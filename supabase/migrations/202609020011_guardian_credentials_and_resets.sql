begin;

alter table public.profiles
  add column if not exists must_change_password boolean not null default false;

create table if not exists public.guardian_password_reset_requests (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references public.guardians(id) on delete cascade,
  requested_username text not null,
  status text not null default 'pending' check (status in ('pending', 'completed', 'cancelled')),
  requested_at timestamptz not null default now(),
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz,
  unique (guardian_id, status)
);

alter table public.guardian_password_reset_requests enable row level security;

create or replace function public.request_guardian_password_reset(requested_username text)
returns void language plpgsql security definer set search_path = public as $$
declare target_guardian uuid;
begin
  select g.id into target_guardian
  from public.profiles p
  join public.guardians g on g.profile_id = p.id
  where lower(p.username) = lower(trim(requested_username))
    and p.role = 'guardian' and p.active = true;
  if target_guardian is not null then
    insert into public.guardian_password_reset_requests(guardian_id, requested_username)
    values (target_guardian, lower(trim(requested_username)))
    on conflict (guardian_id, status) do nothing;
  end if;
end $$;

create or replace function public.complete_password_change()
returns void language sql security definer set search_path = public as $$
  update public.profiles
  set must_change_password = false, updated_at = now()
  where id = auth.uid();
$$;

create or replace function public.activate_guardian_profile(
  invitation_id uuid, auth_user_id uuid, requested_username text
) returns void language plpgsql security definer set search_path = '' as $$
declare inv public.guardian_invitations; g public.guardians;
begin
  select * into inv from public.guardian_invitations where id = invitation_id;
  if not found then raise exception 'Invitation is no longer available.'; end if;
  select * into g from public.guardians where id = inv.guardian_id for update;
  select * into inv from public.guardian_invitations where id = invitation_id for update;
  if inv.status <> 'pending' or inv.expires_at <= now() or g.profile_id is not null
    or g.access_status <> 'invitation_pending'
    or not exists(select 1 from public.facilities where id = g.facility_id and active) then
    raise exception 'Invitation is no longer available.';
  end if;
  if lower(trim(requested_username)) <> lower(trim(g.guardian_code)) then
    raise exception 'Guardian ID username mismatch';
  end if;
  insert into public.profiles(
    id, facility_id, username, full_name, first_name, middle_name, last_name,
    suffix, role, active, must_change_password
  ) values (
    auth_user_id, g.facility_id, lower(trim(g.guardian_code)), g.full_name,
    g.first_name, g.middle_name, g.last_name, g.suffix, 'guardian', true, true
  );
  update public.guardians set profile_id = auth_user_id, access_status = 'active' where id = g.id;
  update public.guardian_invitations set status = 'used', used_at = now() where id = inv.id;
  insert into public.audit_logs(actor_id, facility_id, action, entity_type, entity_id, new_values)
  values (auth_user_id, g.facility_id, 'guardian_activated', 'guardians', g.id::text,
    jsonb_build_object('profile_id', auth_user_id, 'username', lower(g.guardian_code)));
end $$;

revoke all on function public.request_guardian_password_reset(text) from public;
grant execute on function public.request_guardian_password_reset(text) to anon, authenticated;
revoke all on function public.complete_password_change() from public;
grant execute on function public.complete_password_change() to authenticated;

create policy guardian_reset_requests_staff_select on public.guardian_password_reset_requests
  for select using (public.is_health_worker());
create policy guardian_reset_requests_staff_update on public.guardian_password_reset_requests
  for update using (public.is_health_worker()) with check (public.is_health_worker());

commit;
