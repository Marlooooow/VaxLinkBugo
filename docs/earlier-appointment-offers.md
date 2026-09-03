# Earlier appointment offers: prototype contract

## Implemented

- Offer allocation reads the shared mock appointment and usable-batch data.
- Demo policy: weekdays 09:00–12:00, one facility slot every 15 minutes; response window up to 24 hours, ending at least one hour before the offered appointment.
- Policy fields live in `EarlierOfferPolicy`; these hours are demonstration settings, not confirmed Bugo clinic hours.
- Candidate order: explicit staff-supplied clinical priority, then appointment creation/queue entry time, then stable ID.
- Candidates must have an active appointment/waitlist record, an earlier available time, and meet stored PNIP and optional eligibility-not-before dates. This is not a clinical assessment.
- Pending offers occupy a unique time and one provisional dose in the offer allocator. Accepted offers continue occupying an allocation while their replacement appointment is active.
- Declining keeps the original appointment and attempts allocation to the next candidate. Expiry is processed on offer refresh. A declined/expired appointment is not repeatedly reoffered within this mock cycle.
- Acceptance checks active original, deadline, stored eligibility dates, usable stock versus offer allocations, and time collisions. It preserves the offered time, creates a linked replacement, and marks the original rescheduled. Duplicate responses are rejected.
- Offer responses carry actor ID and channel (`guardian_online` or `staff_recorded`). Staff confirms that the guardian actually responded before recording an offline response.
- Guardian reminders and appointment screens share timing/deadline presentation. Staff notification targets retain the related appointment ID.

## Not production guarantees

This is an in-memory prototype. Allocation runs on stock receipt and when offer screens/notifications refresh, not while the application is closed. Read/response state is not yet persisted to Supabase.

Provisional dose allocations prevent duplicate offers, but do **not** lock physical inventory against walk-in administration, wastage or stock adjustment. Acceptance therefore rechecks stock; staff must not interpret a mock hold as a guaranteed vaccine reservation. Appointments made outside this allocator are not yet fully capacity-controlled.

Live implementation requires approved session settings, authoritative eligibility dates from the scheduling rules and staff assessment, facility-scoped authorization, a server job for expiry/reallocation, and transactional slot/dose reservations shared with vaccination and inventory operations. Guard against cross-facility reads, conflicting responses, cancellation races and retries using database constraints and idempotency keys.

Use UTC for persisted timestamps and render in the facility time zone. Store one immutable queue-entry timestamp across rescheduling, explicit priority and its authorized issuer, slot/session IDs, reservation state, expiry, response actor/channel, and an audit trail. A response must never be trusted just because a client supplies a staff channel or guardian identifier.

Do not switch this feature to live mode until these rules and migrations are implemented and tested. No migration or deployment was performed for this prototype change.
