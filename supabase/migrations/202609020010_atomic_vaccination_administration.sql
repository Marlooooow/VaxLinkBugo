begin;

create or replace function public.complete_vaccination_administration(
  screening jsonb,
  records jsonb,
  doses jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_child uuid := (screening->>'child_id')::uuid;
  target_facility uuid;
  screening_row public.vaccination_screenings%rowtype;
  input_row jsonb;
  saved_row public.vaccination_records%rowtype;
  stock_row record;
  vaccine_key text;
  requested integer;
  remaining integer;
  take integer;
begin
  select facility_id into target_facility
  from public.profiles
  where id = auth.uid() and active and role in ('health_worker', 'administrator');
  if target_facility is null or not public.can_access_live_child(target_child) then
    raise exception 'You do not have permission to administer vaccines for this child';
  end if;
  if jsonb_typeof(records) <> 'array' or jsonb_array_length(records) = 0 then
    raise exception 'At least one vaccine must be selected';
  end if;

  insert into public.vaccination_screenings (
    screening_code, child_id, history_reviewed, current_condition_assessed,
    contraindications_reviewed, guardian_consent_confirmed, outcome,
    notes, screened_by, screened_at
  ) values (
    public.live_entity_code('SCR'), target_child,
    (screening->>'history_reviewed')::boolean,
    (screening->>'current_condition_assessed')::boolean,
    (screening->>'contraindications_reviewed')::boolean,
    (screening->>'guardian_consent_confirmed')::boolean,
    screening->>'outcome', coalesce(screening->>'notes', ''), auth.uid(), now()
  ) returning * into screening_row;

  for input_row in select value from jsonb_array_elements(records)
  loop
    insert into public.vaccination_records (
      vaccination_code, child_id, vaccine_id, dose_number, administered_on,
      facility_id, external_facility_name, administered_by,
      external_health_worker_name, screening_id, evidence_type, source,
      notes, recorded_by, recorded_at
    ) values (
      public.live_entity_code('VAX'),
      (input_row->>'child_id')::uuid,
      input_row->>'vaccine_id',
      (input_row->>'dose_number')::integer,
      (input_row->>'administered_on')::date,
      target_facility,
      nullif(input_row->>'external_facility_name', ''), auth.uid(),
      nullif(input_row->>'external_health_worker_name', ''), screening_row.id,
      nullif(input_row->>'evidence_type', ''), coalesce(input_row->>'source', 'local'),
      coalesce(input_row->>'notes', ''), auth.uid(), now()
    ) returning * into saved_row;
  end loop;

  for vaccine_key, requested in
    select key, value::text::integer from jsonb_each(doses)
  loop
    remaining := requested;
    for stock_row in
      select vb.id, vb.quantity
      from public.vaccine_batches vb
      join public.vaccine_inventory vi on vi.id = vb.inventory_id
      where vi.facility_id = target_facility
        and vi.vaccine_id = vaccine_key
        and vb.safety_status = 'usable'
        and vb.quantity > 0
        and vb.expiry_date > current_date
      order by vb.expiry_date, vb.id
      for update of vb
    loop
      exit when remaining <= 0;
      take := least(remaining, stock_row.quantity);
      perform public.record_inventory_movement(
        stock_row.id, 'administration', take,
        'Vaccine administered through child vaccination workflow', vaccine_key
      );
      remaining := remaining - take;
    end loop;
    if remaining > 0 then
      raise exception 'Insufficient usable stock for %', vaccine_key;
    end if;
  end loop;
end;
$$;

revoke all on function public.complete_vaccination_administration(jsonb, jsonb, jsonb)
  from public, anon;
grant execute on function public.complete_vaccination_administration(jsonb, jsonb, jsonb)
  to authenticated;

commit;
