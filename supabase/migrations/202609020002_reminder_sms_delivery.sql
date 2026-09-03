begin;

alter table public.reminder_follow_ups
  drop constraint if exists reminder_follow_ups_action_check;
alter table public.reminder_follow_ups
  add constraint reminder_follow_ups_action_check
  check (action in ('mock_sms', 'sms', 'assign', 'phone_call', 'printed_list', 'home_visit'));

alter table public.reminder_follow_ups
  drop constraint if exists reminder_follow_ups_outcome_check;
alter table public.reminder_follow_ups
  add constraint reminder_follow_ups_outcome_check
  check (outcome in (
    'reminder_sent', 'provider_accepted', 'delivery_failed', 'assigned',
    'contacted', 'no_answer', 'invalid_contact', 'visit_scheduled',
    'declined', 'home_visit_required', 'printed'
  ));

create table public.reminder_sms_deliveries (
  id uuid primary key default gen_random_uuid(),
  delivery_code text not null unique,
  facility_id uuid not null references public.facilities(id),
  reminder_id uuid not null references public.reminders(id),
  guardian_id uuid not null references public.guardians(id),
  child_id uuid not null references public.children(id),
  requested_by uuid not null references public.profiles(id),
  provider text not null default 'semaphore' check (provider = 'semaphore'),
  provider_message_id text,
  recipient_masked text not null,
  status text not null check (status in ('sending', 'accepted', 'failed', 'uncertain')),
  provider_status text,
  failure_code text,
  request_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(request_id, reminder_id)
);

create index reminder_sms_deliveries_reminder_created_idx
  on public.reminder_sms_deliveries(reminder_id, created_at desc);

create trigger reminder_sms_deliveries_updated_at
before update on public.reminder_sms_deliveries
for each row execute function public.set_updated_at();

alter table public.reminder_sms_deliveries enable row level security;
create policy reminder_sms_deliveries_staff_read
on public.reminder_sms_deliveries for select to authenticated
using (public.staff_at_facility(facility_id));

grant select on public.reminder_sms_deliveries to authenticated;
revoke insert, update, delete on public.reminder_sms_deliveries from authenticated;

-- The server-side sender authenticates the requesting worker, reads only the
-- records needed to construct a reminder, and records provider acceptance or
-- failure. The API key and full message body never enter an app table.
grant select on public.profiles, public.facilities, public.reminders,
  public.reminder_preferences, public.guardians, public.children,
  public.vaccine_definitions, public.reminder_sms_deliveries to service_role;
grant insert, update on public.reminder_sms_deliveries to service_role;
grant select, insert on public.reminder_follow_ups to service_role;
grant update(last_contacted_at, delivery_channel, updated_at)
  on public.reminders to service_role;

commit;
