-- Additive live-data boundary. No demo patients, accounts, or stock are seeded.
-- Apply to a development/staging project and run live_family_workflows.sql tests
-- before deploying. Existing migration history must not be rewritten.
begin;

create or replace function public.current_facility_id() returns uuid
language sql stable security definer set search_path = public
as $$ select facility_id from public.profiles where id = auth.uid() and active $$;

create or replace function public.is_active_profile() returns boolean
language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles where id = auth.uid() and active) $$;

create or replace function public.staff_at_facility(target_facility uuid) returns boolean
language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles p join public.facilities f on f.id = p.facility_id
  where p.id = auth.uid() and p.active and f.active
    and p.role in ('health_worker', 'administrator') and p.facility_id = target_facility) $$;

create or replace function public.guardian_can_access_child(target_child uuid) returns boolean
language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.guardian_child_links l
  join public.guardians g on g.id = l.guardian_id
  join public.profiles p on p.id = g.profile_id
  where l.child_id = target_child and l.status = 'approved' and p.id = auth.uid()
    and p.active and p.role = 'guardian' and g.access_status = 'active') $$;

create or replace function public.owns_guardian(target_guardian uuid) returns boolean
language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.guardians g join public.profiles p on p.id = g.profile_id
  where g.id = target_guardian and p.id = auth.uid() and p.active
    and p.role = 'guardian' and g.access_status = 'active') $$;

create or replace function public.can_access_live_child(target_child uuid) returns boolean
language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.children c where c.id = target_child
  and (public.staff_at_facility(c.facility_id) or public.guardian_can_access_child(c.id))) $$;

revoke all on function public.current_facility_id(), public.is_active_profile(),
  public.staff_at_facility(uuid), public.owns_guardian(uuid),
  public.can_access_live_child(uuid), public.guardian_can_access_child(uuid) from public;
grant execute on function public.current_facility_id(), public.is_active_profile(),
  public.staff_at_facility(uuid), public.owns_guardian(uuid),
  public.can_access_live_child(uuid), public.guardian_can_access_child(uuid) to authenticated;

-- Staff must not edit their own role/active/facility permissions using the app.
drop policy profiles_staff_manage on public.profiles;
create policy profiles_live_scope on public.profiles as restrictive for select to authenticated
using (public.is_active_profile() and (id = auth.uid() or public.staff_at_facility(facility_id)));

create policy guardians_live_scope on public.guardians as restrictive for all to authenticated
using (public.staff_at_facility(facility_id) or public.owns_guardian(id))
with check (public.staff_at_facility(facility_id));
create policy children_live_scope on public.children as restrictive for all to authenticated
using (public.staff_at_facility(facility_id) or public.guardian_can_access_child(id))
with check (public.staff_at_facility(facility_id));
create policy links_live_scope on public.guardian_child_links as restrictive for all to authenticated
using (public.owns_guardian(guardian_id) or exists(select 1 from public.guardians g
  where g.id = guardian_id and public.staff_at_facility(g.facility_id)))
with check (exists(select 1 from public.guardians g join public.children c on c.id = child_id
  where g.id = guardian_id and g.facility_id = c.facility_id and public.staff_at_facility(g.facility_id)));
create policy requests_live_scope on public.child_link_requests as restrictive for all to authenticated
using (public.owns_guardian(guardian_id) or exists(select 1 from public.guardians g
  where g.id = guardian_id and public.staff_at_facility(g.facility_id)))
with check (public.owns_guardian(guardian_id) or exists(select 1 from public.guardians g
  where g.id = guardian_id and public.staff_at_facility(g.facility_id)));

create policy vaccination_live_scope on public.vaccination_records as restrictive for all to authenticated
using (public.can_access_live_child(child_id)) with check (exists(select 1 from public.children c
  where c.id = child_id and public.staff_at_facility(c.facility_id)));
create policy screening_live_scope on public.vaccination_screenings as restrictive for all to authenticated
using (public.can_access_live_child(child_id)) with check (exists(select 1 from public.children c
  where c.id = child_id and public.staff_at_facility(c.facility_id)));
create policy first_visit_live_scope on public.first_visit_reviews as restrictive for all to authenticated
using (public.can_access_live_child(child_id)) with check (exists(select 1 from public.children c
  where c.id = child_id and public.staff_at_facility(c.facility_id)));
create policy appointments_live_scope on public.appointments as restrictive for all to authenticated
using (public.staff_at_facility(facility_id) or public.owns_guardian(guardian_id))
with check (public.staff_at_facility(facility_id));
create policy offers_live_scope on public.appointment_offers as restrictive for select to authenticated
using (exists(select 1 from public.appointments a where a.id = appointment_id));
create policy reminders_live_scope on public.reminders as restrictive for all to authenticated
using (public.owns_guardian(guardian_id) or exists(select 1 from public.children c
  where c.id = child_id and public.staff_at_facility(c.facility_id)))
with check (public.owns_guardian(guardian_id) or exists(select 1 from public.children c
  where c.id = child_id and public.staff_at_facility(c.facility_id)));
create policy follow_ups_live_scope on public.reminder_follow_ups as restrictive for all to authenticated
using (exists(select 1 from public.children c where c.id = child_id and public.staff_at_facility(c.facility_id)))
with check (performed_by = auth.uid() and exists(select 1 from public.children c
  where c.id = child_id and public.staff_at_facility(c.facility_id)));
create policy preferences_live_scope on public.reminder_preferences as restrictive for all to authenticated
using (public.owns_guardian(guardian_id) or exists(select 1 from public.guardians g
  where g.id = guardian_id and public.staff_at_facility(g.facility_id)))
with check (public.owns_guardian(guardian_id) or exists(select 1 from public.guardians g
  where g.id = guardian_id and public.staff_at_facility(g.facility_id)));
create policy inventory_live_scope on public.vaccine_inventory as restrictive for all to authenticated
using (public.staff_at_facility(facility_id)) with check (public.staff_at_facility(facility_id));
create policy batches_live_scope on public.vaccine_batches as restrictive for all to authenticated
using (exists(select 1 from public.vaccine_inventory i where i.id = inventory_id))
with check (exists(select 1 from public.vaccine_inventory i where i.id = inventory_id));
create policy transactions_live_scope on public.inventory_transactions as restrictive for all to authenticated
using (exists(select 1 from public.vaccine_inventory i where i.id = inventory_id))
with check (performed_by = auth.uid() and exists(select 1 from public.vaccine_inventory i where i.id = inventory_id));
create policy advisory_live_scope on public.advisory_insights as restrictive for all to authenticated
using (public.staff_at_facility(facility_id)) with check (public.staff_at_facility(facility_id));
create policy cold_chain_live_scope on public.cold_chain_checks as restrictive for all to authenticated
using (public.staff_at_facility(facility_id)) with check (public.staff_at_facility(facility_id));
create policy invitations_live_scope on public.guardian_invitations as restrictive for all to authenticated
using (exists(select 1 from public.guardians g where g.id = guardian_id and public.staff_at_facility(g.facility_id)))
with check (exists(select 1 from public.guardians g where g.id = guardian_id and public.staff_at_facility(g.facility_id)));
create policy guardian_corrections_live_scope on public.guardian_corrections as restrictive for all to authenticated
using (exists(select 1 from public.guardians g where g.id = guardian_id and public.staff_at_facility(g.facility_id)))
with check (corrected_by = auth.uid() and exists(select 1 from public.guardians g where g.id = guardian_id and public.staff_at_facility(g.facility_id)));
create policy child_corrections_live_scope on public.child_corrections as restrictive for all to authenticated
using (exists(select 1 from public.children c where c.id = child_id and public.staff_at_facility(c.facility_id)))
with check (corrected_by = auth.uid() and exists(select 1 from public.children c where c.id = child_id and public.staff_at_facility(c.facility_id)));
create policy referral_live_scope on public.referral_groups as restrictive for all to authenticated
using (public.staff_at_facility(originating_facility_id) or public.guardian_can_access_child(child_id))
with check (public.staff_at_facility(originating_facility_id));
create policy referral_items_live_scope on public.referral_items as restrictive for all to authenticated
using (exists(select 1 from public.referral_groups g where g.id = referral_group_id))
with check (exists(select 1 from public.referral_groups g where g.id = referral_group_id
  and public.staff_at_facility(g.originating_facility_id)));
create policy visits_live_scope on public.external_vaccination_visits as restrictive for all to authenticated
using (exists(select 1 from public.referral_groups g where g.id = referral_group_id and public.staff_at_facility(g.originating_facility_id)))
with check (exists(select 1 from public.referral_groups g where g.id = referral_group_id and public.staff_at_facility(g.originating_facility_id)));
create policy visit_items_live_scope on public.external_visit_items as restrictive for all to authenticated
using (exists(select 1 from public.external_vaccination_visits v where v.id = visit_id))
with check (exists(select 1 from public.external_vaccination_visits v where v.id = visit_id));

-- A guardian may acknowledge/dismiss their own reminder, never change its
-- patient, recipient, vaccine, appointment, due date, or completion status.
create function public.protect_guardian_reminder_update() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_health_worker() then
    if not public.owns_guardian(old.guardian_id)
      or (to_jsonb(new) - array['is_read', 'status', 'updated_at']) <>
         (to_jsonb(old) - array['is_read', 'status', 'updated_at'])
      or (new.status <> old.status and new.status <> 'dismissed') then
      raise exception 'Not authorized to change this reminder';
    end if;
  end if;
  return new;
end $$;
create trigger protect_guardian_reminder_update before update on public.reminders
for each row execute function public.protect_guardian_reminder_update();

-- Server-owned display codes; UUID primary keys keep foreign keys stable.
create function public.live_entity_code(prefix text) returns text
language sql volatile security invoker set search_path = public as $$
  select prefix || '-' || to_char(current_date, 'YYYY') || '-' ||
    lpad(nextval('public.entity_code_seq')::text, 6, '0')
$$;
revoke all on function public.live_entity_code(text) from public;
grant execute on function public.live_entity_code(text) to authenticated;

create function public.validate_live_child(details jsonb) returns void
language plpgsql security invoker set search_path = public as $$
begin
  if nullif(trim(details->>'full_name'), '') is null
    or coalesce(details->>'sex', '') not in ('male', 'female')
    or coalesce(details->>'relationship', '') not in
      ('mother','father','grandmother','grandfather','aunt','uncle','sibling','foster_guardian','legal_guardian','other')
    or nullif(details->>'birth_date', '') is null
    or (details->>'birth_date')::date > current_date then
    raise exception 'Enter a valid child name, sex, birth date, and relationship';
  end if;
end $$;
revoke all on function public.validate_live_child(jsonb) from public;
grant execute on function public.validate_live_child(jsonb) to authenticated;

create function public.add_family_child(target_guardian_id uuid, child_details jsonb, authorization_confirmed boolean)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare g public.guardians; c public.children; l public.guardian_child_links;
begin
  select * into g from public.guardians where id = target_guardian_id for update;
  if not found or not public.staff_at_facility(g.facility_id) then raise exception 'Not authorized'; end if;
  if authorization_confirmed is distinct from true then raise exception 'Guardian authorization is required'; end if;
  perform public.validate_live_child(child_details);
  -- A matching record needs explicit identity review, not automatic duplication/linking.
  if exists(select 1 from public.children where facility_id = g.facility_id
      and lower(trim(full_name)) = lower(trim(child_details->>'full_name'))
      and birth_date = (child_details->>'birth_date')::date and sex = child_details->>'sex') then
    raise exception 'A matching child record already exists. Review the existing record before linking.';
  end if;
  insert into public.children(child_code, facility_id, registered_by, full_name, sex, birth_date, address)
  values(public.live_entity_code('CH'), g.facility_id, auth.uid(), trim(child_details->>'full_name'),
    child_details->>'sex', (child_details->>'birth_date')::date, g.address) returning * into c;
  insert into public.guardian_child_links(guardian_id, child_id, relationship, is_primary, status, requested_by, reviewed_by, reviewed_at)
  values(g.id, c.id, child_details->>'relationship', true, 'approved', auth.uid(), auth.uid(), now()) returning * into l;
  return jsonb_build_object('guardian', to_jsonb(g), 'child', to_jsonb(c), 'link', to_jsonb(l));
end $$;

create function public.register_family(guardian_details jsonb, child_details jsonb, authorization_confirmed boolean)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare g public.guardians; item jsonb; added jsonb; links jsonb := '[]'::jsonb; facility uuid;
begin
  facility := public.current_facility_id();
  if not public.staff_at_facility(facility) then raise exception 'Not authorized'; end if;
  if authorization_confirmed is distinct from true then raise exception 'Guardian authorization is required'; end if;
  if nullif(trim(guardian_details->>'full_name'), '') is null
    or coalesce(guardian_details->>'sex', '') not in ('male','female') then
    raise exception 'Guardian name and sex are required'; end if;
  if jsonb_typeof(child_details) is distinct from 'array'
    or jsonb_array_length(child_details) not between 1 and 20 then
    raise exception 'Register between one and twenty children per request'; end if;
  -- Guard per-facility matching checks against simultaneous registration requests.
  perform pg_advisory_xact_lock(hashtextextended(facility::text, 0));
  insert into public.guardians(guardian_code, facility_id, registered_by, full_name, sex, phone, email, address, access_status)
  values(public.live_entity_code('GRD'), facility, auth.uid(), trim(guardian_details->>'full_name'),
    guardian_details->>'sex', nullif(trim(guardian_details->>'phone'), ''),
    nullif(trim(guardian_details->>'email'), ''), trim(guardian_details->>'address'), 'offline') returning * into g;
  for item in select value from jsonb_array_elements(child_details) loop
    added := public.add_family_child(g.id, item, authorization_confirmed);
    links := links || jsonb_build_array((added->'link') || jsonb_build_object('children', added->'child'));
  end loop;
  return to_jsonb(g) || jsonb_build_object('guardian_child_links', links);
end $$;

-- Requests are created/reviewed only through these transactions, not by trusting
-- a client-supplied status, guardian ID, reviewer ID, or linked-child ID.
revoke insert, update, delete on public.child_link_requests from authenticated;
create function public.submit_family_child_request(child_details jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare g public.guardians; request_id uuid;
begin
  select * into g from public.guardians where profile_id = auth.uid();
  if not found or not public.owns_guardian(g.id) then raise exception 'Not authorized'; end if;
  perform public.validate_live_child(child_details);
  perform pg_advisory_xact_lock(hashtextextended(g.id::text, 0));
  if exists(select 1 from public.child_link_requests where guardian_id = g.id and status = 'pending'
      and lower(trim(child_name)) = lower(trim(child_details->>'full_name'))
      and birth_date = (child_details->>'birth_date')::date) then
    raise exception 'A pending request already exists for this child'; end if;
  insert into public.child_link_requests(request_code, guardian_id, child_name, birth_date, sex, relationship)
  values(public.live_entity_code('CLR'), g.id, trim(child_details->>'full_name'),
    (child_details->>'birth_date')::date, child_details->>'sex', child_details->>'relationship') returning id into request_id;
  return request_id;
end $$;

create function public.review_family_child_request(target_request_id uuid, approve_request boolean, notes text)
returns uuid language plpgsql security definer set search_path = public as $$
declare r public.child_link_requests; g public.guardians; added jsonb;
begin
  select * into r from public.child_link_requests where id = target_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  select * into g from public.guardians where id = r.guardian_id;
  if not public.staff_at_facility(g.facility_id) then raise exception 'Not authorized'; end if;
  if r.status <> 'pending' then raise exception 'This request has already been reviewed'; end if;
  if approve_request is null or (not approve_request and nullif(trim(notes), '') is null) then
    raise exception 'A review decision and rejection reason are required'; end if;
  if approve_request then
    perform pg_advisory_xact_lock(hashtextextended(g.facility_id::text, 0));
    added := public.add_family_child(g.id, jsonb_build_object('full_name', r.child_name, 'sex', r.sex,
      'birth_date', r.birth_date, 'relationship', r.relationship), true);
  end if;
  update public.child_link_requests set status = case when approve_request then 'approved' else 'rejected' end,
    linked_child_id = (added->'child'->>'id')::uuid, reviewed_by = auth.uid(), reviewed_at = now(), review_notes = trim(notes)
    where id = r.id;
  return r.id;
end $$;

revoke all on function public.register_family(jsonb,jsonb,boolean), public.add_family_child(uuid,jsonb,boolean),
  public.submit_family_child_request(jsonb), public.review_family_child_request(uuid,boolean,text) from public;
grant execute on function public.register_family(jsonb,jsonb,boolean), public.add_family_child(uuid,jsonb,boolean),
  public.submit_family_child_request(jsonb), public.review_family_child_request(uuid,boolean,text) to authenticated;

create table public.staff_notification_receipts (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  notification_id text not null,
  read_at timestamptz not null default now(),
  primary key(profile_id, notification_id)
);
alter table public.staff_notification_receipts enable row level security;
create policy own_staff_notification_receipts on public.staff_notification_receipts for all to authenticated
using (profile_id = auth.uid() and public.is_health_worker())
with check (profile_id = auth.uid() and public.is_health_worker());
grant select, insert, update on public.staff_notification_receipts to authenticated;

commit;
