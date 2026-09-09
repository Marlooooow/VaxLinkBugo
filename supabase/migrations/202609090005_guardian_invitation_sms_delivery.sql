begin;

alter table public.guardian_invitations
  add column if not exists delivery_channel text not null default 'printed_slip',
  add column if not exists delivery_status text not null default 'pending',
  add column if not exists destination_masked text,
  add column if not exists delivered_at timestamptz,
  add column if not exists provider_message_id text,
  add column if not exists provider_status text,
  add column if not exists delivery_failure_code text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'guardian_invitations_delivery_channel_check'
  ) then
    alter table public.guardian_invitations
      add constraint guardian_invitations_delivery_channel_check
      check (delivery_channel in ('printed_slip', 'sms', 'email'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'guardian_invitations_delivery_status_check'
  ) then
    alter table public.guardian_invitations
      add constraint guardian_invitations_delivery_status_check
      check (delivery_status in ('pending', 'accepted', 'failed', 'uncertain'));
  end if;
end $$;

grant select, update on public.guardian_invitations to service_role;

commit;
