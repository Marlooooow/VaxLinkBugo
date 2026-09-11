begin;

alter table public.first_visit_reviews
  add column if not exists history_status text,
  add column if not exists history_notes text;

update public.first_visit_reviews
set history_status = case
  when has_documented_previous_vaccinations then 'verified_records'
  else 'unknown_history'
end
where history_status is null;

alter table public.first_visit_reviews
  alter column history_status set default 'unknown_history',
  alter column history_status set not null;
alter table public.first_visit_reviews
  drop constraint if exists first_visit_reviews_history_status_check;
alter table public.first_visit_reviews
  add constraint first_visit_reviews_history_status_check
  check (history_status in ('verified_records', 'unknown_history', 'confirmed_none'));

create or replace function public.record_first_visit_review(
  target_child_id uuid,
  selected_history_status text,
  review_notes text default ''
)
returns public.first_visit_reviews
language plpgsql security definer set search_path = public as $$
declare result_row public.first_visit_reviews%rowtype;
begin
  if not public.is_health_worker()
     or not public.can_access_live_child(target_child_id) then
    raise exception 'Not authorized to record this first-visit review.';
  end if;
  if selected_history_status not in ('verified_records', 'unknown_history', 'confirmed_none') then
    raise exception 'Select a valid previous vaccination history status.';
  end if;
  if selected_history_status = 'unknown_history' and length(trim(review_notes)) < 3 then
    raise exception 'Document why the previous vaccination history is unavailable.';
  end if;
  insert into public.first_visit_reviews(
    review_code, child_id, has_documented_previous_vaccinations,
    history_status, history_notes, reviewed_by, reviewed_at
  ) values (
    public.live_entity_code('FVR'), target_child_id,
    selected_history_status = 'verified_records', selected_history_status,
    nullif(trim(review_notes), ''), auth.uid(), now()
  )
  on conflict (child_id) do update set
    has_documented_previous_vaccinations = excluded.has_documented_previous_vaccinations,
    history_status = excluded.history_status,
    history_notes = excluded.history_notes,
    reviewed_by = excluded.reviewed_by,
    reviewed_at = now()
  returning * into result_row;
  return result_row;
end $$;

revoke all on function public.record_first_visit_review(uuid, text, text)
  from public, anon;
grant execute on function public.record_first_visit_review(uuid, text, text)
  to authenticated;

commit;
