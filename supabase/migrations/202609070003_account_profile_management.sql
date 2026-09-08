-- Audited self-service contact updates and administrator-managed staff status.
begin;

create or replace function public.update_my_profile_contact(contact jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor public.profiles;
  guardian public.guardians;
  staff public.staff_members;
  before_values jsonb;
  after_values jsonb;
  phone_value text := nullif(trim(contact->>'phone'), '');
  email_value text := lower(nullif(trim(contact->>'email'), ''));
  address_value text := nullif(trim(contact->>'address'), '');
begin
  select * into actor from public.profiles
  where id = auth.uid() and active = true
  for update;
  if not found then raise exception 'An active account is required'; end if;
  if contact - array['phone', 'email', 'address'] <> '{}'::jsonb then
    raise exception 'Unsupported profile fields';
  end if;
  if phone_value is not null
    and regexp_replace(phone_value, '[^0-9]', '', 'g') !~ '^(09[0-9]{9}|9[0-9]{9}|639[0-9]{9})$' then
    raise exception 'Enter a valid Philippine mobile number';
  end if;
  if email_value is not null and email_value !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Enter a valid email address';
  end if;

  if actor.role = 'guardian' then
    select * into guardian from public.guardians
    where profile_id = actor.id for update;
    if not found or guardian.access_status <> 'active' then
      raise exception 'The guardian account is not linked to an active record';
    end if;
    if address_value is null then raise exception 'Home address is required'; end if;
    before_values := jsonb_build_object(
      'phone', guardian.phone, 'email', guardian.email, 'address', guardian.address);
    update public.guardians set
      phone = phone_value,
      email = email_value,
      address = address_value,
      updated_at = now()
    where id = guardian.id returning * into guardian;
    after_values := jsonb_build_object(
      'phone', guardian.phone, 'email', guardian.email, 'address', guardian.address);
    insert into public.audit_logs(
      actor_id, facility_id, action, entity_type, entity_id, old_values, new_values)
    values (
      actor.id, guardian.facility_id, 'guardian_contact_updated', 'guardians',
      guardian.id::text, before_values, after_values);
    return to_jsonb(guardian);
  end if;

  select * into staff from public.staff_members
  where profile_id = actor.id for update;
  if not found or staff.status <> 'active' then
    raise exception 'The staff account is not linked to an active staff record';
  end if;
  before_values := jsonb_build_object('phone', staff.phone, 'email', staff.email);
  update public.staff_members set
    phone = phone_value,
    email = email_value,
    updated_at = now()
  where id = staff.id returning * into staff;
  after_values := jsonb_build_object('phone', staff.phone, 'email', staff.email);
  insert into public.audit_logs(
    actor_id, facility_id, action, entity_type, entity_id, old_values, new_values)
  values (
    actor.id, staff.facility_id, 'staff_contact_updated', 'staff_members',
    staff.id::text, before_values, after_values);
  return to_jsonb(staff);
end;
$$;

-- Keep the health-worker correction form aligned with registration, including
-- the guardian email address, while retaining one atomic correction audit.
create or replace function public.correct_guardian_details(
  target_guardian_id uuid,
  changes jsonb,
  correction_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  guardian public.guardians;
  before_guardian jsonb;
  correction public.guardian_corrections;
  before_links jsonb;
  after_links jsonb;
  before_requests jsonb;
  after_requests jsonb;
  display_name text;
  email_value text := lower(nullif(trim(changes->>'email'), ''));
begin
  select * into guardian from public.guardians where id = target_guardian_id;
  if not found or not public.staff_at_facility(guardian.facility_id) then
    raise exception 'Not authorized';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(guardian.facility_id::text, 0));
  select * into guardian from public.guardians
  where id = target_guardian_id for update;
  if nullif(trim(correction_reason), '') is null then
    raise exception 'A correction reason is required';
  end if;
  display_name := public.request_person_name(changes);
  if coalesce(changes->>'sex', '') not in ('male', 'female') then
    raise exception 'Guardian name and sex are required';
  end if;
  if nullif(trim(changes->>'birth_date'), '') is not null
    and (changes->>'birth_date')::date > current_date then
    raise exception 'Guardian birth date cannot be in the future';
  end if;
  if email_value is not null and email_value !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Enter a valid email address';
  end if;
  if changes - array[
    'full_name', 'first_name', 'middle_name', 'last_name', 'suffix',
    'birth_date', 'sex', 'phone', 'email', 'address'
  ] <> '{}'::jsonb then
    raise exception 'Unsupported correction fields';
  end if;
  before_guardian := to_jsonb(guardian);
  select coalesce(jsonb_agg(to_jsonb(link) order by link.id), '[]')
  into before_links from public.guardian_child_links link
  where link.guardian_id = guardian.id;
  select coalesce(jsonb_agg(to_jsonb(request) order by request.id), '[]')
  into before_requests from public.child_link_requests request
  where request.guardian_id = guardian.id and request.status = 'pending';
  update public.guardians set
    full_name = display_name,
    first_name = nullif(trim(changes->>'first_name'), ''),
    middle_name = nullif(trim(changes->>'middle_name'), ''),
    last_name = nullif(trim(changes->>'last_name'), ''),
    suffix = nullif(trim(changes->>'suffix'), ''),
    birth_date = nullif(trim(changes->>'birth_date'), '')::date,
    sex = changes->>'sex',
    phone = nullif(trim(changes->>'phone'), ''),
    email = email_value,
    address = trim(changes->>'address')
  where id = guardian.id returning * into guardian;
  update public.guardian_child_links
  set relationship = public.relationship_for_guardian_sex(
    guardian.sex, relationship)
  where guardian_id = guardian.id;
  update public.child_link_requests
  set relationship = public.relationship_for_guardian_sex(
    guardian.sex, relationship)
  where guardian_id = guardian.id and status = 'pending';
  if guardian.profile_id is not null then
    update public.profiles set
      full_name = guardian.full_name,
      first_name = guardian.first_name,
      middle_name = guardian.middle_name,
      last_name = guardian.last_name,
      suffix = guardian.suffix
    where id = guardian.profile_id;
  end if;
  select coalesce(jsonb_agg(to_jsonb(link) order by link.id), '[]')
  into after_links from public.guardian_child_links link
  where link.guardian_id = guardian.id;
  select coalesce(jsonb_agg(to_jsonb(request) order by request.id), '[]')
  into after_requests from public.child_link_requests request
  where request.guardian_id = guardian.id and request.status = 'pending';
  insert into public.guardian_corrections(
    correction_code, guardian_id, previous_values, updated_values, reason,
    corrected_by)
  values (
    public.live_entity_code('GCOR'), guardian.id,
    before_guardian || jsonb_build_object(
      'links', before_links, 'pending_requests', before_requests),
    to_jsonb(guardian) || jsonb_build_object(
      'links', after_links, 'pending_requests', after_requests),
    trim(correction_reason), auth.uid())
  returning * into correction;
  return jsonb_build_object(
    'guardian', to_jsonb(guardian), 'correction', to_jsonb(correction));
end;
$$;

create or replace function public.set_staff_member_status(
  target_staff_id uuid,
  requested_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  staff public.staff_members;
  before_values jsonb;
begin
  select * into staff from public.staff_members
  where id = target_staff_id for update;
  if not found or not public.is_facility_admin(staff.facility_id) then
    raise exception 'Administrator access is required';
  end if;
  if requested_status not in ('active', 'disabled') then
    raise exception 'Choose Active or Disabled';
  end if;
  if staff.profile_id = auth.uid() and requested_status = 'disabled' then
    raise exception 'You cannot disable your own account';
  end if;
  if requested_status = 'active' and staff.profile_id is null then
    raise exception 'This staff invitation must be activated first';
  end if;
  before_values := to_jsonb(staff);
  update public.staff_members
  set status = requested_status, updated_at = now()
  where id = staff.id returning * into staff;
  if staff.profile_id is not null then
    update public.profiles
    set active = requested_status = 'active', updated_at = now()
    where id = staff.profile_id;
  end if;
  insert into public.audit_logs(
    actor_id, facility_id, action, entity_type, entity_id, old_values, new_values)
  values (
    auth.uid(), staff.facility_id, 'staff_status_updated', 'staff_members',
    staff.id::text, before_values, to_jsonb(staff));
  return to_jsonb(staff);
end;
$$;

revoke all on function public.update_my_profile_contact(jsonb) from public;
grant execute on function public.update_my_profile_contact(jsonb) to authenticated;
revoke all on function public.set_staff_member_status(uuid, text) from public;
grant execute on function public.set_staff_member_status(uuid, text) to authenticated;
revoke all on function public.correct_guardian_details(uuid, jsonb, text) from public;
grant execute on function public.correct_guardian_details(uuid, jsonb, text) to authenticated;

commit;
