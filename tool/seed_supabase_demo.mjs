// Run manually from the project root. Never import this server-only tool in Flutter.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, writeFile, mkdir, open, unlink } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';
import { ACCOUNT_SPECS, FACILITY_ID, PROJECT_REF, SEED_ID, buildDemoSeed, demoId } from '../supabase/seeds/demo-data.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const exec = promisify(execFile);
const privateFile = join(root, '.env.supabase-demo-accounts.json');
const lockFile = join(root, '.dart_tool', 'supabase-demo-seed.lock');
const flags = process.argv.slice(2);
const applying = flags.includes('--apply');
const verifying = flags.includes('--verify');
const syncingPasswords = flags.includes('--sync-passwords');
const ensuringAdmin = flags.includes('--ensure-admin');
const project = flags[flags.indexOf('--project-ref') + 1];
const dateNow = () => new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 10);
const url = `https://${PROJECT_REF}.supabase.co`;
const clientOptions = { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } };

function parseCliJson(output) {
  // Login-role progress may precede the JSON response; never echo raw key output.
  const lines = output.trim().split('\n');
  const start = lines.findIndex(line => /^[\[{]/.test(line.trim()));
  if (start < 0) throw new Error('The Supabase CLI did not return JSON.');
  return JSON.parse(lines.slice(start).join('\n'));
}
async function cli(args) {
  const npx = join(dirname(process.execPath), 'node_modules', 'npm', 'bin', 'npx-cli.js');

  try {
    const { stdout } = await exec(
      process.execPath,
      [npx, '--no-install', 'supabase', ...args, '--output', 'json'],
      {
        cwd: root,
        maxBuffer: 4 * 1024 * 1024,
        timeout: 120000,
      }
    );

    return parseCliJson(stdout);
  } catch {
    throw new Error(
      `Supabase ${args.slice(0, 2).join(' ')} failed. Check CLI login, access and connectivity; no secret output was logged.`
    );
  }
}
async function query(sql) {
  const result = await cli(['db', 'query', sql, '--linked', '--project-ref', PROJECT_REF]);
  const rows = Array.isArray(result) ? result : result.rows;
  if (!Array.isArray(rows)) throw new Error('Unexpected database query response.');
  return rows;
}
async function loadPrivateState() {
  try { return JSON.parse(await readFile(privateFile, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return null; throw new Error('Unable to read the private demo account file.'); }
}
async function savePrivateState(state) {
  await writeFile(privateFile, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
}
async function verifyAccounts(state, publicKey) {
  const results = [];
  for (const spec of ACCOUNT_SPECS) {
    const account = state.accounts[spec.key];
    const client = createClient(url, publicKey, clientOptions);
    const { data: signedIn, error } = await client.auth.signInWithPassword({ email: account.email, password: account.password });
    if (error || signedIn.user?.id !== account.id) throw new Error(`Demo login verification failed for ${spec.username}; no password was changed.`);
    try {
      const profile = await client.from('profiles').select('role,facility_id').eq('id', account.id).single();
      if (profile.error || profile.data.role !== spec.role || profile.data.facility_id !== FACILITY_ID) {
        const reason = profile.error
          ? `${profile.error.code ?? 'unknown'}: ${profile.error.message}`
          : 'the returned role or facility does not match the demo manifest';
        throw new Error(`Profile verification failed for ${spec.username} (${reason}).`);
      }
      const children = await client.from('children').select('id');
      const reminders = await client.from('reminders').select('id,guardian_id,status');
      if (children.error || reminders.error) throw new Error(`Record access failed for ${spec.username}.`);
      const expectedIds = spec.role !== 'guardian' ? null : new Set(
        state.childKeys[spec.key].map(demoId));
      // Verify initial seed children remain visible, but allow legitimately added children.
      if (expectedIds && [...expectedIds].some(id => !children.data.some(row => row.id === id))) {
        throw new Error(`Seed child access is incomplete for ${spec.username}.`);
      }
      if (expectedIds && reminders.data.some(row => row.guardian_id !== demoId(spec.key))) {
        throw new Error(`Family isolation check failed for ${spec.username}.`);
      }
      results.push({
        username: spec.username, login: 'passed', visibleChildren: children.data.length,
        reminders: reminders.data.length
      });
    } finally { await client.auth.signOut({ scope: 'local' }); }
  }
  return results;
}

async function main() {
  if (!applying && !verifying && !syncingPasswords && !ensuringAdmin) {
    const accounts = Object.fromEntries(ACCOUNT_SPECS.map(spec => [spec.key, demoId(`auth:${spec.key}`)]));
    const plan = buildDemoSeed(accounts, dateNow());
    console.log(JSON.stringify({
      mode: 'preview-only (no network or writes)', project: PROJECT_REF, counts: plan.counts,
      apply: 'node tool/seed_supabase_demo.mjs --apply --project-ref ' + PROJECT_REF
    }, null, 2));
    return;
  }
  const selectedModeCount = [applying, verifying, syncingPasswords, ensuringAdmin]
    .filter(Boolean).length;
  if (!flags.includes('--project-ref') || project !== PROJECT_REF ||
      selectedModeCount !== 1) {
    throw new Error('Choose exactly one mode and explicitly confirm the VaxLinkBugo project reference.');
  }
  const linked = (await readFile(join(root, 'supabase', '.temp', 'project-ref'), 'utf8')).trim();
  if (linked !== PROJECT_REF) throw new Error('The linked Supabase project does not match VaxLinkBugo.');
  await mkdir(join(root, '.dart_tool'), { recursive: true });
  const lock = await open(lockFile, 'wx');
  try {
    const ready = (await query("select to_regprocedure('public.register_family_with_access(jsonb,jsonb,boolean,boolean)') is not null as ready"))[0];
    if (!ready?.ready) throw new Error('Apply both tested family migrations before seeding.');
    const markers = await query(`select new_values from public.audit_logs where entity_type='demo_seed' and entity_id='${SEED_ID}' and action='demo_seed_initialized'`);
    let state = await loadPrivateState();
    if (state && (state.project !== PROJECT_REF || state.seed !== SEED_ID)) throw new Error('The private account file belongs to a different seed/project.');
    if ((verifying || syncingPasswords || ensuringAdmin || markers.length) && !state) throw new Error('The private demo account file is required. Existing data/accounts were not changed.');
    const keysResult = await cli(['projects', 'api-keys', '--project-ref', PROJECT_REF, '--output', 'json']);
    const keys = Array.isArray(keysResult) ? keysResult : keysResult.keys;
    const serverKey = keys?.find(k => k.name === 'service_role')?.api_key;
    const publicKey = keys?.find(k => k.name === 'anon')?.api_key;
    if (!serverKey?.startsWith('eyJ') || !publicKey?.startsWith('eyJ')) throw new Error('Server and public API credentials are unavailable. Keys were not saved.');
    const admin = createClient(url, serverKey, clientOptions);
    if (ensuringAdmin) {
      if (markers.length !== 1) throw new Error('The expected demo dataset marker is missing. No administrator was created.');
      const spec = ACCOUNT_SPECS.find(item => item.key === 'admin');
      if (!spec) throw new Error('The demo administrator manifest is missing.');
      const email = `${spec.username}@auth.vaxlink-bugo.local`;
      const users = [];
      for (let page = 1; ; page++) {
        const response = await admin.auth.admin.listUsers({ page, perPage: 100 });
        if (response.error) throw new Error('Unable to inspect existing Auth accounts.');
        users.push(...response.data.users);
        if (response.data.users.length < 100) break;
      }
      let user = users.find(item => item.email?.toLowerCase() === email.toLowerCase());
      if (user && user.app_metadata?.vaxlink_demo_seed !== SEED_ID) {
        throw new Error('The demo administrator username belongs to a non-demo account. Nothing was changed.');
      }
      if (!user) {
        const response = await admin.auth.admin.createUser({
          email,
          password: spec.password,
          email_confirm: true,
          app_metadata: { vaxlink_demo_seed: SEED_ID, vaxlink_demo_admin: true },
          user_metadata: { full_name: spec.name, synthetic: true },
        });
        if (response.error || !response.data.user) {
          throw new Error('The demo administrator Auth account could not be created. Rerun the administrator setup.');
        }
        user = response.data.user;
      }
      if (!/^[0-9a-f-]{36}$/i.test(user.id)) throw new Error('The administrator identity is invalid.');
      console.log('Administrator Auth identity verified; checking its application profile.');
      const profile = await query(`select id::text,username,role from public.profiles where id='${user.id}'::uuid`);
      if (profile.length && (profile[0].username !== spec.username || profile[0].role !== spec.role)) {
        throw new Error('The administrator profile conflicts with an existing profile. Nothing was overwritten.');
      }
      if (!profile.length) {
        const staffId = state.accounts.staff?.id;
        if (!/^[0-9a-f-]{36}$/i.test(staffId ?? '')) throw new Error('The saved demo health-worker identity is invalid.');
        console.log('Creating the missing administrator profile and bootstrap audit record.');
        await query(`with new_profile as (
          insert into public.profiles(id,facility_id,username,full_name,first_name,last_name,role,active)
          values('${user.id}'::uuid,'${FACILITY_ID}'::uuid,'${spec.username}','${spec.name}','Bugo','Administrator','administrator',true)
          returning id
        )
          insert into public.audit_logs(actor_id,facility_id,action,entity_type,entity_id,new_values)
          values(null,'${FACILITY_ID}'::uuid,'demo_admin_provisioned','profiles','${user.id}',
            jsonb_build_object('username','${spec.username}','synthetic',true,'provisioned_by','server_demo_tool'))
          returning entity_id;`);
      }
      state.accounts.admin = {
        username: spec.username,
        email,
        password: spec.password,
        name: spec.name,
        role: spec.role,
        id: user.id,
      };
      state.childKeys.admin = [];
      await savePrivateState(state);
      console.log('The separate synthetic administrator is ready. Existing staff and family records were preserved.');
    }
    if (syncingPasswords) {
      if (markers.length !== 1) throw new Error('The expected demo dataset marker is missing. No password was changed.');
      const users = [];
      for (let page = 1; ; page++) {
        const response = await admin.auth.admin.listUsers({ page, perPage: 100 });
        if (response.error) throw new Error('Unable to inspect existing Auth accounts.');
        users.push(...response.data.users);
        if (response.data.users.length < 100) break;
      }
      if (users.length !== ACCOUNT_SPECS.length ||
          users.some(user => user.app_metadata?.vaxlink_demo_seed !== SEED_ID)) {
        throw new Error('Auth accounts no longer match the four-user demo set. No password was changed.');
      }
      // Resolve every expected identity before changing any password. This keeps
      // a missing or mismatched account from causing a predictable partial run.
      const matchedAccounts = ACCOUNT_SPECS.map(spec => {
        const email = `${spec.username}@auth.vaxlink-bugo.local`;
        const user = users.find(
          item => item.email?.toLowerCase() === email.toLowerCase(),
        );
        if (!user) {
          throw new Error(
            `The demo account ${spec.username} is missing. No password was changed.`,
          );
        }
        return { spec, user };
      });
      for (const { spec, user } of matchedAccounts) {
        const response = await admin.auth.admin.updateUserById(user.id, {
          password: spec.password,
        });
        if (response.error) throw new Error(`Password update failed for ${spec.username}. Rerun the password sync.`);
        state.accounts[spec.key].id = user.id;
        state.accounts[spec.key].password = spec.password;
      }
      await savePrivateState(state);
      console.log('Updated the four demo Auth passwords. Application records were not changed.');
    }
    if (!verifying && !markers.length) {
      if (!state) {
        state = {
          project: PROJECT_REF, seed: SEED_ID, anchorDate: dateNow(),
          warning: 'Private synthetic test logins. Do not commit, embed in the app, or use for real patient records.',
          childKeys: { admin: [], maria: ['sofia', 'princess', 'mateo', 'miguel', 'ana'], paolo: ['lia'], grace: ['noah'] },
          accounts: Object.fromEntries(ACCOUNT_SPECS.map(spec => [spec.key, {
            username: spec.username, email: `${spec.username}@auth.vaxlink-bugo.local`,
            password: spec.password, name: spec.name, role: spec.role,
          }]))
        };
        // Persist passwords BEFORE account creation so an interrupted run can resume.
        await savePrivateState(state);
      }
      const users = [];
      for (let page = 1; ; page++) {
        const response = await admin.auth.admin.listUsers({ page, perPage: 100 });
        if (response.error) throw new Error('Unable to inspect existing Auth accounts.');
        users.push(...response.data.users);
        if (response.data.users.length < 100) break;
      }
      // Preflight every account before creating any. Never take over an existing login.
      for (const spec of ACCOUNT_SPECS) {
        const account = state.accounts[spec.key];
        const existing = users.find(u => u.email?.toLowerCase() === account.email.toLowerCase());
        if (existing && existing.app_metadata?.vaxlink_demo_seed !== SEED_ID) {
          throw new Error(`The username ${spec.username} is already used outside this seed. Nothing was overwritten.`);
        }
        if (account.id && existing?.id !== account.id) throw new Error(`Saved identity mismatch for ${spec.username}; refusing to recreate it.`);
      }
      for (const spec of ACCOUNT_SPECS) {
        const account = state.accounts[spec.key];
        let user = users.find(u => u.email?.toLowerCase() === account.email.toLowerCase());
        if (!user) {
          const response = await admin.auth.admin.createUser({
            email: account.email, password: account.password, email_confirm: true,
            app_metadata: { vaxlink_demo_seed: SEED_ID }, user_metadata: { full_name: spec.name, synthetic: true }
          });
          if (response.error || !response.data.user) throw new Error(`Auth creation failed for ${spec.username}; retained private state allows retry. No existing account was deleted.`);
          user = response.data.user;
        }
        account.id = user.id;
        await savePrivateState(state);
      }
      const seed = buildDemoSeed(Object.fromEntries(ACCOUNT_SPECS.map(s => [s.key, state.accounts[s.key].id])), state.anchorDate);
      const sqlPath = join(root, '.dart_tool', 'supabase-demo-seed.sql');
      await writeFile(sqlPath, seed.sql, { mode: 0o600 });
      await cli(['db', 'query', '--file', sqlPath, '--linked', '--project-ref', PROJECT_REF]);
      console.log('Synthetic records committed in one database transaction. No SMS or email was sent.');
    } else if (markers.length) {
      console.log('Seed already exists; preserving all records, dates, balances and account passwords.');
    }
    const results = await verifyAccounts(state, publicKey);
    const saved = await query(`select new_values from public.audit_logs where entity_type='demo_seed' and entity_id='${SEED_ID}' and action='demo_seed_initialized'`);
    if (saved.length !== 1) throw new Error('Seed audit verification failed.');
    console.log(JSON.stringify({
      project: PROJECT_REF, seed: SEED_ID, seedManifest: saved[0].new_values, checks: results,
      privateLoginFile: '.env.supabase-demo-accounts.json'
    }, null, 2));
  } finally {
    await lock.close();
    await unlink(lockFile);
  }
}
main().catch(error => {
  // Never serialize SDK errors, request headers, command arguments, or credentials.
  const text = error instanceof Error ? error.message : 'Unknown seed failure.';
  console.error(text.includes('eyJ') || text.includes('sb_secret_') ? 'Seed failed; credential output withheld.' : text);
  process.exitCode = 1;
});
