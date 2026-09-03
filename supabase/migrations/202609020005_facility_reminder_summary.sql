begin;

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
  where c.facility_id = public.current_facility_id();
$$;

revoke all on function public.get_facility_reminder_summary() from public, anon;
grant execute on function public.get_facility_reminder_summary() to authenticated;

commit;
