begin;

create or replace function public.record_first_visit_review(
  target_child_id uuid,
  has_documents boolean
)
returns public.first_visit_reviews
language plpgsql
security definer
set search_path = public
as $$
declare result_row public.first_visit_reviews%rowtype;
begin
  if not public.is_health_worker()
     or not public.can_access_live_child(target_child_id) then
    raise exception 'Not authorized to record this first-visit review';
  end if;

  insert into public.first_visit_reviews (
    review_code, child_id, has_documented_previous_vaccinations,
    reviewed_by, reviewed_at
  ) values (
    public.live_entity_code('FVR'), target_child_id, has_documents,
    auth.uid(), now()
  )
  on conflict (child_id) do update set
    has_documented_previous_vaccinations = excluded.has_documented_previous_vaccinations,
    reviewed_by = excluded.reviewed_by,
    reviewed_at = now()
  returning * into result_row;

  return result_row;
end;
$$;

revoke all on function public.record_first_visit_review(uuid, boolean)
  from public, anon;
grant execute on function public.record_first_visit_review(uuid, boolean)
  to authenticated;

commit;
