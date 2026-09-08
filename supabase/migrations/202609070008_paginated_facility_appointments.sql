begin;

create index if not exists appointments_facility_schedule_id_idx
  on public.appointments (facility_id, scheduled_for, id);

create or replace function public.get_facility_appointment_page(
  p_appointment_id uuid default null,
  p_waitlist_vaccine_id text default null,
  p_waitlist_only boolean default false,
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
    select
      appointment.*,
      child.full_name as child_name,
      vaccine.name as vaccine_name,
      facility.name as facility_name
    from public.appointments appointment
    join public.children child on child.id = appointment.child_id
    join public.vaccine_definitions vaccine on vaccine.id = appointment.vaccine_id
    join public.facilities facility on facility.id = appointment.facility_id
    where public.is_health_worker()
      and appointment.facility_id = public.current_facility_id()
      and (p_appointment_id is null or appointment.id = p_appointment_id)
      and (not p_waitlist_only or appointment.status = 'waitlisted')
      and (
        p_waitlist_vaccine_id is null
        or (appointment.vaccine_id = p_waitlist_vaccine_id
          and appointment.status = 'waitlisted')
      )
  ),
  page as (
    select * from filtered
    order by
      case when p_waitlist_only or p_waitlist_vaccine_id is not null
        then case when priority = 'clinical_priority' then 1 else 0 end
        else 0 end desc,
      case when p_waitlist_only or p_waitlist_vaccine_id is not null
        then created_at end asc,
      scheduled_for asc,
      id asc
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
      select jsonb_agg(to_jsonb(page) || jsonb_build_object(
        'children', jsonb_build_object('full_name', page.child_name),
        'vaccine_definitions', jsonb_build_object('name', page.vaccine_name),
        'facilities', jsonb_build_object('name', page.facility_name)
      )) from page
    ), '[]'::jsonb),
    'total_count', totals.total_count,
    'has_more', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
      < totals.total_count,
    'next_offset', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
  ) from totals;
$$;

revoke all on function public.get_facility_appointment_page(
  uuid, text, boolean, integer, integer
) from public;
grant execute on function public.get_facility_appointment_page(
  uuid, text, boolean, integer, integer
) to authenticated;

commit;
