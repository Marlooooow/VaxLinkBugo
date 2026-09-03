-- Allow signed-in app users to reach the existing RLS policies.
-- Family, patient, vaccination, appointment, and stock movements continue to
-- use audited database functions; they intentionally receive no direct writes.
begin;

grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;

-- Direct writes currently used by the Flutter repositories. Row-level policies
-- and protective triggers still determine which rows and fields may change.
grant update on public.advisory_insights to authenticated;
grant update on public.vaccine_batches to authenticated;
grant update on public.reminders to authenticated;
grant insert, update on public.reminder_preferences to authenticated;
grant insert on public.reminder_follow_ups to authenticated;

commit;
