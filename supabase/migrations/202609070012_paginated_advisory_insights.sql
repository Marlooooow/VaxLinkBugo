begin;

create index if not exists advisory_insights_facility_generated_id_idx
  on public.advisory_insights (facility_id, generated_at desc, id desc);

create or replace function public.get_advisory_insight_page(
  p_severity text default null,
  p_status text default null,
  p_insight_id uuid default null,
  p_page_size integer default 20,
  p_page_offset integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with facility_rows as (
    select insight.*
    from public.advisory_insights insight
    where public.is_health_worker()
      and insight.facility_id = public.current_facility_id()
  ),
  filtered as (
    select facility_rows.*
    from facility_rows
    where (p_insight_id is null or facility_rows.id = p_insight_id)
      and (p_severity is null or facility_rows.severity = p_severity)
      and (p_status is null or facility_rows.status = p_status)
  ),
  page as (
    select filtered.*
    from filtered
    order by filtered.generated_at desc, filtered.id desc
    offset greatest(coalesce(p_page_offset, 0), 0)
    limit least(greatest(coalesce(p_page_size, 20), 1), 50)
  ),
  totals as (
    select
      (select count(*)::integer from filtered) as total_count,
      (select count(*)::integer from page) as selected_count
  ),
  summary as (
    select jsonb_build_object(
      'high', count(*) filter (where severity = 'high'),
      'medium', count(*) filter (where severity = 'medium'),
      'new', count(*) filter (where status = 'new_insight')
    ) as value
    from facility_rows
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(
        to_jsonb(page)
        || jsonb_build_object(
          'children', case when child.id is null then null else
            jsonb_build_object('full_name', child.full_name) end,
          'vaccine_definitions', case when vaccine.id is null then null else
            jsonb_build_object('name', vaccine.name) end
        ) order by page.generated_at desc, page.id desc
      )
      from page
      left join public.children child on child.id = page.child_id
      left join public.vaccine_definitions vaccine on vaccine.id = page.vaccine_id
    ), '[]'::jsonb),
    'summary', (select value from summary),
    'total_count', totals.total_count,
    'has_more', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
      < totals.total_count,
    'next_offset', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
  ) from totals;
$$;

revoke all on function public.get_advisory_insight_page(
  text, text, uuid, integer, integer
) from public;
grant execute on function public.get_advisory_insight_page(
  text, text, uuid, integer, integer
) to authenticated;

commit;
