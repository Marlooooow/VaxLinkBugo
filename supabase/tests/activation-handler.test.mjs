// The same handler used by the Edge Function, with an isolated Auth/DB adapter.
// No credentials, environment files, or remote network calls are used.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createActivationHandler } from '../functions/activate-guardian-access/handler.ts';

const code = 'ACT-0123456789ABCDEF0123456789ABCDEF';
const valid = { activation_code: code, username: 'test.guardian', password: 'test-password-123' };
function harness(options = {}) {
  const calls = { created: [], deleted: [], rpc: [], filters: [] };
  let guardianReads = 0;
  const ok = data => ({ data, error: null });
  const admin = {
    from(table) {
      const query = {
        select() { return query; },
        eq(column, value) { calls.filters.push({ table, column, value }); return query; },
        async maybeSingle() {
          if (table === 'guardian_invitations') return options.invitationError ? { data: null, error: { message: 'private SQL detail' } } : ok({ id: 'invite', guardian_id: 'guardian', status: 'pending', expires_at: '2099-01-01T00:00:00Z', ...options.invitation });
          if (table === 'guardians') {
            guardianReads++;
            if (guardianReads > 1) return options.checkError ? { data: null, error: {} } : ok({ profile_id: options.committed ? 'new-user' : null });
            return ok({ profile_id: null, access_status: 'invitation_pending', facility_id: 'clinic', ...options.guardian });
          }
          if (table === 'facilities') return ok({ active: options.facilityActive ?? true });
          if (table === 'profiles') return ok(options.usernameTaken ? { id: 'existing' } : null);
          throw new Error('Unexpected table');
        },
      };
      return query;
    },
    auth: { admin: {
      async createUser(input) { calls.created.push(input); return { data: { user: { id: 'new-user' } }, error: null }; },
      async deleteUser(id) { calls.deleted.push(id); return { error: options.cleanupError ? {} : null }; },
    } },
    async rpc(name, args) {
      calls.rpc.push({ name, args });
      if (options.throwOnRpc) throw new Error('Transport failed');
      return { error: options.linkError ?? null };
    },
  };
  const handler = createActivationHandler(() => admin);
  return { calls, handler, send: (body = valid) => handler(new Request('https://local.test/activate', { method: 'POST', body: JSON.stringify(body) })) };
}

test('activation supports preflight but refuses other methods without touching accounts', async () => {
  const { calls, handler } = harness();
  const response = await handler(new Request('https://local.test', { method: 'OPTIONS' }));
  assert.equal(response.status, 204);
  assert.ok(response.headers.get('Access-Control-Allow-Headers').includes('apikey'));
  assert.equal((await handler(new Request('https://local.test'))).status, 405);
  assert.equal(calls.created.length, 0);
});
test('activation rejects malformed, oversized, and invalid credential input locally', async () => {
  const { calls, handler, send } = harness();
  for (const body of [null, [], {}, { ...valid, activation_code: 'ACT-000101' }, { ...valid, username: 'a@b.com' }, { ...valid, password: 'short' }, { ...valid, password: 'x'.repeat(129) }, { ...valid, padding: 'x'.repeat(5000) }]) {
    assert.equal((await send(body)).status, 400);
  }
  assert.equal((await handler(new Request('https://local.test', { method: 'POST', body: '{' }))).status, 400);
  assert.equal(calls.created.length, 0);
});
test('activation hashes the code and ignores submitted guardian, facility and role', async () => {
  const { calls, send } = harness();
  const response = await send({ ...valid, activation_code: ` ${code.toLowerCase()} `, username: ' TEST.GUARDIAN ', guardian_id: 'forged', role: 'administrator', facility_id: 'forged' });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.deepEqual(await response.json(), { activated: true });
  assert.equal(calls.filters[0].value, createHash('sha256').update(code).digest('hex'));
  assert.equal(calls.created[0].email, 'test.guardian@auth.vaxlink-bugo.local');
  assert.deepEqual(calls.rpc[0], { name: 'activate_guardian_profile', args: { invitation_id: 'invite', auth_user_id: 'new-user', requested_username: 'test.guardian' } });
  assert.ok(!JSON.stringify(calls).includes('forged'));
});
test('expired, used, disabled and already-linked invitations cannot create an Auth account', async () => {
  for (const options of [{ invitation: { expires_at: '2020-01-01' } }, { invitation: { status: 'used' } }, { invitation: { status: 'revoked' } }, { guardian: { access_status: 'disabled' } }, { guardian: { profile_id: 'existing' } }, { facilityActive: false }]) {
    const { calls, send } = harness(options);
    assert.equal((await send()).status, 400);
    assert.equal(calls.created.length, 0);
  }
});
test('database lookup errors stay generic and do not create accounts', async () => {
  const { calls, send } = harness({ invitationError: true });
  const response = await send();
  assert.equal(response.status, 503);
  assert.ok(!(await response.text()).includes('SQL'));
  assert.equal(calls.created.length, 0);
});
test('an existing username is reported before account creation', async () => {
  const { calls, send } = harness({ usernameTaken: true });
  const response = await send();
  assert.equal(response.status, 409);
  assert.match((await response.json()).error, /username is already/);
  assert.equal(calls.created.length, 0);
});
test('lost response after a committed activation returns success and preserves the account', async () => {
  const { calls, send } = harness({ linkError: { code: '', message: 'network' }, committed: true });
  assert.equal((await send()).status, 200);
  assert.deepEqual(calls.deleted, []);
});
test('uncertain activation or failed verification never deletes the created account', async () => {
  for (const options of [{ linkError: { code: '', message: 'network' } }, { linkError: { code: 'P0001' }, checkError: true }, { throwOnRpc: true }]) {
    const { calls, send } = harness(options);
    const response = await send();
    assert.equal(response.status, 503);
    assert.match((await response.json()).error, /Try signing in/);
    assert.deepEqual(calls.deleted, []);
  }
});
test('a confirmed database rollback cleans up only the newly created account', async () => {
  const { calls, send } = harness({ linkError: { code: 'P0001', message: 'Invitation no longer available' } });
  assert.equal((await send()).status, 409);
  assert.deepEqual(calls.deleted, ['new-user']);
});
