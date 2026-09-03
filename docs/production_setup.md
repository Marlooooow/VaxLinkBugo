# Live implementation handoff

Status: **development in progress, not production-ready**. The mock source and
seed data remain available. The exported prototype APK is unchanged. The changes
below have been tested locally. All seven schema migrations, including the family,
authenticated-client, structured-name, and staff migrations, are now applied to
hosted **VaxLinkBugo**. The revised
activation Edge Function has **not** been deployed by this update. A separate
synthetic dataset is now stored in Supabase; see `supabase_demo_data.md` for
accounts, scope, safe reruns and verification.

## Choose a run mode

- `live` is the default mode and the first VS Code launch. A validated public-only
  configuration is bundled with the app, so plain `flutter run` works without
  command-line defines. Missing/invalid configuration fails visibly and does not
  switch to local mock records.
- `mock` remains an explicit opt-in for local demo accounts and records, without
  Supabase: use the preserved Demo launch or `--dart-define=APP_DATA_MODE=mock`.
- `hybrid` initializes Supabase but currently selects mock repositories. It is
  **not live data mode**.
- `live` selects database repositories and removes the demo authentication helpers.
  Unimplemented write workflows report that they are unavailable. They do not
  fall back to mock records or pretend a save succeeded.

In VS Code, choose **VaxLink - Live (Supabase)**, or use plain `flutter run`.
When the public project URL/key changes, regenerate the launch and bundled copy:

```powershell
dart run tool/export_live_config.dart
flutter run
```

The exporter writes only `APP_DATA_MODE`, `SUPABASE_URL`, and
`SUPABASE_ANON_KEY` to the public bundle. Flutter does not load `.env` at runtime.
Do **not** pass the entire `.env` file to Flutter or add it as an app asset.

Only `SUPABASE_URL` and `SUPABASE_ANON_KEY` (publishable or legacy anon key) belong
in the client build. The exporter accepts `SUPABASE_KEY` as a legacy input alias.
Service-role keys, access tokens, database passwords, AI keys, and SMS keys stay
server-side. Rotate any private credentials previously shared in messages.

## Live family workflow implemented locally

- Real family/child reads, scoped to the signed-in guardian or worker's facility.
- Register one guardian with 1–20 children in a single transaction. A failed child
  validation rolls back the guardian and all children in that request.
- Add a child to an existing guardian, with explicit authorization and duplicate
  checks. A matching record is blocked for identity review, never silently merged.
  A dedicated verified existing-child linking/merge workflow remains pending.
- Guardian-submitted child requests; worker approval/rejection with server-owned
  actor IDs, timestamps, and audit records. Approval creates the child/link once.
- Guardian and child corrections, with reasons and before/after records.
  A child relationship belongs to one guardian-child pair; editing it does not
  overwrite another guardian's relationship or change primary-guardian status.
- Guardian sex corrections normalize gendered labels on links and pending requests,
  while retaining the original values in the correction audit.
- Optional one-time activation code at registration, or later issuance/reissue from
  Registered Families. Codes expire after seven days and are stored as SHA-256
  hashes. The raw code is returned only when issued; it is not in database reads
  or audit logs. Reissuing revokes previous pending codes.
- Manual private code handoff only. No SMS or email delivery is claimed. A family
  does not need a login; activation creates one only after the guardian chooses a
  username/password.
- Activation rechecks availability in a transaction, enforces the guardian role,
  and safely handles a lost response without deleting a committed account.
  An uncertain result asks the guardian to try signing in before retrying.
- New registrations capture guardian and child names as first name, optional
  middle name, last name, and optional suffix. Guardian birth date is also saved.
  The compatible `full_name` display remains populated for existing screens.
- `profile_id` is server-managed and remains null for an offline guardian or a
  pending invitation; it is linked only after successful account activation.
  It is intentionally not editable in the registration form.
- A facility-scoped staff registry now supports nurse, midwife, barangay health
  worker, and physician records. Only an administrator can invite staff. The
  one-time code is returned once, its hash is stored, and invite/activation events
  are audited. A separate staff activation client flow remains rollout work.

Registration cannot be blindly retried after an interrupted response: check
Registered Families first. If the registration committed but the code was not
received, issue a new code from the saved family's details.

## Database migrations

Apply these **in order** to a development/staging project:

1. `supabase/migrations/202608300001_initial_schema.sql` — original schema.
2. `supabase/migrations/202608310001_live_family_workflows.sql` — live repository
   boundary, facility/guardian RLS, request transactions, reminder protections.
3. `supabase/migrations/202608310002_family_access_and_corrections.sql` — audited
   family operations, one-time codes, pair-scoped corrections, activation checks,
   and prevention of simulated follow-up delivery writes.
4. `supabase/migrations/202609010001_authenticated_app_permissions.sql` —
   authenticated app grants constrained by row-level security.
5. `supabase/migrations/202609010002_structured_names_and_staff.sql` — structured
   person names, guardian birth date handling, staff registry/invitations,
   administrator checks, and staff audit operations.
6. `supabase/migrations/202609020001_guardian_activation_service_access.sql` —
   minimum read-only table permissions required by the server-side guardian
   activation function; all activation writes remain inside the audited RPC.
7. `supabase/migrations/202609020002_reminder_sms_delivery.sql` — SMS delivery
   attempt records, provider-aware outcomes, and server-only Semaphore access.
8. `supabase/migrations/202609020003_child_reminder_synchronization.sql` —
   idempotent reminder creation when a child is registered or approved.

Do not edit/reapply the original migration on a project that already has it.
These migrations contain **no mock patients or prototype login seeds**. Existing
rows are not deleted. Some former direct REST writes are deliberately revoked in
favor of audited RPCs. Existing audit rows without a facility are not exposed
through the new facility-scoped app policy; retain them for administrator review.

Provision the actual facility and authorized Auth/profile accounts separately.
A worker profile must be active, have role `health_worker` or `administrator`,
and point to an active facility. Username sign-in uses the internal Auth email
`username@auth.vaxlink-bugo.local`; real email sign-in is also accepted.

After applying the migrations to the intended development project, deploy:

```powershell
supabase functions deploy activate-guardian-access
```

Only this activation endpoint uses `verify_jwt=false`, because the guardian has
no session yet. Its authorization is the high-entropy one-time invitation;
`activate_guardian_profile` itself is service-role-only. Do not disable JWT
verification for other functions to make authentication errors disappear.

Before public exposure, add and verify abuse controls/rate limiting (and CAPTCHA
as appropriate), account-recovery procedures, and cleanup/monitoring for orphaned
Auth users after uncertain activation attempts. These tests do not establish
production-scale concurrency or delivery reliability.

## Validation

```powershell
npm ci --ignore-scripts
npm run test:database
npm run test:activation
flutter test --dart-define=APP_DATA_MODE=mock
flutter analyze --no-pub lib test
```

Database tests use isolated PGlite PostgreSQL with pgcrypto. They load the actual
migration SQL, exercise RPC transactions/RLS, and never read `.env` or contact the
hosted project. Activation handler tests use fake Auth/database transports and
Node 22.13+ type stripping; they do not replace Deno Edge runtime or hosted Auth
integration checks. Flutter tests verify live adapters, inline activation errors,
small-screen dialogs, no simulated writes, usable inventory counts, and demo
regressions.

Hosted acceptance checks still required: two facilities, an authorized worker,
a different-facility worker, two unrelated guardian accounts, offline family
registration, multi-child registration, activation/reissue/expiry, duplicate
request rejection, approval/rejection, pair-scoped corrections, and disabled
account denial. Use synthetic staging records, not real patient data.

## Remaining rollout work

1. Clinical transactions: screening, first-visit history, local administration
   with stock deduction, corrections, idempotent retries, and validated
   database-configured scheduling/eligibility. Live history reads work, but the
   current schedule projection still uses the shared deterministic app rules.
2. Verified referrals and external vaccination recording. Live referral operations
   are intentionally unavailable instead of issuing mock verification tokens.
3. Appointment creation/rescheduling, earlier-offer acceptance and queue expiry,
   capacity/stock reservation, and concurrent first-come acceptance. Current live
   appointment/offer adapters read existing rows; writes remain unavailable.
4. Reminders: server generation/synchronization, real delivery provider, audited
   bulk operations, printed-list generation, and a live staff-notification feed.
   Prototype SMS/printed-list actions are blocked in live mode; actual contact
   outcomes/assignment currently use the existing database adapter.
5. Inventory: transactional safety reviews, stronger mutation contracts and
   clinical integration. The live overview counts only non-expired, verified
   usable batches. The separate `consumeDoses` path is blocked: vaccination and
   stock must commit together, not in separate client requests.
6. Hosted end-to-end tests, recovery/backup checks, secret rotation, observability,
   and a final UI audit before enabling public production use.
7. Staff invitation activation: deploy a guarded server endpoint and activation
   screen that creates the Auth identity, then calls the service-only activation
   transaction. The current administrator workflow creates the staff record and
   audited pending invitation but does not claim the invitation has been activated.

Do not use this development live mode for real clinical decisions or vaccination
recording yet. Preserve the demo launch while these remaining workflows are
completed and accepted.
