begin;

create or replace function public.get_operational_report(
  p_report_type text,
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
  title_value text;
  columns_value jsonb;
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
  select f.name into facility_name_value
    from public.facilities f
   where f.id = facility_id_value;

  if p_report_type = 'follow_ups' then
    title_value := 'Due and Overdue Children Report';
    columns_value := jsonb_build_array(
      jsonb_build_object('key', 'child', 'label', 'Child'),
      jsonb_build_object('key', 'guardian', 'label', 'Guardian'),
      jsonb_build_object('key', 'mobile', 'label', 'Mobile'),
      jsonb_build_object('key', 'due_today', 'label', 'Due Today'),
      jsonb_build_object('key', 'overdue', 'label', 'Overdue'),
      jsonb_build_object('key', 'earliest_due', 'label', 'Earliest Due'),
      jsonb_build_object('key', 'vaccines', 'label', 'Vaccines')
    );
    select coalesce(jsonb_agg(to_jsonb(report_row)), '[]'::jsonb)
      into rows_value
      from (
        select c.full_name as child,
               g.full_name as guardian,
               coalesce(g.phone, 'Not provided') as mobile,
               count(*) filter (where r.status = 'due_today')::integer as due_today,
               count(*) filter (where r.status = 'overdue')::integer as overdue,
               min(r.due_on)::text as earliest_due,
               string_agg(
                 v.name || ' Dose ' || r.dose_number::text || ' (' ||
                 replace(r.status, '_', ' ') || ' - ' || r.due_on::text || ')',
                 '; ' order by r.due_on, v.name, r.dose_number
               ) as vaccines
          from public.reminders r
          join public.children c on c.id = r.child_id
          join public.guardians g on g.id = r.guardian_id
          join public.vaccine_definitions v on v.id = r.vaccine_id
         where c.facility_id = facility_id_value
           and r.status in ('due_today', 'overdue')
           and r.due_on <= p_to_date
         group by c.id, c.full_name, g.id, g.full_name, g.phone
         order by min(r.due_on), c.full_name
      ) report_row;
  elsif p_report_type = 'vaccination_accomplishment' then
    title_value := 'Vaccination Accomplishment Report';
    columns_value := jsonb_build_array(
      jsonb_build_object('key', 'vaccine', 'label', 'Vaccine'),
      jsonb_build_object('key', 'dose', 'label', 'Dose'),
      jsonb_build_object('key', 'administered', 'label', 'Administered'),
      jsonb_build_object('key', 'local', 'label', 'Local'),
      jsonb_build_object('key', 'external', 'label', 'External'),
      jsonb_build_object('key', 'previous_record', 'label', 'Previous Record')
    );
    select coalesce(jsonb_agg(to_jsonb(report_row)), '[]'::jsonb)
      into rows_value
      from (
        select v.name as vaccine,
               vr.dose_number as dose,
               count(*)::integer as administered,
               count(*) filter (where vr.source = 'local')::integer as local,
               count(*) filter (where vr.source = 'external_referral')::integer as external,
               count(*) filter (where vr.source = 'previous_record')::integer as previous_record
          from public.vaccination_records vr
          join public.children c on c.id = vr.child_id
          join public.vaccine_definitions v on v.id = vr.vaccine_id
         where c.facility_id = facility_id_value
           and vr.status <> 'voided'
           and vr.administered_on between p_from_date and p_to_date
         group by v.name, vr.dose_number
         order by v.name, vr.dose_number
      ) report_row;
  elsif p_report_type = 'inventory' then
    title_value := 'Vaccine Inventory, Expiry, and Wastage Report';
    columns_value := jsonb_build_array(
      jsonb_build_object('key', 'vaccine', 'label', 'Vaccine'),
      jsonb_build_object('key', 'available', 'label', 'Available'),
      jsonb_build_object('key', 'reorder_level', 'label', 'Reorder Level'),
      jsonb_build_object('key', 'stock_status', 'label', 'Stock Status'),
      jsonb_build_object('key', 'expiring_batches', 'label', 'Expiring Batches'),
      jsonb_build_object('key', 'expired_doses', 'label', 'Expired Doses'),
      jsonb_build_object('key', 'wasted_in_period', 'label', 'Wasted in Period')
    );
    select coalesce(jsonb_agg(to_jsonb(report_row)), '[]'::jsonb)
      into rows_value
      from (
        select v.name as vaccine,
               coalesce(batch_totals.available, 0)::integer as available,
               inventory.reorder_level,
               case
                 when coalesce(batch_totals.available, 0) = 0 then 'Out of stock'
                 when coalesce(batch_totals.available, 0) <= inventory.reorder_level then 'Low stock'
                 else 'Available'
               end as stock_status,
               coalesce(batch_totals.expiring_batches, 0)::integer as expiring_batches,
               coalesce(batch_totals.expired_doses, 0)::integer as expired_doses,
               coalesce(wastage.wasted_in_period, 0)::integer as wasted_in_period
          from public.vaccine_inventory inventory
          join public.vaccine_definitions v on v.id = inventory.vaccine_id
          left join lateral (
            select coalesce(sum(batch.quantity) filter (
                     where batch.safety_status = 'usable'
                       and batch.packaging_intact
                       and batch.cold_chain_verified
                       and batch.vvm_status in ('acceptable', 'not_applicable')
                       and batch.expiry_date >= current_date
                   ), 0) as available,
                   count(*) filter (
                     where batch.quantity > 0
                       and batch.expiry_date between current_date and current_date + 90
                   ) as expiring_batches,
                   coalesce(sum(batch.quantity) filter (
                     where batch.quantity > 0
                       and batch.expiry_date < current_date
                   ), 0) as expired_doses
              from public.vaccine_batches batch
             where batch.inventory_id = inventory.id
          ) batch_totals on true
          left join lateral (
            select coalesce(sum(abs(tx.quantity_delta)), 0) as wasted_in_period
              from public.inventory_transactions tx
             where tx.inventory_id = inventory.id
               and tx.transaction_type = 'wastage'
               and tx.created_at::date between p_from_date and p_to_date
          ) wastage on true
         where inventory.facility_id = facility_id_value
         order by v.name
      ) report_row;
  else
    raise exception 'Unsupported report type';
  end if;

  return jsonb_build_object(
    'report_type', p_report_type,
    'title', title_value,
    'facility_name', coalesce(facility_name_value, 'Health Center'),
    'from_date', p_from_date,
    'to_date', p_to_date,
    'generated_at', now(),
    'columns', columns_value,
    'rows', rows_value
  );
end;
$$;

revoke all on function public.get_operational_report(text, date, date)
  from public, anon;
grant execute on function public.get_operational_report(text, date, date)
  to authenticated;

commit;
