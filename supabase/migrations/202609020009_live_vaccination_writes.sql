begin;

create or replace function public.record_vaccination_screening(
  target_child_id uuid,
  history_reviewed boolean,
  current_condition_assessed boolean,
  contraindications_reviewed boolean,
  guardian_consent_confirmed boolean,
  outcome text,
  notes text default ''
)
returns public.vaccination_screenings
language plpgsql
security definer
set search_path = public
as $$
declare result_row public.vaccination_screenings%rowtype;
begin
  if not public.is_health_worker()
     or not public.can_access_live_child(target_child_id) then
    raise exception 'Not authorized to screen this child';
  end if;
  if outcome not in ('cleared', 'deferred', 'referred') then
    raise exception 'Invalid screening outcome';
  end if;

  insert into public.vaccination_screenings (
    screening_code, child_id, history_reviewed, current_condition_assessed,
    contraindications_reviewed, guardian_consent_confirmed, outcome,
    notes, screened_by, screened_at
  ) values (
    public.live_entity_code('SCR'), target_child_id, history_reviewed,
    current_condition_assessed, contraindications_reviewed,
    guardian_consent_confirmed, outcome, coalesce(notes, ''), auth.uid(), now()
  ) returning * into result_row;
  return result_row;
end;
$$;

create or replace function public.record_vaccinations(records jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  input_row jsonb;
  saved_row public.vaccination_records%rowtype;
  result jsonb := '[]'::jsonb;
  target_facility uuid;
begin
  select facility_id into target_facility
  from public.profiles
  where id = auth.uid() and active and role in ('health_worker', 'administrator');
  if target_facility is null then raise exception 'Only an active health worker may record vaccinations'; end if;
  if jsonb_typeof(records) <> 'array' or jsonb_array_length(records) = 0 then
    raise exception 'At least one vaccination record is required';
  end if;

  for input_row in select value from jsonb_array_elements(records)
  loop
    if not public.can_access_live_child((input_row->>'child_id')::uuid) then
      raise exception 'Not authorized to record this child vaccination';
    end if;
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
      nullif(input_row->>'external_facility_name', ''),
      auth.uid(),
      nullif(input_row->>'external_health_worker_name', ''),
      nullif(input_row->>'screening_id', '')::uuid,
      nullif(input_row->>'evidence_type', ''),
      coalesce(input_row->>'source', 'local'),
      coalesce(input_row->>'notes', ''),
      auth.uid(), now()
    ) returning * into saved_row;
    result := result || jsonb_build_array(to_jsonb(saved_row));
  end loop;
  return result;
end;
$$;

revoke all on function public.record_vaccination_screening(uuid, boolean, boolean, boolean, boolean, text, text)
  from public, anon;
revoke all on function public.record_vaccinations(jsonb) from public, anon;
grant execute on function public.record_vaccination_screening(uuid, boolean, boolean, boolean, boolean, text, text)
  to authenticated;
grant execute on function public.record_vaccinations(jsonb) to authenticated;

commit;
