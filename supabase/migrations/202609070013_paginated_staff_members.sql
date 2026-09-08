begin;

create index if not exists staff_members_facility_created_id_idx
  on public.staff_members (facility_id, created_at desc, id desc);

create or replace function public.get_staff_member_page(
  p_search text default null,
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
    select staff.*
    from public.staff_members staff
    where public.is_health_worker()
      and staff.facility_id = public.current_facility_id()
      and (
        nullif(trim(p_search), '') is null
        or lower(staff.full_name) like '%' || lower(trim(p_search)) || '%'
        or lower(staff.staff_code) like '%' || lower(trim(p_search)) || '%'
        or lower(coalesce(staff.email, '')) like '%' || lower(trim(p_search)) || '%'
        or lower(coalesce(staff.phone, '')) like '%' || lower(trim(p_search)) || '%'
      )
  ),
  page as (
    select filtered.*
    from filtered
    order by filtered.created_at desc, filtered.id desc
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
      select jsonb_agg(to_jsonb(page) order by page.created_at desc, page.id desc)
      from page
    ), '[]'::jsonb),
    'total_count', totals.total_count,
    'has_more', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
      < totals.total_count,
    'next_offset', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
  ) from totals;
$$;

revoke all on function public.get_staff_member_page(text, integer, integer)
  from public;
grant execute on function public.get_staff_member_page(text, integer, integer)
  to authenticated;

commit;
