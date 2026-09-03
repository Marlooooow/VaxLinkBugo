import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { ACCOUNT_SPECS, FACILITY_ID, SEED_ID, buildDemoSeed, demoId, addDays, addMonths } from '../seeds/demo-data.mjs';

test('synthetic Supabase seed: relationships, chronology, isolation and safe reruns',async t => {
  assert.deepEqual(
    Object.fromEntries(ACCOUNT_SPECS.map(account => [account.username, account.password])),
    {
      'demo.admin': 'admin123',
      'demo.healthworker': 'healthworkeradmin123',
      'demo.maria': 'maria123',
      'demo.paolo': 'paolo123',
      'demo.grace': 'grace123',
    },
  );
  const db = new PGlite({extensions:{pgcrypto}});
  const accounts = Object.fromEntries(ACCOUNT_SPECS.map(s => [s.key,demoId(`auth:${s.key}`)]));
  const seed = buildDemoSeed(accounts,'2026-08-31');
  async function asUser(key,sql) {
    return db.transaction(async tx => {
      await tx.exec('set local role authenticated');
      await tx.query("select set_config('request.jwt.claim.sub',$1,true)",[accounts[key]]);
      return (await tx.query(sql)).rows;
    });
  }
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key);
      create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
      grant usage on schema auth,public to anon,authenticated,service_role;
      grant execute on function auth.uid() to anon,authenticated,service_role;
      `);
  for (const name of ['202608300001_initial_schema.sql','202608310001_live_family_workflows.sql','202608310002_family_access_and_corrections.sql','202609010001_authenticated_app_permissions.sql','202609010002_structured_names_and_staff.sql','202609020001_guardian_activation_service_access.sql','202609020002_reminder_sms_delivery.sql','202609020003_child_reminder_synchronization.sql']) {
      await db.exec(await readFile(new URL(`../migrations/${name}`,import.meta.url),'utf8'));
    }
    for (const id of Object.values(accounts)) await db.query('insert into auth.users(id) values ($1)',[id]);
    await t.test('applies all fixtures using the real schema and constraints',async () => {
      await db.exec(seed.sql);
      assert.equal(seed.counts.guardians,4);
      assert.equal(seed.counts.children,8);
      assert.equal(seed.counts.vaccination_records,61);
      for (const [table,count] of Object.entries(seed.counts)) assert.equal((await db.query(`select count(*)::int as n from ${table}`)).rows[0].n,count,table);
    });
    await t.test('guardian logins see only linked children and reminders; staff sees demo families',async () => {
      for (const [key,count] of [['maria',5],['paolo',1],['grace',1],['staff',8]]) {
        assert.equal((await asUser(key,'select id from children')).length,count);
        const reminders = await asUser(key,'select guardian_id from reminders');
        if(key !== 'staff') assert.ok(reminders.every(r => r.guardian_id === demoId(key)));
      }
      assert.equal((await asUser('staff','select id from guardians')).length,4);
      assert.equal((await asUser('maria','select id from child_link_requests')).length,1);
      assert.equal((await asUser('paolo','select id from child_link_requests')).length,0);
    });
    await t.test('history dates, prerequisite doses, and reminder states agree',async () => {
      for (const record of seed.data.vaccination_records) {
        const child = seed.data.children.find(c => c.id===record.child_id);
        assert.ok(record.administered_on>=child.birth_date && record.administered_on<=seed.anchorDate);
        assert.equal(record.source,'previous_record');
        if(record.dose_number>1) {
          const prev = seed.data.vaccination_records.find(r => r.child_id===record.child_id && r.vaccine_id===record.vaccine_id && r.dose_number===record.dose_number-1);
          assert.ok(prev);
          const minimum = record.vaccine_id==='ipv' ? addMonths(prev.administered_on,4) : addDays(prev.administered_on,28);
          assert.ok(record.administered_on>=minimum);
        }
      }
      for(const reminder of seed.data.reminders) {
        const history = seed.data.vaccination_records.filter(r => r.child_id===reminder.child_id && r.vaccine_id===reminder.vaccine_id);
        assert.equal(reminder.status==='completed',history.some(r => r.dose_number===reminder.dose_number));
        if(reminder.dose_number>1) assert.ok(history.some(r => r.dose_number===reminder.dose_number-1));
      }
      for(const status of ['completed','due_today','overdue','upcoming']) assert.ok(seed.data.reminders.some(r => r.status===status));
    });
    await t.test('appointments, earlier offer, and source reminders refer to the same child/dose',async () => {
      const rows = (await db.query(`select a.child_id,a.guardian_id,a.vaccine_id,a.dose_number,a.pnip_due_date,
        r.child_id as rc,r.guardian_id as rg,r.vaccine_id as rv,r.dose_number as rd,r.due_on
        from appointments a join reminders r on r.id=a.reminder_id and r.appointment_id=a.id`)).rows;
      assert.equal(rows.length,4);
      for(const row of rows) { assert.equal(row.child_id,row.rc); assert.equal(row.guardian_id,row.rg); assert.equal(row.vaccine_id,row.rv); assert.equal(row.dose_number,row.rd); assert.deepEqual(row.pnip_due_date,row.due_on); }
      const offer = seed.data.appointment_offers[0];
      assert.ok(offer.expires_at < offer.offered_for);
      assert.ok(offer.offered_for < seed.data.appointments[0].scheduled_for);
    });
    await t.test('stock balances reconcile and delivery/provider activity is not fabricated',async () => {
      for(const batch of seed.data.vaccine_batches) {
        const movement = seed.data.inventory_transactions.find(r => r.batch_id===batch.id);
        assert.equal(batch.quantity,movement.quantity_delta);
        assert.equal(movement.balance_after-movement.balance_before,movement.quantity_delta);
      }
      assert.ok(seed.data.reminder_preferences.every(r => !r.sms_enabled && !r.email_enabled));
      assert.ok(seed.data.guardians.every(r => r.phone===null && r.email===null));
      assert.equal((await db.query('select count(*)::int as n from reminder_follow_ups')).rows[0].n,0);
      assert.equal(seed.data.advisory_insights[0].analysis_provider,'synthetic_seed');
    });
    await t.test('another facility cannot access demo patients or inventory',async () => {
      const other = demoId('other-staff');
      await db.query('insert into auth.users(id) values ($1)',[other]);
      await db.query("insert into facilities(facility_code,name,barangay,city) values ('OTHER','Other','Other','Other') returning id").then(async result => {
        await db.query("insert into profiles(id,facility_id,username,full_name,role) values ($1,$2,'other.staff','Other','health_worker')",[other,result.rows[0].id]);
      });
      accounts.other=other;
      assert.equal((await asUser('other','select id from children')).length,0);
      assert.equal((await asUser('other','select id from vaccine_inventory')).length,0);
    });
    await t.test('rerun preserves edited stock, read status, profile changes, dates and other facilities',async () => {
      await db.query('update vaccine_batches set quantity=2 where id=$1',[demoId('batch:bcg')]);
      await db.query('update reminders set is_read=true where child_id=$1',[demoId('sofia')]);
      await db.query("update guardians set full_name='Edited demo name' where id=$1",[demoId('maria')]);
      await db.exec(buildDemoSeed(accounts,'2026-09-30').sql);
      assert.equal((await db.query('select quantity from vaccine_batches where id=$1',[demoId('batch:bcg')])).rows[0].quantity,2);
      assert.equal((await db.query('select full_name from guardians where id=$1',[demoId('maria')])).rows[0].full_name,'Edited demo name');
      assert.ok((await db.query('select is_read from reminders where child_id=$1',[demoId('sofia')])).rows.every(r => r.is_read));
      assert.equal((await db.query("select new_values->>'anchor_date' as date from audit_logs where entity_id=$1",[SEED_ID])).rows[0].date,'2026-08-31');
      assert.equal((await db.query('select count(*)::int as n from children where facility_id=$1',[FACILITY_ID])).rows[0].n,8);
      assert.equal((await db.query("select count(*)::int as n from facilities where facility_code='OTHER'")).rows[0].n,1);
    });
  } finally { await db.close(); }
});
