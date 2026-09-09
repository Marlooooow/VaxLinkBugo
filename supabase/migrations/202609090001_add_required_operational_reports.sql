begin;

create or replace function public.get_child_vaccination_report(
  p_child_id uuid,
  p_from_date date,
  p_to_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  child_record public.children%rowtype;
  facility_name_value text;
  rows_value jsonb;
begin
  if not public.is_health_worker() then
    raise exception 'Health-worker access is required';
  end if;

  select child.* into child_record
    from public.children child
   where child.id = p_child_id
     and child.facility_id = public.current_facility_id()
     and child.status = 'active';

  if not found then
    raise exception 'The selected child was not found at this facility';
  end if;

  select facility.name into facility_name_value
    from public.facilities facility
   where facility.id = child_record.facility_id;

  select coalesce(jsonb_agg(to_jsonb(report_row)), '[]'::jsonb)
    into rows_value
    from (
      select definition.name as vaccine,
             vr.dose_number as dose,
             vr.administered_on::text as administered_on,
             initcap(replace(vr.source, '_', ' ')) as source,
             initcap(vr.status) as status,
             coalesce(vr.external_facility_name, facility.name,
                      facility_name_value, 'Not recorded') as facility,
             coalesce(vr.external_health_worker_name,
                      administering_profile.full_name,
                      recording_profile.full_name,
                      'Not recorded') as health_worker,
             vr.vaccination_code as record_number,
             coalesce(vr.notes, '') as notes
        from public.vaccination_records vr
        join public.vaccine_definitions definition
          on definition.id = vr.vaccine_id
        left join public.facilities facility on facility.id = vr.facility_id
        left join public.profiles administering_profile
          on administering_profile.id = vr.administered_by
        left join public.profiles recording_profile
          on recording_profile.id = vr.recorded_by
       where vr.child_id = child_record.id
         and vr.status <> 'voided'
       order by vr.administered_on desc, definition.name, vr.dose_number
    ) report_row;

  return jsonb_build_object(
    'report_type', 'child_vaccination_record',
    'title', child_record.full_name || ' - Vaccination Record',
    'facility_name', coalesce(facility_name_value, 'Health Center'),
    'from_date', child_record.birth_date,
    'to_date', current_date,
    'generated_at', now(),
    'columns', jsonb_build_array(
      jsonb_build_object('key', 'vaccine', 'label', 'Vaccine'),
      jsonb_build_object('key', 'dose', 'label', 'Dose'),
      jsonb_build_object('key', 'administered_on', 'label', 'Date'),
      jsonb_build_object('key', 'source', 'label', 'Source'),
      jsonb_build_object('key', 'status', 'label', 'Status'),
      jsonb_build_object('key', 'facility', 'label', 'Facility'),
      jsonb_build_object('key', 'health_worker', 'label', 'Health Worker'),
      jsonb_build_object('key', 'record_number', 'label', 'Record Number'),
      jsonb_build_object('key', 'notes', 'label', 'Notes')
    ),
    'rows', rows_value
  );
end;
$$;

create or replace function public.get_inventory_transaction_report(
  p_from_date date,
  p_to_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  facility_id_value uuid;
  facility_name_value text;
  rows_value jsonb;
begin
  if not public.is_health_worker() then
    raise exception 'Health-worker access is required';
  end if;
  if p_from_date is null or p_to_date is null or p_from_date > p_to_date then
    raise exception 'Choose a valid report period';
  end if;
  if p_to_date - p_from_date > 366 then
    raise exception 'Report periods cannot exceed 366 days';
  end if;

  facility_id_value := public.current_facility_id();
  select facility.name into facility_name_value
    from public.facilities facility
   where facility.id = facility_id_value;

  select coalesce(jsonb_agg(to_jsonb(report_row)), '[]'::jsonb)
    into rows_value
    from (
      select tx.created_at::date::text as transaction_date,
             tx.transaction_code,
             definition.name as vaccine,
             coalesce(batch.lot_number, 'Not applicable') as batch_lot,
             initcap(replace(tx.transaction_type, '_', ' ')) as transaction_type,
             tx.quantity_delta as quantity_change,
             tx.balance_before,
             tx.balance_after,
             tx.reason,
             coalesce(tx.reference_number, '') as reference_number,
             coalesce(profile.full_name, 'Unknown staff') as performed_by
        from public.inventory_transactions tx
        join public.vaccine_inventory inventory
          on inventory.id = tx.inventory_id
        join public.vaccine_definitions definition
          on definition.id = inventory.vaccine_id
        left join public.vaccine_batches batch on batch.id = tx.batch_id
        left join public.profiles profile on profile.id = tx.performed_by
       where inventory.facility_id = facility_id_value
         and tx.created_at::date between p_from_date and p_to_date
       order by tx.created_at desc, tx.id desc
    ) report_row;

  return jsonb_build_object(
    'report_type', 'inventory_transactions',
    'title', 'Vaccine Inventory Transaction Report',
    'facility_name', coalesce(facility_name_value, 'Health Center'),
    'from_date', p_from_date,
    'to_date', p_to_date,
    'generated_at', now(),
    'columns', jsonb_build_array(
      jsonb_build_object('key', 'transaction_date', 'label', 'Date'),
      jsonb_build_object('key', 'transaction_code', 'label', 'Transaction Number'),
      jsonb_build_object('key', 'vaccine', 'label', 'Vaccine'),
      jsonb_build_object('key', 'batch_lot', 'label', 'Batch / Lot'),
      jsonb_build_object('key', 'transaction_type', 'label', 'Type'),
      jsonb_build_object('key', 'quantity_change', 'label', 'Quantity Change'),
      jsonb_build_object('key', 'balance_before', 'label', 'Balance Before'),
      jsonb_build_object('key', 'balance_after', 'label', 'Balance After'),
      jsonb_build_object('key', 'reason', 'label', 'Reason'),
      jsonb_build_object('key', 'reference_number', 'label', 'Reference'),
      jsonb_build_object('key', 'performed_by', 'label', 'Performed By')
    ),
    'rows', rows_value
  );
end;
$$;

revoke all on function public.get_child_vaccination_report(uuid, date, date)
  from public, anon;
grant execute on function public.get_child_vaccination_report(uuid, date, date)
  to authenticated;

revoke all on function public.get_inventory_transaction_report(date, date)
  from public, anon;
grant execute on function public.get_inventory_transaction_report(date, date)
  to authenticated;

commit;
