begin;

create or replace function public.get_facility_reminder_summary()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with actionable as (
    select reminder.*, vaccine.name as vaccine_name
    from public.reminders reminder
    join public.children child on child.id = reminder.child_id
    join public.vaccine_definitions vaccine on vaccine.id = reminder.vaccine_id
    where public.is_health_worker()
      and child.facility_id = public.current_facility_id()
      and reminder.status in ('overdue', 'due_today', 'upcoming')
      and reminder.due_on <= current_date + 30
  ),
  vaccine_counts as (
    select
      vaccine_id,
      vaccine_name,
      count(*) filter (where status = 'due_today')::integer as due_today,
      count(*) filter (where status = 'overdue')::integer as overdue
    from actionable
    where status in ('due_today', 'overdue')
    group by vaccine_id, vaccine_name
  )
  select jsonb_build_object(
    'due_today', count(*) filter (where status = 'due_today'),
    'overdue', count(*) filter (where status = 'overdue'),
    'upcoming', count(*) filter (where status = 'upcoming'),
    'guardian_ids', coalesce(
      jsonb_agg(distinct guardian_id)
        filter (where status in ('due_today', 'overdue')),
      '[]'::jsonb
    ),
    'vaccine_counts', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'vaccine_id', vaccine_id,
          'vaccine_name', vaccine_name,
          'due_today', due_today,
          'overdue', overdue
        )
        order by due_today + overdue desc, vaccine_name
      )
      from vaccine_counts
    ), '[]'::jsonb)
  )
  from actionable;
$$;

revoke all on function public.get_facility_reminder_summary()
  from public, anon;
grant execute on function public.get_facility_reminder_summary()
  to authenticated;

commit;
