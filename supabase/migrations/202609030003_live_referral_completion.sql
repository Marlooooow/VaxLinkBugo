begin;

create or replace function public.record_external_vaccinations(
  target_group_id uuid,
  target_item_ids uuid[],
  administered_on_date date,
  receiving_facility text,
  receiving_worker text,
  visit_notes text default ''
)
returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare
  group_record public.referral_groups%rowtype;
  item_record public.referral_items%rowtype;
  visit_id uuid := extensions.gen_random_uuid();
  visit_code text := 'EV-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 6, '0');
  result jsonb := '[]'::jsonb;
  record_code text;
  item_id uuid;
begin
  select * into group_record from public.referral_groups
  where id = target_group_id for update;
  if group_record.id is null then raise exception 'Referral group was not found.'; end if;
  if not public.staff_at_facility(group_record.originating_facility_id) then
    raise exception 'You do not have permission to complete this referral.';
  end if;
  if coalesce(array_length(target_item_ids, 1), 0) = 0 then
    raise exception 'Select at least one referral item.';
  end if;

  insert into public.external_vaccination_visits (
    id, referral_group_id, administered_on, administering_facility,
    health_worker_name, notes, verified_by, verification_method
  ) values (
    visit_id, group_record.id, administered_on_date, trim(receiving_facility),
    trim(receiving_worker), nullif(trim(visit_notes), ''), auth.uid(),
    'referral_qr'
  );

  foreach item_id in array target_item_ids loop
    select * into item_record from public.referral_items
    where id = item_id and referral_group_id = group_record.id for update;
    if item_record.id is null then raise exception 'Referral item was not found.'; end if;
    if item_record.status <> 'pending' then raise exception 'Referral item is already completed.'; end if;
    record_code := 'VR-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 6, '0');
    insert into public.vaccination_records (
      vaccination_code, child_id, vaccine_id, dose_number, administered_on,
      facility_id, external_facility_name, administered_by,
      external_health_worker_name, referral_item_id, external_visit_id,
      evidence_type, source, status, notes
    ) values (
      record_code, group_record.child_id, item_record.vaccine_id,
      item_record.dose_number, administered_on_date,
      group_record.originating_facility_id, trim(receiving_facility), auth.uid(),
      trim(receiving_worker), item_record.id, visit_id, 'referral_qr',
      'external_referral', 'recorded', nullif(trim(visit_notes), '')
    );
    insert into public.external_visit_items (visit_id, referral_item_id, vaccination_record_id)
    values (visit_id, item_record.id, (select id from public.vaccination_records where vaccination_code = record_code));
    update public.referral_items set status = 'completed', completed_at = now() where id = item_record.id;
    result := result || jsonb_build_array(jsonb_build_object('id', item_record.id, 'referral_code', item_record.referral_code, 'status', 'Completed', 'completed_at', now()));
  end loop;

  update public.referral_groups rg set status = case when not exists (
    select 1 from public.referral_items ri where ri.referral_group_id = rg.id and ri.status = 'pending'
  ) then 'completed' else 'partial' end where rg.id = group_record.id;
  return jsonb_build_object('visit_id', visit_id, 'visit_code', visit_code, 'items', result);
end;
$$;

revoke all on function public.record_external_vaccinations(uuid, uuid[], date, text, text, text) from public, anon;
grant execute on function public.record_external_vaccinations(uuid, uuid[], date, text, text, text) to authenticated;
commit;
