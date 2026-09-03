begin;

alter table public.vaccination_record_corrections
  add column if not exists reason text;

create or replace function public.correct_live_external_vaccination_record(
  target_record_id uuid, target_administered_on date, target_facility text,
  target_worker text, target_notes text, correction_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare corrected_id uuid;
begin
  if nullif(trim(correction_reason), '') is null then
    raise exception 'A correction reason is required.';
  end if;
  corrected_id := public.correct_live_vaccination_record(
    target_record_id, target_administered_on, target_facility, target_worker, target_notes
  );
  update public.vaccination_record_corrections
  set reason = trim(correction_reason)
  where id = (
    select id from public.vaccination_record_corrections
    where vaccination_record_id = corrected_id
    order by corrected_at desc limit 1
  );
  return corrected_id;
end;
$$;

revoke all on function public.correct_live_external_vaccination_record(uuid,date,text,text,text,text) from public, anon;
grant execute on function public.correct_live_external_vaccination_record(uuid,date,text,text,text,text) to authenticated;
commit;
