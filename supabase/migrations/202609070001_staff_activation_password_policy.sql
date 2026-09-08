begin;

create or replace function public.activate_staff_profile(
  invitation_id uuid,
  auth_user_id uuid,
  requested_username text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation public.staff_invitations;
  staff public.staff_members;
begin
  select si.* into invitation
  from public.staff_invitations si
  where si.id = activate_staff_profile.invitation_id
  for update;

  if not found
     or invitation.status <> 'pending'
     or invitation.expires_at <= now() then
    raise exception 'Invitation is no longer available.';
  end if;

  select sm.* into staff
  from public.staff_members sm
  where sm.id = invitation.staff_member_id
  for update;

  if not found
     or staff.profile_id is not null
     or staff.status <> 'invitation_pending'
     or lower(trim(requested_username)) <> lower(trim(staff.staff_code)) then
    raise exception 'Invitation is no longer available.';
  end if;

  if not exists (
    select 1
    from public.facilities f
    where f.id = staff.facility_id and f.active
  ) then
    raise exception 'Invitation is no longer available.';
  end if;

  insert into public.profiles(
    id,
    facility_id,
    username,
    full_name,
    first_name,
    middle_name,
    last_name,
    suffix,
    role,
    active,
    must_change_password
  ) values (
    auth_user_id,
    staff.facility_id,
    lower(trim(staff.staff_code)),
    staff.full_name,
    staff.first_name,
    staff.middle_name,
    staff.last_name,
    staff.suffix,
    'health_worker',
    true,
    true
  );

  update public.staff_members
  set profile_id = auth_user_id,
      status = 'active',
      updated_at = now()
  where id = staff.id;

  update public.staff_invitations
  set status = 'used', used_at = now()
  where id = invitation.id;

  insert into public.audit_logs(
    actor_id,
    facility_id,
    action,
    entity_type,
    entity_id,
    new_values
  ) values (
    auth_user_id,
    staff.facility_id,
    'staff_activated',
    'staff_members',
    staff.id::text,
    jsonb_build_object(
      'profile_id', auth_user_id,
      'staff_code', staff.staff_code,
      'must_change_password', true
    )
  );
end;
$$;

revoke all on function public.activate_staff_profile(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.activate_staff_profile(uuid, uuid, text)
  to service_role;

commit;
