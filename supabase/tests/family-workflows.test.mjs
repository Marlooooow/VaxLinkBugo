// Isolated PostgreSQL tests. Never reads .env or contacts the Supabase project.
// PGlite pgcrypto setup: https://pglite.dev/extensions/#pgcrypto
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';

test('live family transactions, invitations, corrections and access isolation', async (t) => {
  const db = new PGlite({ extensions: { pgcrypto } });
  const staff = '10000000-0000-4000-8000-000000000001';
  const otherStaff = '10000000-0000-4000-8000-000000000002';
  const guardianUser = '10000000-0000-4000-8000-000000000003';
  const facility = '20000000-0000-4000-8000-000000000001';
  const otherFacility = '20000000-0000-4000-8000-000000000002';
  async function asUser(user, work) {
    return db.transaction(async tx => {
      await tx.exec('set local role authenticated');
      await tx.query("select set_config('request.jwt.claim.sub', $1, true)", [user]);
      return work(tx);
    });
  }
  const child = (name, relationship = 'mother') => ({ full_name: name, birth_date: '2025-01-02', sex: 'female', relationship });
  const register = (tx, children, online = false) => tx.query(
    'select public.register_family_with_access($1::jsonb,$2::jsonb,true,$3) as family',
    [{ full_name: 'Test Guardian', sex: 'female', phone: null, email: null, address: 'Test address' }, children, online]);
  try {
    await db.exec(`
      create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth;
      create table auth.users(id uuid primary key);
      create function auth.uid() returns uuid language sql stable as
        $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
      grant usage on schema auth, public to anon, authenticated, service_role;
      grant execute on function auth.uid() to anon, authenticated, service_role;
    `);
    for (const name of ['202608300001_initial_schema.sql', '202608310001_live_family_workflows.sql', '202608310002_family_access_and_corrections.sql', '202609010001_authenticated_app_permissions.sql', '202609010002_structured_names_and_staff.sql', '202609020001_guardian_activation_service_access.sql', '202609020002_reminder_sms_delivery.sql', '202609020003_child_reminder_synchronization.sql']) {
      await db.exec(await readFile(new URL(`../migrations/${name}`, import.meta.url), 'utf8'));
    }
    await db.query('insert into auth.users(id) values ($1),($2),($3)', [staff, otherStaff, guardianUser]);
    await db.query("insert into public.facilities(id,facility_code,name,barangay,city) values ($1,'TEST-A','Test facility A','Test','Test'),($2,'TEST-B','Test facility B','Test','Test')", [facility, otherFacility]);
    await db.query("insert into public.profiles(id,facility_id,username,full_name,role) values ($1,$3,'test.staff.a','Test Staff A','administrator'),($2,$4,'test.staff.b','Test Staff B','health_worker')", [staff,otherStaff,facility,otherFacility]);
    await t.test('authenticated app permissions reach RLS without opening audited tables', async () => {
      const privileges = (await db.query(`select
        has_table_privilege('authenticated','public.profiles','select') as profile_read,
        has_table_privilege('authenticated','public.guardians','update') as guardian_write,
        has_table_privilege('authenticated','public.profiles','update') as profile_write,
        has_table_privilege('authenticated','public.advisory_insights','update') as insight_update,
        has_table_privilege('authenticated','public.reminder_preferences','insert,update') as preference_write,
        has_table_privilege('authenticated','public.reminder_follow_ups','insert') as follow_up_insert`)).rows[0];
      assert.equal(privileges.profile_read,true);
      assert.equal(privileges.guardian_write,false);
      assert.equal(privileges.profile_write,false);
      assert.equal(privileges.insight_update,true);
      assert.equal(privileges.preference_write,true);
      assert.equal(privileges.follow_up_insert,true);
    });
    let family;
    await t.test('structured names and guardian birth date are stored with a compatible display name', async () => {
      const result = (await asUser(staff,tx => tx.query(
        'select public.register_family_with_access($1::jsonb,$2::jsonb,true,false) as family',
        [{first_name:'Jane',middle_name:'Q',last_name:'Public',suffix:'Jr.',birth_date:'1995-04-12',sex:'female',address:'Bugo'},
          [{first_name:'Baby',middle_name:null,last_name:'Public',suffix:null,full_name:'ignored',birth_date:'2026-01-02',sex:'female',relationship:'mother'}]],
      ))).rows[0].family;
      assert.equal(result.full_name,'Jane Q Public Jr.');
      assert.equal(result.birth_date,'1995-04-12');
      assert.equal(result.guardian_child_links[0].children.full_name,'Baby Public');
      assert.equal(result.guardian_child_links[0].children.first_name,'Baby');
      const synced = (await db.query(`select vaccine_id, status from reminders
        where child_id = $1 and vaccine_id in ('bcg','hepatitis_b') order by vaccine_id`,
        [result.guardian_child_links[0].child_id])).rows;
      assert.deepEqual(synced, [
        { vaccine_id: 'bcg', status: 'overdue' },
        { vaccine_id: 'hepatitis_b', status: 'overdue' },
      ]);
    });
    await t.test('an administrator can invite a nurse with a facility audit record', async () => {
      const result = (await asUser(staff,tx => tx.query(
        'select public.register_staff_member($1::jsonb) as result',
        [{first_name:'Nora',middle_name:'A',last_name:'Nurse',staff_type:'nurse',license_number:'RN-TEST'}],
      ))).rows[0].result;
      assert.equal(result.staff.full_name,'Nora A Nurse');
      assert.equal(result.staff.status,'invitation_pending');
      assert.match(result.invitation.activation_code,/^STF-ACT-[0-9A-F]{32}$/);
      assert.equal(result.invitation.activation_code_hash,undefined);
      assert.equal((await db.query("select count(*)::int as n from audit_logs where action='staff_invited' and entity_id=$1",[result.staff.id])).rows[0].n,1);
      assert.equal((await asUser(otherStaff,tx => tx.query('select id from staff_members'))).rows.length,0);
      assert.equal((await db.query("select has_function_privilege('authenticated','public.activate_staff_profile(uuid,uuid,text)','execute') as allowed")).rows[0].allowed,false);
    });
    await t.test('one registration commits two children and an invitation without creating a login', async () => {
      family = (await asUser(staff, tx => register(tx,[child('Test Child One'),child('Test Child Two')],true))).rows[0].family;
      assert.equal(family.guardian_child_links.length,2);
      assert.equal(family.profile_id,null);
      assert.equal(family.access_status,'invitation_pending');
      assert.match(family.issued_invitation.activation_code,/^ACT-[0-9A-F]{32}$/);
      assert.equal(family.issued_invitation.activation_code_hash,undefined);
      const stored = (await db.query('select * from guardian_invitations where id=$1',[family.issued_invitation.id])).rows[0];
      assert.equal(stored.activation_code_hash,createHash('sha256').update(family.issued_invitation.activation_code).digest('hex'));
      const audit = (await db.query('select new_values from audit_logs')).rows;
      assert.ok(!JSON.stringify(audit).includes(family.issued_invitation.activation_code));
    });
    await t.test('invalid second child rolls back the guardian and first child', async () => {
      const before = (await db.query('select count(*)::int as n from guardians')).rows[0].n;
      await assert.rejects(asUser(staff,tx => register(tx,[child('Rollback child'),{...child('Invalid'),sex:'invalid'}])),/valid child/);
      assert.equal((await db.query('select count(*)::int as n from guardians')).rows[0].n,before);
      assert.equal((await db.query("select count(*)::int as n from children where full_name='Rollback child'")).rows[0].n,0);
    });
    await t.test('other facility staff cannot read or modify this family', async () => {
      const visible = await asUser(otherStaff,tx => tx.query('select id from guardians where id=$1',[family.id]));
      assert.equal(visible.rows.length,0);
      await assert.rejects(asUser(otherStaff,tx => tx.query('select add_family_child($1,$2,true)',[family.id,child('Unauthorized')])),/Not authorized/);
      await assert.rejects(asUser(otherStaff,tx => tx.query('select issue_guardian_invitation($1)',[family.id])),/Not authorized/);
    });
    await t.test('direct REST writes cannot bypass audit transactions or promote staff', async () => {
      await assert.rejects(asUser(staff,tx => tx.query("update guardians set full_name='Bypass' where id=$1",[family.id])),/permission denied/);
      await assert.rejects(
        asUser(staff,tx => tx.query("update profiles set role='administrator' where id=$1 returning id",[staff])),
        /permission denied/,
      );
      for (const role of ['anon','authenticated']) {
        assert.equal((await db.query("select has_function_privilege($1,'public.activate_guardian_profile(uuid,uuid,text)','execute') as allowed",[role])).rows[0].allowed,false);
      }
      assert.equal((await db.query("select has_function_privilege('service_role','public.activate_guardian_profile(uuid,uuid,text)','execute') as allowed")).rows[0].allowed,true);
      for (const table of ['guardian_invitations','guardians','facilities','profiles']) {
        assert.equal((await db.query("select has_table_privilege('service_role',$1,'select') as allowed",[`public.${table}`])).rows[0].allowed,true);
        assert.equal((await db.query("select has_table_privilege('service_role',$1,'insert,update,delete') as allowed",[`public.${table}`])).rows[0].allowed,false);
      }
      assert.equal((await db.query("select has_table_privilege('service_role','public.reminder_sms_deliveries','select,insert,update') as allowed")).rows[0].allowed,true);
      assert.equal((await db.query("select has_table_privilege('authenticated','public.reminder_sms_deliveries','insert,update,delete') as allowed")).rows[0].allowed,false);
      await assert.rejects(asUser(staff,tx => tx.query('select register_family($1,$2,true)',[{full_name:'Bypass',sex:'female'},[child('Bypass child')]])),/permission denied/);
    });
    await t.test('reissuing revokes the old code and activation can only be consumed once', async () => {
      const issued = (await asUser(staff,tx => tx.query('select issue_guardian_invitation($1) as result',[family.id]))).rows[0].result;
      assert.equal((await db.query('select status from guardian_invitations where id=$1',[family.issued_invitation.id])).rows[0].status,'revoked');
      await db.query('select activate_guardian_profile($1,$2,$3)',[issued.invitation.id,guardianUser,'test.guardian']);
      await assert.rejects(db.query('select activate_guardian_profile($1,$2,$3)',[issued.invitation.id,guardianUser,'test.guardian']),/no longer available/);
      assert.equal((await asUser(guardianUser,tx => tx.query('select id from children'))).rows.length,2);
      await assert.rejects(asUser(staff,tx => tx.query('select issue_guardian_invitation($1)',[family.id])),/already linked/);
    });
    await t.test('guardian requests can be approved once and rejected without creating a child', async () => {
      const requestId = (await asUser(guardianUser,tx => tx.query('select submit_family_child_request($1) as id',[child('Requested Child')]))).rows[0].id;
      await assert.rejects(asUser(guardianUser,tx => tx.query('select submit_family_child_request($1)',[child('Requested Child')])),/pending request already exists/);
      await assert.rejects(asUser(guardianUser,tx => tx.query('select submit_family_child_request($1)',[child('Invalid relationship','uncle')])),/guardian sex/);
      await assert.rejects(asUser(guardianUser,tx => tx.query('select review_family_child_request($1,true,$2)',[requestId,''])),/Not authorized/);
      await asUser(staff,tx => tx.query('select review_family_child_request($1,true,$2)',[requestId,'Verified documents']));
      await assert.rejects(asUser(staff,tx => tx.query('select review_family_child_request($1,true,$2)',[requestId,'Again'])),/already been reviewed/);
      assert.equal((await db.query("select count(*)::int as n from children where full_name='Requested Child'")).rows[0].n,1);
      const rejectedId = (await asUser(guardianUser,tx => tx.query('select submit_family_child_request($1) as id',[child('Rejected Child')]))).rows[0].id;
      await assert.rejects(asUser(staff,tx => tx.query('select review_family_child_request($1,false,$2)',[rejectedId,''])),/reason/);
      await asUser(staff,tx => tx.query('select review_family_child_request($1,false,$2)',[rejectedId,'Unable to verify']));
      assert.equal((await db.query("select count(*)::int as n from children where full_name='Rejected Child'")).rows[0].n,0);
    });
    await t.test('corrections preserve actor, previous values, login status and primary link', async () => {
      const result = (await asUser(staff,tx => tx.query('select correct_guardian_details($1,$2,$3) as result',[
        family.id,{full_name:'Corrected Guardian',sex:'female',phone:'09123456789',address:'Corrected address'},'Name spelling']))).rows[0].result;
      assert.equal(result.correction.corrected_by,staff);
      assert.equal(result.correction.previous_values.full_name,'Test Guardian');
      assert.equal(result.guardian.access_status,'active');
      assert.equal(result.guardian.profile_id,guardianUser);
      const target = family.guardian_child_links[0];
      const corrected = (await asUser(staff,tx => tx.query('select correct_child_details($1,$2,$3,$4) as result',[
        target.child_id,family.id,child('Corrected Child','aunt'),'Relationship correction']))).rows[0].result;
      assert.equal(corrected.link.relationship,'aunt');
      assert.equal(corrected.link.is_primary,target.is_primary);
      assert.equal(corrected.correction.previous_values.guardian_child_link.relationship,'mother');
      assert.equal(corrected.correction.corrected_by,staff);
      await assert.rejects(asUser(staff,tx => tx.query('select correct_child_details($1,$2,$3,$4)',[
        target.child_id,family.id,child('Corrected Child','uncle'),'Invalid relationship'])),/guardian sex/);
    });
    await t.test('a shared child correction changes only the selected guardian relationship', async () => {
      const other = (await asUser(staff,tx => register(tx,[child('Other family child')]))).rows[0].family;
      const target = family.guardian_child_links[0].child_id;
      // Existing verified second-guardian link is an isolated test fixture.
      await db.query("insert into guardian_child_links(guardian_id,child_id,relationship,status,is_primary) values ($1,$2,'mother','approved',false)",[other.id,target]);
      const result = (await asUser(staff,tx => tx.query('select correct_child_details($1,$2,$3,$4) as result',[
        target,other.id,child('Pair-scoped child','grandmother'),'Verified relationship']))).rows[0].result;
      assert.equal(result.link.relationship,'grandmother');
      assert.equal(result.link.is_primary,false);
      assert.equal((await db.query('select relationship from guardian_child_links where guardian_id=$1 and child_id=$2',[family.id,target])).rows[0].relationship,'aunt');
      assert.equal((await asUser(guardianUser,tx => tx.query('select id from children'))).rows.length,3);
    });
    await t.test('guardian sex corrections also normalize pending requests and preserve their audit values', async () => {
      const requestId = (await asUser(guardianUser,tx => tx.query('select submit_family_child_request($1) as id',[child('Pending during correction','aunt')]))).rows[0].id;
      const result = (await asUser(staff,tx => tx.query('select correct_guardian_details($1,$2,$3) as result',[
        family.id,{full_name:'Corrected Guardian',sex:'male',phone:null,address:'Bugo'},'Correct demographic field']))).rows[0].result;
      assert.equal(result.correction.previous_values.pending_requests[0].relationship,'aunt');
      assert.equal(result.correction.updated_values.pending_requests[0].relationship,'uncle');
      assert.equal((await db.query('select relationship from child_link_requests where id=$1',[requestId])).rows[0].relationship,'uncle');
      await asUser(staff,tx => tx.query('select review_family_child_request($1,true,$2)',[requestId,'Verified after correction']));
    });
    await t.test('expired invitations cannot activate profiles or change family access', async () => {
      const expired = (await asUser(staff,tx => register(tx,[child('Expired code child')],true))).rows[0].family;
      await db.query("update guardian_invitations set expires_at=now()-interval '1 day' where id=$1",[expired.issued_invitation.id]);
      await assert.rejects(db.query('select activate_guardian_profile($1,$2,$3)',[expired.issued_invitation.id,guardianUser,'expired.guardian']),/no longer available/);
      assert.equal((await db.query('select profile_id from guardians where id=$1',[expired.id])).rows[0].profile_id,null);
    });
    await t.test('facility audit records are unavailable to other facilities and guardians', async () => {
      assert.ok((await asUser(staff,tx => tx.query('select id from audit_logs'))).rows.length > 0);
      assert.equal((await asUser(otherStaff,tx => tx.query('select id from audit_logs'))).rows.length,0);
      assert.equal((await asUser(guardianUser,tx => tx.query('select id from audit_logs'))).rows.length,0);
    });
    await t.test('guardians can acknowledge but cannot rewrite their vaccination reminders', async () => {
      await db.query("insert into vaccine_definitions(id,vaccine_code,name) values ('test-vaccine','TEST','Test vaccine')");
      const reminder = (await db.query("insert into reminders(reminder_code,guardian_id,child_id,vaccine_id,dose_number,due_on,status) values ('TEST-REMINDER',$1,$2,'test-vaccine',1,current_date,'due_today') returning id",[family.id,family.guardian_child_links[0].child_id])).rows[0].id;
      await asUser(guardianUser,tx => tx.query('update reminders set is_read=true where id=$1',[reminder]));
      await assert.rejects(asUser(guardianUser,tx => tx.query("update reminders set due_on=current_date+7 where id=$1",[reminder])),/Not authorized/);
      await assert.rejects(asUser(guardianUser,tx => tx.query("update reminders set status='completed' where id=$1",[reminder])),/Not authorized/);
      for (const action of ['mock_sms','printed_list']) {
        await assert.rejects(asUser(staff,tx => tx.query("insert into reminder_follow_ups(follow_up_code,reminder_id,child_id,action,outcome,performed_by) values ($1,$2,$3,$4,'reminder_sent',$5)",[`BLOCKED-${action}`,reminder,family.guardian_child_links[0].child_id,action,staff])),/row-level security/);
      }
      assert.equal((await db.query('select count(*)::int as n from reminder_follow_ups')).rows[0].n,0);
    });
    await t.test('guardian reminder sync is available for live refreshes', async () => {
      await asUser(guardianUser, async tx => {
        const sync = await tx.query('select public.sync_guardian_reminders($1) as count', [family.id]);
        assert.ok(sync.rows[0].count >= 1);
      });
    });
    await t.test('disabled guardian cannot read children', async () => {
      await db.query('update profiles set active=false where id=$1',[guardianUser]);
      assert.equal((await asUser(guardianUser,tx => tx.query('select id from children'))).rows.length,0);
      await assert.rejects(asUser(guardianUser,tx => tx.query('select submit_family_child_request($1)',[child('Disabled')])),/Not authorized/);
    });
  } finally { await db.close(); }
});
