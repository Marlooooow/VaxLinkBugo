begin;

create or replace function public.get_filtered_facility_follow_up_child_page(
  p_status text default null,
  p_page_size integer default 10,
  p_page_offset integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with actionable as (
    select reminder.*
    from public.reminders reminder
    join public.children child on child.id = reminder.child_id
    where public.is_health_worker()
      and child.facility_id = public.current_facility_id()
      and (p_status is null or reminder.status = p_status)
      and reminder.status in ('overdue', 'due_today', 'upcoming')
      and reminder.due_on <= current_date + 30
  ),
  ranked_children as (
    select child_id, min(due_on) as first_due_on
    from actionable
    group by child_id
  ),
  page_children as (
    select * from ranked_children
    order by first_due_on, child_id
    offset greatest(coalesce(p_page_offset, 0), 0)
    limit least(greatest(coalesce(p_page_size, 10), 1), 100)
  ),
  page_rows as (
    select
      jsonb_build_object(
        'id', reminder.id,
        'reminder_code', reminder.reminder_code,
        'guardian_id', reminder.guardian_id,
        'child_id', reminder.child_id,
        'vaccine_id', reminder.vaccine_id,
        'dose_number', reminder.dose_number,
        'due_on', reminder.due_on,
        'status', reminder.status,
        'delivery_channel', reminder.delivery_channel,
        'is_read', reminder.is_read,
        'created_at', reminder.created_at,
        'updated_at', reminder.updated_at,
        'children', jsonb_build_object('full_name', child.full_name),
        'vaccine_definitions', jsonb_build_object('name', vaccine.name)
      ) as item,
      page_children.first_due_on,
      reminder.due_on,
      reminder.id
    from page_children
    join actionable reminder on reminder.child_id = page_children.child_id
    join public.children child on child.id = reminder.child_id
    join public.vaccine_definitions vaccine on vaccine.id = reminder.vaccine_id
  ),
  totals as (
    select count(*)::integer as total_children from ranked_children
  ),
  selected as (
    select count(*)::integer as selected_children from page_children
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(
        page_rows.item order by page_rows.first_due_on, page_rows.due_on, page_rows.id
      ) from page_rows
    ), '[]'::jsonb),
    'has_more', greatest(coalesce(p_page_offset, 0), 0)
      + (select selected_children from selected)
      < (select total_children from totals),
    'next_offset', greatest(coalesce(p_page_offset, 0), 0)
      + (select selected_children from selected)
  );
$$;

revoke all on function public.get_filtered_facility_follow_up_child_page(
  text, integer, integer
) from public;
grant execute on function public.get_filtered_facility_follow_up_child_page(
  text, integer, integer
) to authenticated;

commit;
