begin;

create index if not exists child_link_requests_guardian_status_created_idx
  on public.child_link_requests (guardian_id, status, created_at desc, id desc);

create or replace function public.get_pending_child_link_request_page(
  p_search text default null,
  p_request_id uuid default null,
  p_page_size integer default 20,
  p_page_offset integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with filtered as (
    select request.*, guardian.full_name as guardian_name,
      guardian.sex as guardian_sex, guardian.facility_id
    from public.child_link_requests request
    join public.guardians guardian on guardian.id = request.guardian_id
    where public.is_health_worker()
      and guardian.facility_id = public.current_facility_id()
      and request.status = 'pending'
      and (p_request_id is null or request.id = p_request_id)
      and (
        nullif(trim(p_search), '') is null
        or lower(request.child_name) like '%' || lower(trim(p_search)) || '%'
        or lower(guardian.full_name) like '%' || lower(trim(p_search)) || '%'
        or lower(request.request_code) like '%' || lower(trim(p_search)) || '%'
      )
  ),
  page as (
    select * from filtered
    order by created_at desc, id desc
    offset greatest(coalesce(p_page_offset, 0), 0)
    limit least(greatest(coalesce(p_page_size, 20), 1), 50)
  ),
  totals as (
    select
      (select count(*)::integer from filtered) as total_count,
      (select count(*)::integer from page) as selected_count
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(
        (to_jsonb(page) - 'guardian_name' - 'guardian_sex' - 'facility_id')
        || jsonb_build_object(
          'guardians', jsonb_build_object(
            'full_name', page.guardian_name,
            'sex', page.guardian_sex,
            'facility_id', page.facility_id
          )
        ) order by page.created_at desc, page.id desc
      ) from page
    ), '[]'::jsonb),
    'total_count', totals.total_count,
    'has_more', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
      < totals.total_count,
    'next_offset', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
  ) from totals;
$$;

revoke all on function public.get_pending_child_link_request_page(
  text, uuid, integer, integer
) from public;
grant execute on function public.get_pending_child_link_request_page(
  text, uuid, integer, integer
) to authenticated;

commit;
