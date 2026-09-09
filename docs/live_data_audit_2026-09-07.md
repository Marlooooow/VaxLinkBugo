# Live data audit — 2026-09-07

The normal `live` launch uses Supabase repositories. Mock repositories and
fixtures remain in the source tree and are selected only by an explicit mock
or demo launch.

## Connected workflows

| Area | Live source / write path |
| --- | --- |
| Authentication | Supabase Auth plus `profiles`, guardian activation, password change/reset |
| Guardians and children | Facility-scoped tables and audited registration/correction/link RPCs |
| Vaccination history | `vaccination_records` |
| PNIP schedule and assessment | Active, effective `pnip_schedule_rules` plus saved vaccination history |
| First-visit review | Idempotent database RPC/upsert |
| Vaccination administration | Atomic screening, vaccination, and inventory transaction RPC |
| Inventory | Supabase inventory, batch, transaction, safety, receipt, adjustment, and wastage workflows |
| Appointments | Facility/guardian reads and database RPCs for schedule, waitlist, reschedule, status, and offer response |
| Reminders | Database synchronization, summaries, paging, preferences, follow-up history, SMS delivery, and PDF/CSV follow-up export |
| Referrals | Database-issued QR token, verification, external vaccination, completion, and corrections |
| Advisory insights | Database reads/status changes and facility-scoped generation function |
| Staff accounts | Administrator registration plus one-time activation function |
| Staff notifications | Live facility sources with database-persisted read receipts and password-reset requests |
| Guardian invitation delivery | Database-issued one-time codes with printed fallback and live SMS delivery |

## Files that must be applied or deployed

The application does not push these automatically:

1. Apply `supabase/migrations/202609040001_seed_pnip_schedule_rules.sql`.
2. Apply `supabase/migrations/202609070001_staff_activation_password_policy.sql`.
3. Deploy `activate-staff-access` after setting the standard Supabase function secrets.
4. Redeploy `generate-advisory-insights` to use the corrected facility and usable-stock filters.
5. Apply `supabase/migrations/202609090005_guardian_invitation_sms_delivery.sql`.
6. Apply `supabase/migrations/202609090006_follow_up_export_contact_fields.sql`.
7. Deploy `send-guardian-activation-sms` with the existing SMS provider secrets.

## Deliberately unresolved product-policy items

- Automatic earlier-appointment offer creation needs the health center's
  approved clinic days, opening hours, slot duration, per-slot capacity,
  prioritization rules, and offer expiry. Existing reads and responses are
  live; the app must not invent real appointment capacity.
- System push notifications require a selected push provider and device-token
  policy. The current notification inbox and read state are database-backed,
  but it does not claim operating-system push delivery.

## Validation completed

- Dart static analysis: no compile errors; remaining findings are pre-existing
  warnings/style notices.
- Database regression suite: 26 of 26 tests passed.
- Edge-function TypeScript syntax checks passed.
- The local Flutter test runner did not emit output and was stopped after a
  bounded wait; this is recorded rather than reported as a passing run.
