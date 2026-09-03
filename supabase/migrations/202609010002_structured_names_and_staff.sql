-- Structured person names plus an administrator-managed staff registry.
-- Existing full_name values remain valid and unchanged.
begin;

alter table public.profiles
  add column first_name text,
  add column middle_name text,
  add column last_name text,
  add column suffix text;
alter table public.guardians
  add column first_name text,
  add column middle_name text,
  add column last_name text,
  add column suffix text;
alter table public.children
  add column first_name text,
  add column middle_name text,
  add column last_name text,
  add column suffix text;
alter table public.child_link_requests
  add column first_name text,
  add column middle_name text,
  add column last_name text,
  add column suffix text;

create function public.person_full_name(
  first_name_value text,
  middle_name_value text,
  last_name_value text,
  suffix_value text
) returns text language sql immutable set search_path = '' as $$
  select concat_ws(' ', nullif(trim(first_name_value), ''),
    nullif(trim(middle_name_value), ''), nullif(trim(last_name_value), ''),
    nullif(trim(suffix_value), ''))
$$;

create function public.request_person_name(details jsonb) returns text
language plpgsql immutable set search_path = public as $$
declare structured boolean; result text;
begin
  structured := nullif(trim(details->>'first_name'), '') is not null
    or nullif(trim(details->>'last_name'), '') is not null;
  if structured then
    if nullif(trim(details->>'first_name'), '') is null
      or nullif(trim(details->>'last_name'), '') is null then
      raise exception 'First name and last name are required';
    end if;
    result := public.person_full_name(details->>'first_name', details->>'middle_name',
      details->>'last_name', details->>'suffix');
  else
    result := nullif(trim(details->>'full_name'), '');
  end if;
  if result is null then raise exception 'A valid name is required'; end if;
  return result;
end $$;

create or replace function public.validate_live_child(details jsonb) returns void
language plpgsql security invoker set search_path = public as $$
begin
  perform public.request_person_name(details);
  if coalesce(details->>'sex', '') not in ('male', 'female')
    or coalesce(details->>'relationship', '') not in
      ('mother','father','grandmother','grandfather','aunt','uncle','sibling','foster_guardian','legal_guardian','other')
    or nullif(details->>'birth_date', '') is null
    or (details->>'birth_date')::date > current_date then
    raise exception 'Enter a valid child name, sex, birth date, and relationship';
  end if;
end $$;

create or replace function public.add_family_child(target_guardian_id uuid, child_details jsonb, authorization_confirmed boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.guardians; c public.children; l public.guardian_child_links; display_name text;
begin
  select * into g from public.guardians where id = target_guardian_id;
  if not found or not public.staff_at_facility(g.facility_id) then raise exception 'Not authorized'; end if;
  perform pg_advisory_xact_lock(hashtextextended(g.facility_id::text, 0));
  select * into g from public.guardians where id = target_guardian_id for update;
  if authorization_confirmed is distinct from true then raise exception 'Guardian authorization is required'; end if;
  perform public.validate_live_child(child_details);
  perform public.validate_guardian_relationship(g.sex, child_details->>'relationship');
  display_name := public.request_person_name(child_details);
  if exists(select 1 from public.children where facility_id = g.facility_id
      and lower(trim(full_name)) = lower(display_name)
      and birth_date = (child_details->>'birth_date')::date and sex = child_details->>'sex') then
    raise exception 'A matching child record already exists. Review the existing record before linking.';
  end if;
  insert into public.children(child_code, facility_id, registered_by, full_name,
    first_name, middle_name, last_name, suffix, sex, birth_date, address)
  values(public.live_entity_code('CH'), g.facility_id, auth.uid(), display_name,
    nullif(trim(child_details->>'first_name'), ''), nullif(trim(child_details->>'middle_name'), ''),
    nullif(trim(child_details->>'last_name'), ''), nullif(trim(child_details->>'suffix'), ''),
    child_details->>'sex', (child_details->>'birth_date')::date, g.address) returning * into c;
  insert into public.guardian_child_links(guardian_id, child_id, relationship, is_primary, status, requested_by, reviewed_by, reviewed_at)
  values(g.id, c.id, child_details->>'relationship', true, 'approved', auth.uid(), auth.uid(), now()) returning * into l;
  insert into public.audit_logs(actor_id, facility_id, action, entity_type, entity_id, new_values)
  values(auth.uid(), g.facility_id, 'child_registered', 'children', c.id::text,
    jsonb_build_object('child', to_jsonb(c), 'guardian_child_link', to_jsonb(l)));
  return jsonb_build_object('guardian', to_jsonb(g), 'child', to_jsonb(c), 'link', to_jsonb(l));
end $$;

create or replace function public.register_family(guardian_details jsonb, child_details jsonb, authorization_confirmed boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.guardians; item jsonb; added jsonb; links jsonb := '[]'::jsonb;
  facility uuid; display_name text; guardian_birth_date date;
begin
  facility := public.current_facility_id();
  if not public.staff_at_facility(facility) then raise exception 'Not authorized'; end if;
  if authorization_confirmed is distinct from true then raise exception 'Guardian authorization is required'; end if;
  display_name := public.request_person_name(guardian_details);
  if coalesce(guardian_details->>'sex', '') not in ('male','female') then
    raise exception 'Guardian name and sex are required'; end if;
  if guardian_details ? 'first_name' then
    if nullif(guardian_details->>'birth_date', '') is null then
      raise exception 'Guardian birth date is required';
    end if;
    guardian_birth_date := (guardian_details->>'birth_date')::date;
    if guardian_birth_date > current_date then raise exception 'Guardian birth date cannot be in the future'; end if;
  else
    guardian_birth_date := nullif(guardian_details->>'birth_date', '')::date;
  end if;
  if jsonb_typeof(child_details) is distinct from 'array'
    or jsonb_array_length(child_details) not between 1 and 20 then
    raise exception 'Register between one and twenty children per request'; end if;
  perform pg_advisory_xact_lock(hashtextextended(facility::text, 0));
  insert into public.guardians(guardian_code, facility_id, registered_by, full_name,
    first_name, middle_name, last_name, suffix, sex, birth_date, phone, email, address, access_status)
  values(public.live_entity_code('GRD'), facility, auth.uid(), display_name,
    nullif(trim(guardian_details->>'first_name'), ''), nullif(trim(guardian_details->>'middle_name'), ''),
    nullif(trim(guardian_details->>'last_name'), ''), nullif(trim(guardian_details->>'suffix'), ''),
    guardian_details->>'sex', guardian_birth_date, nullif(trim(guardian_details->>'phone'), ''),
    nullif(trim(guardian_details->>'email'), ''), trim(guardian_details->>'address'), 'offline') returning * into g;
  for item in select value from jsonb_array_elements(child_details) loop
    added := public.add_family_child(g.id, item, authorization_confirmed);
    links := links || jsonb_build_array((added->'link') || jsonb_build_object('children', added->'child'));
  end loop;
  return to_jsonb(g) || jsonb_build_object('guardian_child_links', links);
end $$;

create or replace function public.submit_family_child_request(child_details jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare g public.guardians; request_id uuid; display_name text;
begin
  select * into g from public.guardians where profile_id=auth.uid();
  if not found or not public.owns_guardian(g.id) then raise exception 'Not authorized'; end if;
  perform pg_advisory_xact_lock(hashtextextended(g.facility_id::text,0));
  select * into g from public.guardians where profile_id=auth.uid() for update;
  if not public.owns_guardian(g.id) then raise exception 'Not authorized'; end if;
  perform public.validate_live_child(child_details);
  perform public.validate_guardian_relationship(g.sex,child_details->>'relationship');
  display_name := public.request_person_name(child_details);
  if exists(select 1 from public.child_link_requests where guardian_id=g.id and status='pending'
      and lower(trim(child_name))=lower(display_name) and birth_date=(child_details->>'birth_date')::date) then
    raise exception 'A pending request already exists for this child'; end if;
  insert into public.child_link_requests(request_code,guardian_id,child_name,first_name,middle_name,last_name,suffix,birth_date,sex,relationship)
  values(public.live_entity_code('CLR'),g.id,display_name,
    nullif(trim(child_details->>'first_name'), ''), nullif(trim(child_details->>'middle_name'), ''),
    nullif(trim(child_details->>'last_name'), ''), nullif(trim(child_details->>'suffix'), ''),
    (child_details->>'birth_date')::date, child_details->>'sex',child_details->>'relationship') returning id into request_id;
  insert into public.audit_logs(actor_id,facility_id,action,entity_type,entity_id,new_values)
  values(auth.uid(),g.facility_id,'child_request_submitted','child_link_requests',request_id::text,
    jsonb_build_object('guardian_id',g.id,'status','pending'));
  return request_id;
end $$;

create or replace function public.review_family_child_request(target_request_id uuid, approve_request boolean, notes text)
returns uuid language plpgsql security definer set search_path = public as $$
declare r public.child_link_requests; g public.guardians; added jsonb; before_r jsonb;
begin
  select * into r from public.child_link_requests where id=target_request_id;
  if not found then raise exception 'Request not found'; end if;
  select * into g from public.guardians where id=r.guardian_id;
  if not public.staff_at_facility(g.facility_id) then raise exception 'Not authorized'; end if;
  perform pg_advisory_xact_lock(hashtextextended(g.facility_id::text,0));
  select * into r from public.child_link_requests where id=target_request_id for update;
  if r.status <> 'pending' then raise exception 'This request has already been reviewed'; end if;
  if approve_request is null or (not approve_request and nullif(trim(notes),'') is null) then
    raise exception 'A review decision and rejection reason are required'; end if;
  before_r := to_jsonb(r);
  if approve_request then
    added := public.add_family_child(g.id,jsonb_build_object('full_name',r.child_name,
      'first_name',r.first_name,'middle_name',r.middle_name,'last_name',r.last_name,'suffix',r.suffix,
      'sex',r.sex,'birth_date',r.birth_date,'relationship',r.relationship),true);
  end if;
  update public.child_link_requests set status=case when approve_request then 'approved' else 'rejected' end,
    linked_child_id=(added->'child'->>'id')::uuid, reviewed_by=auth.uid(),reviewed_at=now(),review_notes=trim(notes)
    where id=r.id returning * into r;
  insert into public.audit_logs(actor_id,facility_id,action,entity_type,entity_id,old_values,new_values)
  values(auth.uid(),g.facility_id,'child_request_reviewed','child_link_requests',r.id::text,before_r,to_jsonb(r));
  return r.id;
end $$;

create or replace function public.activate_guardian_profile(invitation_id uuid, auth_user_id uuid, requested_username text)
returns void language plpgsql security definer set search_path = '' as $$
declare inv public.guardian_invitations; g public.guardians;
begin
  select * into inv from public.guardian_invitations where id = invitation_id;
  if not found then raise exception 'Invitation is no longer available.'; end if;
  select * into g from public.guardians where id = inv.guardian_id for update;
  select * into inv from public.guardian_invitations where id = invitation_id for update;
  if inv.status <> 'pending' or inv.expires_at <= now() or g.profile_id is not null
    or g.access_status <> 'invitation_pending' or not exists(select 1 from public.facilities where id=g.facility_id and active) then
    raise exception 'Invitation is no longer available.'; end if;
  if lower(trim(requested_username)) !~ '^[a-z0-9._-]{4,40}$' then raise exception 'Invalid username'; end if;
  insert into public.profiles(id,facility_id,username,full_name,first_name,middle_name,last_name,suffix,role,active)
  values(auth_user_id,g.facility_id,lower(trim(requested_username)),g.full_name,g.first_name,g.middle_name,g.last_name,g.suffix,'guardian',true);
  update public.guardians set profile_id=auth_user_id, access_status='active' where id=g.id;
  update public.guardian_invitations set status='used',used_at=now() where id=inv.id;
  insert into public.audit_logs(actor_id,facility_id,action,entity_type,entity_id,new_values)
  values(auth_user_id,g.facility_id,'guardian_activated','guardians',g.id::text,jsonb_build_object('profile_id',auth_user_id));
end $$;

create table public.staff_members (
  id uuid primary key default gen_random_uuid(),
  staff_code text not null unique,
  facility_id uuid not null references public.facilities(id),
  profile_id uuid unique references public.profiles(id),
  first_name text not null,
  middle_name text,
  last_name text not null,
  suffix text,
  full_name text not null,
  staff_type text not null check (staff_type in ('nurse','midwife','barangay_health_worker','physician')),
  license_number text,
  phone text,
  email text,
  status text not null default 'invitation_pending' check (status in ('invitation_pending','active','disabled')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.staff_invitations (
  id uuid primary key default gen_random_uuid(),
  staff_member_id uuid not null references public.staff_members(id) on delete cascade,
  activation_code_hash text not null unique,
  expires_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','used','expired','revoked')),
  issued_by uuid not null references public.profiles(id),
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create trigger staff_members_updated_at before update on public.staff_members
for each row execute function public.set_updated_at();

create function public.is_facility_admin(target_facility uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles p join public.facilities f on f.id=p.facility_id
    where p.id=auth.uid() and p.role='administrator' and p.active and f.active
      and p.facility_id=target_facility)
$$;

alter table public.staff_members enable row level security;
alter table public.staff_invitations enable row level security;
create policy staff_members_facility_read on public.staff_members for select to authenticated
using (public.staff_at_facility(facility_id));
create policy staff_invitations_admin_read on public.staff_invitations for select to authenticated
using (exists(select 1 from public.staff_members s where s.id=staff_member_id and public.is_facility_admin(s.facility_id)));

create function public.register_staff_member(staff_details jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare facility uuid; staff public.staff_members; invitation public.staff_invitations;
  display_name text; raw_code text;
begin
  facility := public.current_facility_id();
  if not public.is_facility_admin(facility) then raise exception 'Administrator access is required'; end if;
  display_name := public.request_person_name(staff_details);
  if coalesce(staff_details->>'staff_type','') not in ('nurse','midwife','barangay_health_worker','physician') then
    raise exception 'Choose a valid staff type'; end if;
  insert into public.staff_members(staff_code,facility_id,first_name,middle_name,last_name,suffix,full_name,
    staff_type,license_number,phone,email,created_by)
  values(public.live_entity_code('STF'),facility,trim(staff_details->>'first_name'),
    nullif(trim(staff_details->>'middle_name'),''),trim(staff_details->>'last_name'),
    nullif(trim(staff_details->>'suffix'),''),display_name,staff_details->>'staff_type',
    nullif(trim(staff_details->>'license_number'),''),nullif(trim(staff_details->>'phone'),''),
    nullif(trim(staff_details->>'email'),''),auth.uid()) returning * into staff;
  raw_code := 'STF-ACT-' || upper(encode(gen_random_bytes(16),'hex'));
  insert into public.staff_invitations(staff_member_id,activation_code_hash,expires_at,issued_by)
  values(staff.id,encode(digest(raw_code,'sha256'),'hex'),now()+interval '7 days',auth.uid()) returning * into invitation;
  insert into public.audit_logs(actor_id,facility_id,action,entity_type,entity_id,new_values)
  values(auth.uid(),facility,'staff_invited','staff_members',staff.id::text,
    jsonb_build_object('staff_code',staff.staff_code,'staff_type',staff.staff_type,'invitation_id',invitation.id));
  return jsonb_build_object('staff',to_jsonb(staff),'invitation',
    (to_jsonb(invitation)-'activation_code_hash')||jsonb_build_object('activation_code',raw_code));
end $$;

create function public.activate_staff_profile(invitation_id uuid, auth_user_id uuid, requested_username text)
returns void language plpgsql security definer set search_path = '' as $$
declare invitation public.staff_invitations; staff public.staff_members;
begin
  select * into invitation from public.staff_invitations where id=invitation_id for update;
  if not found or invitation.status<>'pending' or invitation.expires_at<=now() then
    raise exception 'Invitation is no longer available.'; end if;
  select * into staff from public.staff_members where id=invitation.staff_member_id for update;
  if staff.profile_id is not null or staff.status<>'invitation_pending'
    or lower(trim(requested_username)) !~ '^[a-z0-9._-]{4,40}$' then
    raise exception 'Invitation is no longer available.'; end if;
  insert into public.profiles(id,facility_id,username,full_name,first_name,middle_name,last_name,suffix,role,active)
  values(auth_user_id,staff.facility_id,lower(trim(requested_username)),staff.full_name,
    staff.first_name,staff.middle_name,staff.last_name,staff.suffix,'health_worker',true);
  update public.staff_members set profile_id=auth_user_id,status='active' where id=staff.id;
  update public.staff_invitations set status='used',used_at=now() where id=invitation.id;
  insert into public.audit_logs(actor_id,facility_id,action,entity_type,entity_id,new_values)
  values(auth_user_id,staff.facility_id,'staff_activated','staff_members',staff.id::text,
    jsonb_build_object('profile_id',auth_user_id));
end $$;

grant select on public.staff_members, public.staff_invitations to authenticated;
revoke insert,update,delete on public.staff_members,public.staff_invitations from authenticated;
revoke all on function public.person_full_name(text,text,text,text), public.request_person_name(jsonb),
  public.is_facility_admin(uuid), public.register_staff_member(jsonb),
  public.activate_staff_profile(uuid,uuid,text) from public;
grant execute on function public.person_full_name(text,text,text,text), public.request_person_name(jsonb) to authenticated;
grant execute on function public.is_facility_admin(uuid), public.register_staff_member(jsonb) to authenticated;
grant execute on function public.activate_staff_profile(uuid,uuid,text) to service_role;

commit;
