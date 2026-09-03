begin;

-- Reminder screens contain only actionable records: overdue, due today, or
-- upcoming within 30 days. The complete PNIP schedule remains in child views.
create or replace function public.get_facility_reminder_summary()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'due_today', count(*) filter (where r.status = 'due_today'),
    'overdue', count(*) filter (where r.status = 'overdue'),
    'upcoming', count(*) filter (where r.status = 'upcoming')
  )
  from public.reminders r
  join public.children c on c.id = r.child_id
  where public.is_health_worker()
    and c.facility_id = public.current_facility_id()
    and r.status in ('overdue', 'due_today', 'upcoming')
    and r.due_on <= current_date + 30;
$$;

revoke all on function public.get_facility_reminder_summary() from public, anon;
grant execute on function public.get_facility_reminder_summary() to authenticated;

create or replace function public.get_facility_follow_up_child_page(
  page_size integer default 10,
  page_offset integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with actionable_reminders as (
    select r.*
    from public.reminders r
    join public.children c on c.id = r.child_id
    where public.is_health_worker()
      and c.facility_id = public.current_facility_id()
      and r.status in ('overdue', 'due_today', 'upcoming')
      and r.due_on <= current_date + 30
  ),
  ranked_children as (
    select
      r.child_id,
      min(r.created_at) as first_reminder_created_at
    from actionable_reminders r
    group by r.child_id
  ),
  page_children as (
    select rc.child_id, rc.first_reminder_created_at
    from ranked_children rc
    order by rc.first_reminder_created_at, rc.child_id
    offset greatest(page_offset, 0)
    limit least(greatest(page_size, 1), 100)
  ),
  page_rows as (
    select
      jsonb_build_object(
        'id', r.id,
        'reminder_code', r.reminder_code,
        'guardian_id', r.guardian_id,
        'child_id', r.child_id,
        'vaccine_id', r.vaccine_id,
        'dose_number', r.dose_number,
        'due_on', r.due_on,
        'status', r.status,
        'delivery_channel', r.delivery_channel,
        'is_read', r.is_read,
        'created_at', r.created_at,
        'updated_at', r.updated_at,
        'children', jsonb_build_object('full_name', c.full_name),
        'vaccine_definitions', jsonb_build_object('name', v.name)
      ) as item,
      pc.first_reminder_created_at,
      r.created_at as reminder_created_at,
      r.id as reminder_id
    from page_children pc
    join actionable_reminders r on r.child_id = pc.child_id
    join public.children c on c.id = r.child_id
    join public.vaccine_definitions v on v.id = r.vaccine_id
  ),
  totals as (
    select count(*)::integer as total_children from ranked_children
  ),
  selected as (
    select count(*)::integer as selected_children from page_children
  )
  select jsonb_build_object(
    'items', coalesce(
      (
        select jsonb_agg(
          pr.item order by
            pr.first_reminder_created_at,
            pr.reminder_created_at,
            pr.reminder_id
        )
        from page_rows pr
      ),
      '[]'::jsonb
    ),
    'has_more',
      greatest(page_offset, 0) + (select selected_children from selected)
        < (select total_children from totals),
    'next_offset',
      greatest(page_offset, 0) + (select selected_children from selected)
  );
$$;

revoke all on function public.get_facility_follow_up_child_page(integer, integer)
  from public, anon;
grant execute on function public.get_facility_follow_up_child_page(integer, integer)
  to authenticated;

commit;
