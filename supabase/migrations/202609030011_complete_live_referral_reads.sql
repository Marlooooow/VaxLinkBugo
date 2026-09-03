begin;

alter table public.referral_items
  add column if not exists scheduled_due_date date;

update public.referral_items ri
set scheduled_due_date = rg.issued_on
from public.referral_groups rg
where rg.id = ri.referral_group_id and ri.scheduled_due_date is null;

alter table public.external_vaccination_visits
  add column if not exists visit_code text;

update public.external_vaccination_visits
set visit_code = 'EV-' || replace(id::text, '-', '')
where visit_code is null;

create unique index if not exists external_vaccination_visits_visit_code_key
  on public.external_vaccination_visits(visit_code);

create or replace function public.verify_live_referral_group(
  target_group_id uuid, supplied_token text default null
) returns text language plpgsql security definer set search_path = '' as $$
declare group_record public.referral_groups%rowtype;
begin
  select * into group_record from public.referral_groups where id = target_group_id;
  if group_record.id is null then return 'not_found'; end if;
  if not public.staff_at_facility(group_record.originating_facility_id) then
    raise exception 'Only health-center staff can verify this referral.';
  end if;
  if supplied_token is not null and supplied_token <> '' and
     group_record.qr_token_hash <> encode(extensions.digest(supplied_token, 'sha256'), 'hex') then
    return 'invalid_token';
  end if;
  if group_record.status = 'completed' then return 'completed'; end if;
  if group_record.status in ('cancelled', 'expired') then return 'cancelled'; end if;
  return 'valid';
end;
$$;

create or replace function public.create_referral_group(target_child_id uuid, target_vaccine_ids text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  child_record public.children%rowtype;
  facility_name text;
  group_id uuid := extensions.gen_random_uuid();
  group_code text;
  raw_token text := encode(extensions.gen_random_bytes(24), 'hex');
  result jsonb := '[]'::jsonb;
  target_vaccine_id text;
  target_dose_number integer;
  target_due_date date;
  rule_record public.pnip_schedule_rules%rowtype;
  item_id uuid;
  item_code text;
  item jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication is required.'; end if;
  select c.* into child_record from public.children c where c.id = target_child_id and c.status = 'active';
  if child_record.id is null then raise exception 'Child was not found.'; end if;
  if not public.staff_at_facility(child_record.facility_id) then raise exception 'You do not have permission to create this referral.'; end if;
  select f.name into facility_name from public.facilities f where f.id = child_record.facility_id;
  group_code := 'RGRP-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 6, '0');
  insert into public.referral_groups (id, referral_group_code, child_id, originating_facility_id, issued_by, issued_on, expires_on, status, qr_token_hash)
  values (group_id, group_code, child_record.id, child_record.facility_id, auth.uid(), current_date, current_date + 30, 'pending', encode(extensions.digest(raw_token, 'sha256'), 'hex'));
  foreach target_vaccine_id in array target_vaccine_ids loop
    select coalesce(max(vr.dose_number), 0) + 1 into target_dose_number from public.vaccination_records vr where vr.child_id = child_record.id and vr.vaccine_id = target_vaccine_id and vr.status <> 'voided';
    select r.* into rule_record from public.pnip_schedule_rules r where r.vaccine_id = target_vaccine_id and r.dose_number = target_dose_number and r.active = true and r.effective_from <= current_date and (r.effective_to is null or r.effective_to >= current_date) order by r.effective_from desc limit 1;
    if rule_record.id is null then raise exception 'No active PNIP schedule rule exists for % dose %.', target_vaccine_id, target_dose_number; end if;
    target_due_date := child_record.birth_date + rule_record.recommended_age_days;
    item_id := extensions.gen_random_uuid();
    item_code := 'REF-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 6, '0');
    insert into public.referral_items (id, referral_code, referral_group_id, vaccine_id, dose_number, scheduled_due_date, status) values (item_id, item_code, group_id, target_vaccine_id, target_dose_number, target_due_date, 'pending');
    select jsonb_build_object('id', ri.id, 'referral_code', ri.referral_code, 'referral_group_id', rg.id, 'referral_group_code', rg.referral_group_code, 'child_id', c.id, 'child_name', c.full_name, 'vaccine_id', ri.vaccine_id, 'vaccine_name', vd.name, 'dose_number', ri.dose_number, 'scheduled_due_date', ri.scheduled_due_date, 'originating_facility', facility_name, 'status', 'Pending', 'created_at', rg.created_at, 'verification_token', raw_token) into item from public.referral_items ri join public.referral_groups rg on rg.id = ri.referral_group_id join public.children c on c.id = rg.child_id join public.vaccine_definitions vd on vd.id = ri.vaccine_id where ri.id = item_id;
    result := result || jsonb_build_array(item);
  end loop;
  if jsonb_array_length(result) = 0 then raise exception 'At least one unavailable vaccine is required.'; end if;
  return jsonb_build_object('referrals', result);
end;
$$;

create or replace function public.record_external_vaccinations(target_group_id uuid, target_item_ids uuid[], administered_on_date date, receiving_facility text, receiving_worker text, visit_notes text default '')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare group_record public.referral_groups%rowtype; item_record public.referral_items%rowtype; visit_id uuid := extensions.gen_random_uuid(); visit_code text := 'EV-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 6, '0'); item_id uuid; record_code text; result jsonb := '[]'::jsonb;
begin
  select * into group_record from public.referral_groups where id = target_group_id for update;
  if group_record.id is null then raise exception 'Referral group was not found.'; end if;
  if not public.staff_at_facility(group_record.originating_facility_id) then raise exception 'You do not have permission to complete this referral.'; end if;
  if coalesce(array_length(target_item_ids, 1), 0) = 0 then raise exception 'Select at least one referral item.'; end if;
  insert into public.external_vaccination_visits (id, visit_code, referral_group_id, administered_on, administering_facility, health_worker_name, notes, verified_by, verification_method) values (visit_id, visit_code, group_record.id, administered_on_date, trim(receiving_facility), trim(receiving_worker), nullif(trim(visit_notes), ''), auth.uid(), 'referral_qr');
  foreach item_id in array target_item_ids loop
    select * into item_record from public.referral_items where id = item_id and referral_group_id = group_record.id for update;
    if item_record.id is null then raise exception 'Referral item was not found.'; end if;
    if item_record.status <> 'pending' then raise exception 'Referral item is already completed.'; end if;
    record_code := 'VR-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 6, '0');
    insert into public.vaccination_records (vaccination_code, child_id, vaccine_id, dose_number, administered_on, facility_id, external_facility_name, administered_by, external_health_worker_name, referral_item_id, external_visit_id, evidence_type, source, status, notes) values (record_code, group_record.child_id, item_record.vaccine_id, item_record.dose_number, administered_on_date, group_record.originating_facility_id, trim(receiving_facility), auth.uid(), trim(receiving_worker), item_record.id, visit_id, 'referral_qr', 'external_referral', 'recorded', nullif(trim(visit_notes), ''));
    insert into public.external_visit_items (visit_id, referral_item_id, vaccination_record_id) values (visit_id, item_record.id, (select id from public.vaccination_records where vaccination_code = record_code));
    update public.referral_items set status = 'completed', completed_at = now() where id = item_record.id;
    result := result || jsonb_build_array(jsonb_build_object('id', item_record.id, 'referral_code', item_record.referral_code, 'status', 'Completed', 'completed_at', now()));
  end loop;
  update public.referral_groups rg set status = case when not exists (select 1 from public.referral_items ri where ri.referral_group_id = rg.id and ri.status = 'pending') then 'completed' else 'partial' end where rg.id = group_record.id;
  return jsonb_build_object('visit_id', visit_id, 'visit_code', visit_code, 'items', result);
end;
$$;

revoke all on function public.verify_live_referral_group(uuid,text) from public, anon;
grant execute on function public.verify_live_referral_group(uuid,text) to authenticated;
revoke all on function public.create_referral_group(uuid,text[]) from public, anon;
grant execute on function public.create_referral_group(uuid,text[]) to authenticated;
revoke all on function public.record_external_vaccinations(uuid,uuid[],date,text,text,text) from public, anon;
grant execute on function public.record_external_vaccinations(uuid,uuid[],date,text,text,text) to authenticated;
commit;
