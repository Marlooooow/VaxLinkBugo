# Supabase-backed synthetic demo

The `vaxlink-demo-v1` dataset is explicitly loaded into VaxLinkBugo
(`oytdqiavxqowrzqpowvr`). It uses actual Supabase Auth, UUID foreign keys, row-level
security, and the app's live repositories. It is **not real patient data** and is
not a certification that every production workflow is complete.

## Accounts and records

| Username | Password | Account | Linked children |
| --- | --- | --- | --- |
| `demo.admin` | `admin123` | Bugo Demo Administrator, administrator | All children at the demo facility |
| `demo.healthworker` | `healthworkeradmin123` | Maria Reyes (Demo), health worker | All 8 at the demo facility |
| `demo.maria` | `maria123` | Maria Santos (Demo) | Sofia, Princess, Mateo, Miguel, Ana |
| `demo.paolo` | `paolo123` | Paolo Mendoza (Demo) | Lia |
| `demo.grace` | `grace123` | Grace Villanueva (Demo) | Noah |

Elena Dela Cruz (Demo) and Carlo form an offline family, visible to the worker
without requiring a guardian login. Maria is mother to three children and aunt
to two; these are separate guardian-child relationships, not separate accounts.

These intentionally simple credentials are for synthetic prototype data only.
Never reuse them for real staff, guardians, or patient records. The local ignored
file `.env.supabase-demo-accounts.json` also stores the Auth identity mapping;
do not commit or embed it in the app. Internal Auth email addresses are
identifiers only; no email or SMS is sent during seeding.

The initial dataset contains four family/staff profiles. A fifth, dedicated demo
administrator profile is provisioned separately and idempotently so an
administrator can test staff registration without promoting the nurse account.
The hosted facility may contain additional records deliberately created through
the app after the initial seed; those records are preserved.

The initial dataset contains:

- 1 dedicated demo facility, 4 profiles, 4 families and 8 children.
- 61 synthetic previous-facility vaccination records and 8 first-visit reviews.
- 88 reminders: completed, due today, overdue and upcoming, excluding doses whose
  preceding dose is missing. Completed items start read; other items start unread.
- 4 appointments, including a waitlist example, and 1 earlier-date offer.
- 7 vaccine catalog entries, 7 inventory/batch records and 7 matching receipts.
- 1 pending guardian child request and 1 clearly labeled synthetic advisory.

Scenario dates are anchored to **2026-09-01**, the first seed date. They do not
reset on app refresh or seed reruns. Due statuses are a seed-time snapshot;
server-side ongoing reminder synchronization remains pending. Earlier offers
expire normally. These dates are fixtures based on the app's existing schedule,
not clinical guidance or newly validated scheduling policy.

History is marked `previous_record`: it does not consume the new demo facility's
opening stock. Batch safety fields describe a synthetic assessment, not real
temperature measurements. The advisory is marked `synthetic_seed`, not attributed
to Gemini, Groq, or another model.

## Running the app

Select **VaxLink - Live (Supabase)** in VS Code and fully restart the app. It is
the first launch choice. A normal terminal run now uses the bundled public-only
connection settings:

```powershell
flutter run
```

Sign in using one of the usernames above and its private generated password.
The original offline mock data remains in source, available through the explicit
**VaxLink - Demo (preserved mock data)** launch. The existing prototype APK is not
modified by this seed and still runs its original offline demo.

## Repeatable, opt-in seed

Preview without any network access or writes:

```powershell
node tool/seed_supabase_demo.mjs
```

Apply only to the explicitly confirmed project using the existing CLI login:

```powershell
node tool/seed_supabase_demo.mjs --apply --project-ref oytdqiavxqowrzqpowvr
```

Verify existing test logins without reinserting business data:

```powershell
node tool/seed_supabase_demo.mjs --verify --project-ref oytdqiavxqowrzqpowvr
```

Provision or repair only the dedicated demo administrator, without reseeding
families or clinical records:

```powershell
node tool/seed_supabase_demo.mjs --ensure-admin --project-ref oytdqiavxqowrzqpowvr
```

Synchronize only the verified synthetic Auth passwords, then verify their
row-level access without changing application records:

```powershell
node tool/seed_supabase_demo.mjs --sync-passwords --project-ref oytdqiavxqowrzqpowvr
```

The tool checks project identity and required migrations. It creates Auth users
through the server-side Admin API, keeps the server key in process memory only,
and inserts business records in one database transaction. A transaction lock and
audit marker prevent repeated insertion. An existing matching marker means
**leave all records, passwords, dates, read states and stock edits alone**.
Conflicting non-demo accounts are never adopted or overwritten.

Keep the private account file when retrying an interrupted seed. Auth provisioning
and PostgreSQL insertion cannot share a transaction; if insertion fails, newly
created demo Auth users are retained for retry, never silently deleted. A missing
private file or changed saved identity stops the tool instead of resetting users.
This seed never runs automatically during migrations, app startup, or deployments.

## Validation

```powershell
npm run test:database
flutter test --no-pub test/supabase_demo_live_test.dart --dart-define-from-file=.dart_tool/vaxlink.public.json --dart-define=RUN_SUPABASE_DEMO_CHECKS=true
```

The database suite uses isolated PostgreSQL. The hosted Flutter smoke test is
explicit opt-in and exercises real app adapters and sign-ins, without changing
business records. Ordinary Flutter tests skip it and never open the private file.
It checks the initial demo scenario and may need revisiting after deliberate
changes such as deleting fixture children or approving its only pending request.

Verified on 2026-09-02: all 8 migrations match hosted history; 25 isolated database
tests passed, and all five hosted demo accounts passed sign-in and row-level
family isolation checks. A repeated hosted seed run skipped insertion and
preserved the application records.
The prototype APK SHA-256 remained
`E64AF896B1624F78892F9BD56449AC8F4F339B183D564A372D7A5F073990C1F1`.

The remaining clinical writes, referral workflows, appointment/offer mutations,
reminder automation, delivery integrations and live staff notification feed are
listed in `production_setup.md`. Loading test data does not implement these.
The activation Edge Function still needs its own deployment/acceptance checks;
the seeded active guardian logins do not depend on that endpoint.
