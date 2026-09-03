-- Live family workflow: audited corrections and one-time printed activation.
-- No real clinical records or prototype accounts are seeded by this migration.
begin;

alter table public.audit_logs add column facility_id uuid references public.facilities(id);
create policy audit_facility_scope on public.audit_logs as restrictive for select to authenticated
using (public.staff_at_facility(facility_id));

-- Prototype delivery/list generation must never be recorded as real work.
create policy follow_up_no_simulated_delivery on public.reminder_follow_ups as restrictive for insert to authenticated
with check (action not in ('mock_sms','printed_list'));

-- Codes must grow instead of truncating and colliding after six-digit sequences.
create or replace function public.live_entity_code(prefix text) returns text
language sql volatile security invoker set search_path = public as $$
  with value as (select nextval('public.entity_code_seq')::text as n)
  select prefix || '-' || to_char(current_date, 'YYYY') || '-' || lpad(n, greatest(6,length(n)), '0') from value
$$;

create function public.validate_guardian_relationship(guardian_sex text, relationship_value text) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  if (guardian_sex = 'male' and relationship_value in ('mother','grandmother','aunt'))
    or (guardian_sex = 'female' and relationship_value in ('father','grandfather','uncle')) then
    raise exception 'Choose a relationship consistent with the guardian sex';
  end if;
end $$;

create function public.relationship_for_guardian_sex(guardian_sex text, relationship_value text) returns text
language sql immutable set search_path = '' as $$
  select case
    when relationship_value in ('mother','father') then case when guardian_sex='male' then 'father' else 'mother' end
    when relationship_value in ('aunt','uncle') then case when guardian_sex='male' then 'uncle' else 'aunt' end
    when relationship_value in ('grandmother','grandfather') then case when guardian_sex='male' then 'grandfather' else 'grandmother' end
    else relationship_value end
$$;

-- All registrations and edits that check for duplicate children use the same
-- facility lock before locking the guardian/child row. No record is merged
-- automatically just because its name and date of birth match.
create or replace function public.add_family_child(target_guardian_id uuid, child_details jsonb, authorization_confirmed boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.guardians; c public.children; l public.guardian_child_links;
begin
  select * into g from public.guardians where id = target_guardian_id;
  if not found or not public.staff_at_facility(g.facility_id) then raise exception 'Not authorized'; end if;
  perform pg_advisory_xact_lock(hashtextextended(g.facility_id::text, 0));
  select * into g from public.guardians where id = target_guardian_id for update;
  if authorization_confirmed is distinct from true then raise exception 'Guardian authorization is required'; end if;
  perform public.validate_live_child(child_details);
  perform public.validate_guardian_relationship(g.sex, child_details->>'relationship');
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
  insert into public.audit_logs(actor_id, facility_id, action, entity_type, entity_id, new_values)
  values(auth.uid(), g.facility_id, 'child_registered', 'children', c.id::text,
    jsonb_build_object('child', to_jsonb(c), 'guardian_child_link', to_jsonb(l)));
  return jsonb_build_object('guardian', to_jsonb(g), 'child', to_jsonb(c), 'link', to_jsonb(l));
end $$;

-- Raw codes are returned only to the issuing worker, never stored in plaintext.
-- Reissuing invalidates previous pending invitations. No SMS/email is sent here.
create function public.issue_guardian_invitation(target_guardian_id uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare g public.guardians; invitation public.guardian_invitations; raw_code text;
begin
  select * into g from public.guardians where id = target_guardian_id for update;
  if not found or not public.staff_at_facility(g.facility_id) then raise exception 'Not authorized'; end if;
  if g.profile_id is not null then raise exception 'Guardian access is already linked'; end if;
  if g.access_status = 'disabled' then raise exception 'Guardian online access is disabled'; end if;
  update public.guardian_invitations set status = 'revoked' where guardian_id = g.id and status = 'pending';
  raw_code := 'ACT-' || upper(encode(gen_random_bytes(16), 'hex'));
  insert into public.guardian_invitations(guardian_id, activation_code_hash, expires_at, issued_by)
  values(g.id, encode(digest(raw_code, 'sha256'), 'hex'), now() + interval '7 days', auth.uid()) returning * into invitation;
  update public.guardians set access_status = 'invitation_pending' where id = g.id returning * into g;
  insert into public.audit_logs(actor_id, facility_id, action, entity_type, entity_id, new_values)
  values(auth.uid(), g.facility_id, 'invitation_issued', 'guardian_invitations', invitation.id::text,
    jsonb_build_object('guardian_id', g.id, 'expires_at', invitation.expires_at, 'channel', 'printed_slip'));
  return jsonb_build_object('guardian', to_jsonb(g), 'invitation',
    (to_jsonb(invitation) - 'activation_code_hash') || jsonb_build_object('activation_code', raw_code));
end $$;

-- Register all children and optionally issue an invitation in one transaction.
-- Failure of any child or invitation rolls back the entire registration.
create function public.register_family_with_access(guardian_details jsonb, child_details jsonb,
  authorization_confirmed boolean, request_online_access boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare family jsonb; issued jsonb; facility uuid;
begin
  facility := public.current_facility_id();
  if not public.staff_at_facility(facility) then raise exception 'Not authorized'; end if;
  family := public.register_family(guardian_details, child_details, authorization_confirmed);
  if request_online_access then
    issued := public.issue_guardian_invitation((family->>'id')::uuid);
    family := family || (issued->'guardian') || jsonb_build_object('issued_invitation', issued->'invitation');
  end if;
  insert into public.audit_logs(actor_id, facility_id, action, entity_type, entity_id, new_values)
  values(auth.uid(), facility, 'family_registered', 'guardians', family->>'id', family - 'issued_invitation');
  return family;
end $$;

-- Edits cannot activate/deactivate accounts. That is a separate access workflow.
-- Lock guardian before invitation, matching issuance/reissue to avoid lock inversion.
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
  insert into public.profiles(id,facility_id,username,full_name,role,active)
  values(auth_user_id,g.facility_id,lower(trim(requested_username)),g.full_name,'guardian',true);
  update public.guardians set profile_id=auth_user_id, access_status='active' where id=g.id;
  update public.guardian_invitations set status='used',used_at=now() where id=inv.id;
  insert into public.audit_logs(actor_id,facility_id,action,entity_type,entity_id,new_values)
  values(auth_user_id,g.facility_id,'guardian_activated','guardians',g.id::text,jsonb_build_object('profile_id',auth_user_id));
end $$;

create function public.correct_guardian_details(target_guardian_id uuid, changes jsonb, correction_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.guardians; before_g jsonb; correction public.guardian_corrections;
  before_links jsonb; after_links jsonb; before_requests jsonb; after_requests jsonb;
begin
  select * into g from public.guardians where id = target_guardian_id;
  if not found or not public.staff_at_facility(g.facility_id) then raise exception 'Not authorized'; end if;
  perform pg_advisory_xact_lock(hashtextextended(g.facility_id::text, 0));
  select * into g from public.guardians where id = target_guardian_id for update;
  if nullif(trim(correction_reason), '') is null then raise exception 'A correction reason is required'; end if;
  if nullif(trim(changes->>'full_name'), '') is null or coalesce(changes->>'sex','') not in ('male','female') then
    raise exception 'Guardian name and sex are required'; end if;
  if changes - array['full_name','sex','phone','address'] <> '{}'::jsonb then raise exception 'Unsupported correction fields'; end if;
  before_g := to_jsonb(g);
  select coalesce(jsonb_agg(to_jsonb(l) order by l.id), '[]') into before_links from public.guardian_child_links l where l.guardian_id = g.id;
  select coalesce(jsonb_agg(to_jsonb(r) order by r.id), '[]') into before_requests from public.child_link_requests r where r.guardian_id = g.id and r.status='pending';
  update public.guardians set full_name = trim(changes->>'full_name'), sex = changes->>'sex',
    phone = nullif(trim(changes->>'phone'), ''), address = trim(changes->>'address') where id = g.id returning * into g;
  -- Only the gendered label changes; the relationship category and primary flag do not.
  update public.guardian_child_links set relationship = public.relationship_for_guardian_sex(g.sex, relationship)
    where guardian_id = g.id;
  -- Pending requests remain reviewable after a demographic correction. Past
  -- review decisions retain the relationship recorded at the time of review.
  update public.child_link_requests set relationship = public.relationship_for_guardian_sex(g.sex, relationship)
    where guardian_id = g.id and status='pending';
  if g.profile_id is not null then update public.profiles set full_name = g.full_name where id = g.profile_id; end if;
  select coalesce(jsonb_agg(to_jsonb(l) order by l.id), '[]') into after_links from public.guardian_child_links l where l.guardian_id = g.id;
  select coalesce(jsonb_agg(to_jsonb(r) order by r.id), '[]') into after_requests from public.child_link_requests r where r.guardian_id = g.id and r.status='pending';
  insert into public.guardian_corrections(correction_code, guardian_id, previous_values, updated_values, reason, corrected_by)
  values(public.live_entity_code('GCOR'), g.id, before_g || jsonb_build_object('links',before_links,'pending_requests',before_requests),
    to_jsonb(g) || jsonb_build_object('links',after_links,'pending_requests',after_requests), trim(correction_reason), auth.uid()) returning * into correction;
  return jsonb_build_object('guardian', to_jsonb(g), 'correction', to_jsonb(correction));
end $$;

-- Use the same facility-first lock order for requests and corrections. This
-- also prevents a guardian's sex changing between validation and submission.
create or replace function public.submit_family_child_request(child_details jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare g public.guardians; request_id uuid;
begin
  select * into g from public.guardians where profile_id=auth.uid();
  if not found or not public.owns_guardian(g.id) then raise exception 'Not authorized'; end if;
  perform pg_advisory_xact_lock(hashtextextended(g.facility_id::text,0));
  select * into g from public.guardians where profile_id=auth.uid() for update;
  if not public.owns_guardian(g.id) then raise exception 'Not authorized'; end if;
  perform public.validate_live_child(child_details);
  perform public.validate_guardian_relationship(g.sex,child_details->>'relationship');
  if exists(select 1 from public.child_link_requests where guardian_id=g.id and status='pending'
      and lower(trim(child_name))=lower(trim(child_details->>'full_name')) and birth_date=(child_details->>'birth_date')::date) then
    raise exception 'A pending request already exists for this child'; end if;
  insert into public.child_link_requests(request_code,guardian_id,child_name,birth_date,sex,relationship)
  values(public.live_entity_code('CLR'),g.id,trim(child_details->>'full_name'),(child_details->>'birth_date')::date,
    child_details->>'sex',child_details->>'relationship') returning id into request_id;
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
    added := public.add_family_child(g.id,jsonb_build_object('full_name',r.child_name,'sex',r.sex,
      'birth_date',r.birth_date,'relationship',r.relationship),true);
  end if;
  update public.child_link_requests set status=case when approve_request then 'approved' else 'rejected' end,
    linked_child_id=(added->'child'->>'id')::uuid, reviewed_by=auth.uid(),reviewed_at=now(),review_notes=trim(notes)
    where id=r.id returning * into r;
  insert into public.audit_logs(actor_id,facility_id,action,entity_type,entity_id,old_values,new_values)
  values(auth.uid(),g.facility_id,'child_request_reviewed','child_link_requests',r.id::text,before_r,to_jsonb(r));
  return r.id;
end $$;

create function public.correct_child_details(target_child_id uuid, target_guardian_id uuid, changes jsonb, correction_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.children; g public.guardians; l public.guardian_child_links; before_c jsonb; correction public.child_corrections;
begin
  select * into c from public.children where id = target_child_id;
  if not found or not public.staff_at_facility(c.facility_id) then raise exception 'Not authorized'; end if;
  perform pg_advisory_xact_lock(hashtextextended(c.facility_id::text, 0));
  select * into c from public.children where id = target_child_id for update;
  select * into g from public.guardians where id = target_guardian_id;
  if not found or g.facility_id <> c.facility_id then raise exception 'Not authorized'; end if;
  select * into l from public.guardian_child_links where child_id = c.id and guardian_id = g.id and status = 'approved' for update;
  if not found then raise exception 'An approved guardian-child link is required'; end if;
  if nullif(trim(correction_reason),'') is null then raise exception 'A correction reason is required'; end if;
  perform public.validate_live_child(changes);
  perform public.validate_guardian_relationship(g.sex, changes->>'relationship');
  if changes - array['full_name','sex','birth_date','relationship'] <> '{}'::jsonb then raise exception 'Unsupported correction fields'; end if;
  if exists(select 1 from public.children where id <> c.id and facility_id = c.facility_id
    and lower(trim(full_name)) = lower(trim(changes->>'full_name')) and birth_date = (changes->>'birth_date')::date and sex = changes->>'sex') then
    raise exception 'A matching child record already exists. Review the existing record before linking.'; end if;
  if exists(select 1 from public.vaccination_records where child_id = c.id and status <> 'voided'
    and administered_on < (changes->>'birth_date')::date) then raise exception 'Birth date cannot be after a recorded vaccination'; end if;
  before_c := to_jsonb(c) || jsonb_build_object('guardian_child_link', to_jsonb(l));
  update public.children set full_name = trim(changes->>'full_name'), sex = changes->>'sex', birth_date = (changes->>'birth_date')::date
    where id = c.id returning * into c;
  -- A relationship belongs to a particular guardian-child pair, not the child globally.
  update public.guardian_child_links set relationship = changes->>'relationship' where id = l.id returning * into l;
  insert into public.child_corrections(correction_code, child_id, previous_values, updated_values, reason, corrected_by)
  values(public.live_entity_code('CCOR'), c.id, before_c, to_jsonb(c) || jsonb_build_object('guardian_child_link',to_jsonb(l)),
    trim(correction_reason), auth.uid()) returning * into correction;
  return jsonb_build_object('child', to_jsonb(c), 'link', to_jsonb(l), 'guardian_sex', g.sex, 'correction', to_jsonb(correction));
end $$;

-- Prevent bypassing audited family transactions using direct REST writes.
revoke insert, update, delete on public.guardians, public.children, public.guardian_child_links,
  public.guardian_corrections, public.child_corrections, public.guardian_invitations from authenticated;
alter function public.register_family(jsonb,jsonb,boolean) security definer;
revoke execute on function public.register_family(jsonb,jsonb,boolean) from authenticated;
revoke all on function public.validate_guardian_relationship(text,text), public.issue_guardian_invitation(uuid),
  public.relationship_for_guardian_sex(text,text),
  public.register_family_with_access(jsonb,jsonb,boolean,boolean), public.correct_guardian_details(uuid,jsonb,text),
  public.correct_child_details(uuid,uuid,jsonb,text) from public;
grant execute on function public.issue_guardian_invitation(uuid), public.register_family_with_access(jsonb,jsonb,boolean,boolean),
  public.correct_guardian_details(uuid,jsonb,text), public.correct_child_details(uuid,uuid,jsonb,text) to authenticated;

commit;
