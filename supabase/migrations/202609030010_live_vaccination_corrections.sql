begin;

create table if not exists public.vaccination_record_corrections (
  id uuid primary key default extensions.gen_random_uuid(),
  correction_code text not null unique,
  vaccination_record_id uuid not null references public.vaccination_records(id),
  previous_values jsonb not null,
  updated_values jsonb not null,
  corrected_by uuid not null references public.profiles(id),
  corrected_at timestamptz not null default now()
);

alter table public.vaccination_record_corrections enable row level security;

create policy vaccination_corrections_staff_read on public.vaccination_record_corrections
for select to authenticated using (exists (
  select 1 from public.vaccination_records vr join public.children c on c.id = vr.child_id
  where vr.id = vaccination_record_id and public.staff_at_facility(c.facility_id)
));

create or replace function public.correct_live_vaccination_record(
  target_record_id uuid, target_administered_on date, target_facility text,
  target_worker text, target_notes text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare original public.vaccination_records%rowtype;
begin
  select vr.* into original from public.vaccination_records vr where vr.id = target_record_id for update;
  if original.id is null then raise exception 'Vaccination record was not found.'; end if;
  if not exists(select 1 from public.children c where c.id = original.child_id and public.staff_at_facility(c.facility_id)) then
    raise exception 'Only health-center staff can correct this vaccination record.';
  end if;
  insert into public.vaccination_record_corrections (
    correction_code, vaccination_record_id, previous_values, updated_values, corrected_by
  ) values (
    'VCOR-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 6, '0'),
    original.id,
    jsonb_build_object('administered_on', original.administered_on, 'external_facility_name', original.external_facility_name, 'external_health_worker_name', original.external_health_worker_name, 'notes', original.notes),
    jsonb_build_object('administered_on', target_administered_on, 'external_facility_name', nullif(trim(target_facility), ''), 'external_health_worker_name', nullif(trim(target_worker), ''), 'notes', nullif(trim(target_notes), '')),
    auth.uid()
  );
  update public.vaccination_records set
    administered_on = target_administered_on,
    external_facility_name = nullif(trim(target_facility), ''),
    external_health_worker_name = nullif(trim(target_worker), ''),
    notes = nullif(trim(target_notes), ''), status = 'corrected'
  where id = original.id;
  return original.id;
end;
$$;

revoke all on function public.correct_live_vaccination_record(uuid,date,text,text,text) from public, anon;
grant execute on function public.correct_live_vaccination_record(uuid,date,text,text,text) to authenticated;
commit;
