begin;

create or replace function public.get_vaccination_accomplishment_report(
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
      select definition.name as vaccine,
             record.dose_number as dose,
             count(*)::integer as administered,
             count(*) filter (where record.source = 'local')::integer as local,
             count(*) filter (
               where record.source = 'external_referral'
             )::integer as external,
             count(*) filter (
               where record.source = 'previous_record'
             )::integer as previous_record,
             count(*) filter (
               where record.source = 'outreach'
             )::integer as outreach
        from public.vaccination_records record
        join public.children child on child.id = record.child_id
        join public.vaccine_definitions definition
          on definition.id = record.vaccine_id
       where child.facility_id = facility_id_value
         and record.status <> 'voided'
         and record.administered_on between p_from_date and p_to_date
       group by definition.name, record.dose_number
       order by definition.name, record.dose_number
    ) report_row;

  return jsonb_build_object(
    'report_type', 'vaccination_accomplishment',
    'title', 'Vaccination Accomplishment Report',
    'facility_name', coalesce(facility_name_value, 'Health Center'),
    'from_date', p_from_date,
    'to_date', p_to_date,
    'generated_at', now(),
    'columns', jsonb_build_array(
      jsonb_build_object('key', 'vaccine', 'label', 'Vaccine'),
      jsonb_build_object('key', 'dose', 'label', 'Dose'),
      jsonb_build_object('key', 'administered', 'label', 'Administered'),
      jsonb_build_object('key', 'local', 'label', 'Local'),
      jsonb_build_object('key', 'outreach', 'label', 'Outreach'),
      jsonb_build_object('key', 'external', 'label', 'External'),
      jsonb_build_object(
        'key', 'previous_record', 'label', 'Previous Record'
      )
    ),
    'rows', rows_value
  );
end;
$$;

create or replace function public.get_outreach_session_report(
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
      select session.scheduled_on::text as session_date,
             session.session_code,
             session.title as activity,
             session.location,
             case session.status
               when 'reconciliation' then 'Awaiting approval'
               else initcap(replace(session.status, '_', ' '))
             end as status,
             coalesce(definition.name, 'No stock allocated') as vaccine,
             coalesce(batch.lot_number, 'Not applicable') as batch_lot,
             coalesce(coverage.children_vaccinated, 0)::integer
               as children_vaccinated,
             coalesce(allocation.allocated_quantity, 0)::integer as allocated,
             coalesce(allocation.administered_quantity, 0)::integer
               as administered,
             coalesce(allocation.returned_quantity, 0)::integer as returned,
             coalesce(allocation.wasted_quantity, 0)::integer as wasted,
             coalesce(allocation.quarantined_quantity, 0)::integer
               as quarantined,
             coalesce(
               allocation.allocated_quantity
               - allocation.administered_quantity
               - allocation.returned_quantity
               - allocation.wasted_quantity
               - allocation.quarantined_quantity,
               0
             )::integer as unaccounted,
             coalesce(creator.full_name, 'Unknown staff') as created_by,
             coalesce(approver.full_name, 'Not approved') as approved_by
        from public.outreach_sessions session
        left join public.outreach_stock_allocations allocation
          on allocation.session_id = session.id
        left join public.vaccine_batches batch on batch.id = allocation.batch_id
        left join public.vaccine_inventory inventory
          on inventory.id = batch.inventory_id
        left join public.vaccine_definitions definition
          on definition.id = inventory.vaccine_id
        left join public.profiles creator on creator.id = session.created_by
        left join public.profiles approver on approver.id = session.completed_by
        left join lateral (
          select count(distinct record.child_id)::integer
                   as children_vaccinated
            from public.vaccination_records record
           where record.outreach_session_id = session.id
             and record.status <> 'voided'
        ) coverage on true
       where session.facility_id = facility_id_value
         and session.scheduled_on between p_from_date and p_to_date
       order by session.scheduled_on desc, session.session_code,
                definition.name, batch.lot_number
    ) report_row;

  return jsonb_build_object(
    'report_type', 'outreach_sessions',
    'title', 'Outreach Immunization Session Report',
    'facility_name', coalesce(facility_name_value, 'Health Center'),
    'from_date', p_from_date,
    'to_date', p_to_date,
    'generated_at', now(),
    'columns', jsonb_build_array(
      jsonb_build_object('key', 'session_date', 'label', 'Date'),
      jsonb_build_object('key', 'session_code', 'label', 'Session'),
      jsonb_build_object('key', 'activity', 'label', 'Activity'),
      jsonb_build_object('key', 'location', 'label', 'Location'),
      jsonb_build_object('key', 'status', 'label', 'Status'),
      jsonb_build_object('key', 'vaccine', 'label', 'Vaccine'),
      jsonb_build_object('key', 'batch_lot', 'label', 'Batch / Lot'),
      jsonb_build_object(
        'key', 'children_vaccinated', 'label', 'Children Vaccinated'
      ),
      jsonb_build_object('key', 'allocated', 'label', 'Allocated'),
      jsonb_build_object('key', 'administered', 'label', 'Administered'),
      jsonb_build_object('key', 'returned', 'label', 'Returned'),
      jsonb_build_object('key', 'wasted', 'label', 'Wasted'),
      jsonb_build_object('key', 'quarantined', 'label', 'Quarantined'),
      jsonb_build_object('key', 'unaccounted', 'label', 'Unaccounted'),
      jsonb_build_object('key', 'created_by', 'label', 'Created By'),
      jsonb_build_object('key', 'approved_by', 'label', 'Approved By')
    ),
    'rows', rows_value
  );
end;
$$;

revoke all on function public.get_vaccination_accomplishment_report(date, date)
  from public, anon;
grant execute on function public.get_vaccination_accomplishment_report(date, date)
  to authenticated;

revoke all on function public.get_outreach_session_report(date, date)
  from public, anon;
grant execute on function public.get_outreach_session_report(date, date)
  to authenticated;

commit;
