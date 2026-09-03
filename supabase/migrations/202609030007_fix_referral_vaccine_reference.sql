begin;

create or replace function public.create_referral_group(target_child_id uuid, target_vaccine_ids text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  child_record public.children%rowtype;
  facility_name text;
  group_id uuid;
  group_code text;
  raw_token text := encode(extensions.gen_random_bytes(24), 'hex');
  item jsonb;
  result jsonb := '[]'::jsonb;
  target_vaccine_id text;
  dose_number integer;
  due_date date;
  rule_record public.pnip_schedule_rules%rowtype;
  item_id uuid;
  item_code text;
begin
  if auth.uid() is null then raise exception 'Authentication is required.'; end if;
  select c.* into child_record from public.children c where c.id = target_child_id and c.status = 'active';
  if child_record.id is null then raise exception 'Child was not found.'; end if;
  if not public.staff_at_facility(child_record.facility_id) then raise exception 'You do not have permission to create this referral.'; end if;
  select f.name into facility_name from public.facilities f where f.id = child_record.facility_id;
  group_id := extensions.gen_random_uuid();
  group_code := 'RGRP-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 6, '0');
  insert into public.referral_groups (id, referral_group_code, child_id, originating_facility_id, issued_by, issued_on, expires_on, status, qr_token_hash)
  values (group_id, group_code, child_record.id, child_record.facility_id, auth.uid(), current_date, current_date + 30, 'pending', encode(extensions.digest(raw_token, 'sha256'), 'hex'));
  foreach target_vaccine_id in array target_vaccine_ids loop
    select coalesce(max(vr.dose_number), 0) + 1 into dose_number from public.vaccination_records vr where vr.child_id = child_record.id and vr.vaccine_id = target_vaccine_id and vr.status <> 'voided';
    select * into rule_record from public.pnip_schedule_rules r where r.vaccine_id = target_vaccine_id and r.dose_number = dose_number and r.active = true and r.effective_from <= current_date and (r.effective_to is null or r.effective_to >= current_date) order by r.effective_from desc limit 1;
    if rule_record.id is null then raise exception 'No active PNIP schedule rule exists for % dose %.', target_vaccine_id, dose_number; end if;
    due_date := child_record.birth_date + rule_record.recommended_age_days;
    item_id := extensions.gen_random_uuid();
    item_code := 'REF-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 6, '0');
    insert into public.referral_items (id, referral_code, referral_group_id, vaccine_id, dose_number, status) values (item_id, item_code, group_id, target_vaccine_id, dose_number, 'pending');
    select jsonb_build_object('id', ri.id, 'referral_code', ri.referral_code, 'referral_group_id', rg.id, 'referral_group_code', rg.referral_group_code, 'child_id', c.id, 'child_name', c.full_name, 'vaccine_id', ri.vaccine_id, 'vaccine_name', vd.name, 'dose_number', ri.dose_number, 'scheduled_due_date', due_date, 'originating_facility', facility_name, 'status', 'Pending', 'created_at', rg.created_at, 'verification_token', raw_token) into item
    from public.referral_items ri join public.referral_groups rg on rg.id = ri.referral_group_id join public.children c on c.id = rg.child_id join public.vaccine_definitions vd on vd.id = ri.vaccine_id where ri.id = item_id;
    result := result || jsonb_build_array(item);
  end loop;
  if jsonb_array_length(result) = 0 then raise exception 'At least one unavailable vaccine is required.'; end if;
  return jsonb_build_object('referrals', result);
end;
$$;

revoke all on function public.create_referral_group(uuid, text[]) from public, anon;
grant execute on function public.create_referral_group(uuid, text[]) to authenticated;
commit;
