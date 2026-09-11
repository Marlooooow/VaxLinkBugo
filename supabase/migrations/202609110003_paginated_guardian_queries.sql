begin;

create index if not exists appointments_guardian_schedule_id_idx
  on public.appointments (guardian_id, scheduled_for, id);
create index if not exists reminders_guardian_status_due_child_idx
  on public.reminders (guardian_id, status, due_on, child_id, id);

create or replace function public.get_guardian_appointment_page(
  p_guardian_id uuid,
  p_appointment_id uuid default null,
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
    where appointment.guardian_id = p_guardian_id
      and exists (
        select 1 from public.guardians guardian
        where guardian.id = p_guardian_id
          and guardian.profile_id = auth.uid()
      )
      and (p_appointment_id is null or appointment.id = p_appointment_id)
  ),
  page as (
    select * from filtered
    order by scheduled_for, id
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
        to_jsonb(page) || jsonb_build_object(
          'children', jsonb_build_object('full_name', page.child_name),
          'vaccine_definitions', jsonb_build_object('name', page.vaccine_name),
          'facilities', jsonb_build_object('name', page.facility_name)
        ) order by page.scheduled_for, page.id
      ) from page
    ), '[]'::jsonb),
    'total_count', totals.total_count,
    'has_more', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
      < totals.total_count,
    'next_offset', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
  ) from totals;
$$;

create or replace function public.get_guardian_appointment_offer_page(
  p_guardian_id uuid,
  p_status text default null,
  p_offer_id uuid default null,
  p_page_size integer default 20,
  p_page_offset integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with base as (
    select
      offer.*,
      appointment.guardian_id,
      appointment.child_id,
      appointment.vaccine_id,
      appointment.dose_number,
      appointment.scheduled_for as current_appointment_date,
      child.full_name as child_name,
      vaccine.name as vaccine_name,
      case
        when offer.status = 'pending' and offer.expires_at <= now()
          then 'expired'
        else offer.status
      end as computed_status
    from public.appointment_offers offer
    join public.appointments appointment on appointment.id = offer.appointment_id
    join public.children child on child.id = appointment.child_id
    join public.vaccine_definitions vaccine on vaccine.id = appointment.vaccine_id
    where appointment.guardian_id = p_guardian_id
      and offer.status <> 'withdrawn'
      and exists (
        select 1 from public.guardians guardian
        where guardian.id = p_guardian_id
          and guardian.profile_id = auth.uid()
      )
  ),
  filtered as (
    select * from base
    where (p_offer_id is null or id = p_offer_id)
      and (p_status is null or computed_status = p_status)
  ),
  page as (
    select * from filtered
    order by expires_at, id
    offset greatest(coalesce(p_page_offset, 0), 0)
    limit least(greatest(coalesce(p_page_size, 20), 1), 50)
  ),
  totals as (
    select
      (select count(*)::integer from filtered) as total_count,
      (select count(*)::integer from base where computed_status = 'pending')
        as pending_count,
      (select count(*)::integer from page) as selected_count
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', page.id,
        'offer_code', page.offer_code,
        'appointment_id', page.appointment_id,
        'guardian_id', page.guardian_id,
        'child_id', page.child_id,
        'child_name', page.child_name,
        'vaccine_id', page.vaccine_id,
        'vaccine_name', page.vaccine_name,
        'dose_number', page.dose_number,
        'current_appointment_date', page.current_appointment_date,
        'offered_appointment_date', page.offered_for,
        'status', page.computed_status,
        'created_at', page.created_at,
        'expires_at', page.expires_at,
        'responded_at', page.responded_at
      ) order by page.expires_at, page.id) from page
    ), '[]'::jsonb),
    'total_count', totals.total_count,
    'pending_count', totals.pending_count,
    'has_more', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
      < totals.total_count,
    'next_offset', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
  ) from totals;
$$;

create or replace function public.get_guardian_reminder_summary(
  p_guardian_id uuid,
  p_child_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'due_today', count(*) filter (where reminder.status = 'due_today'),
    'overdue', count(*) filter (where reminder.status = 'overdue'),
    'upcoming', count(*) filter (where reminder.status = 'upcoming'),
    'unread', count(*) filter (where not reminder.is_read)
  )
  from public.reminders reminder
  where reminder.guardian_id = p_guardian_id
    and (p_child_id is null or reminder.child_id = p_child_id)
    and reminder.status in ('overdue', 'due_today', 'upcoming')
    and reminder.due_on <= current_date + 30
    and exists (
      select 1 from public.guardians guardian
      where guardian.id = p_guardian_id
        and guardian.profile_id = auth.uid()
    );
$$;

create or replace function public.get_guardian_reminder_child_page(
  p_guardian_id uuid,
  p_status text default null,
  p_child_id uuid default null,
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
    where reminder.guardian_id = p_guardian_id
      and (p_child_id is null or reminder.child_id = p_child_id)
      and (p_status is null or reminder.status = p_status)
      and reminder.status in ('overdue', 'due_today', 'upcoming')
      and reminder.due_on <= current_date + 30
      and exists (
        select 1 from public.guardians guardian
        where guardian.id = p_guardian_id
          and guardian.profile_id = auth.uid()
      )
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
    limit least(greatest(coalesce(p_page_size, 10), 1), 50)
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

revoke all on function public.get_guardian_appointment_page(
  uuid, uuid, integer, integer
) from public;
grant execute on function public.get_guardian_appointment_page(
  uuid, uuid, integer, integer
) to authenticated;

revoke all on function public.get_guardian_appointment_offer_page(
  uuid, text, uuid, integer, integer
) from public;
grant execute on function public.get_guardian_appointment_offer_page(
  uuid, text, uuid, integer, integer
) to authenticated;

revoke all on function public.get_guardian_reminder_summary(uuid, uuid)
  from public;
grant execute on function public.get_guardian_reminder_summary(uuid, uuid)
  to authenticated;

revoke all on function public.get_guardian_reminder_child_page(
  uuid, text, uuid, integer, integer
) from public;
grant execute on function public.get_guardian_reminder_child_page(
  uuid, text, uuid, integer, integer
) to authenticated;

create or replace function public.get_children_pnip_schedules(
  target_child_ids uuid[],
  schedule_as_of date default current_date
)
returns table (
  child_id uuid,
  schedule_rule_id uuid,
  vaccine_id text,
  vaccine_name text,
  dose_number integer,
  scheduled_date date,
  status text,
  administered_date date,
  vaccination_record_id uuid
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if coalesce(cardinality(target_child_ids), 0) > 50 then
    raise exception 'A maximum of 50 child schedules can be requested at once.';
  end if;

  if exists (
    select 1
    from unnest(coalesce(target_child_ids, '{}'::uuid[])) requested(child_id)
    left join public.children child on child.id = requested.child_id
    where child.id is null
       or not (
         public.guardian_can_access_child(requested.child_id)
         or public.staff_at_facility(child.facility_id)
       )
  ) then
    raise exception 'One or more child schedules are unavailable.';
  end if;

  return query
  select
    requested.child_id,
    schedule.schedule_rule_id,
    schedule.vaccine_id,
    schedule.vaccine_name,
    schedule.dose_number,
    schedule.scheduled_date,
    schedule.status,
    schedule.administered_date,
    schedule.vaccination_record_id
  from unnest(coalesce(target_child_ids, '{}'::uuid[])) requested(child_id)
  cross join lateral public.calculate_child_pnip_schedule(
    requested.child_id,
    schedule_as_of
  ) schedule
  order by requested.child_id, schedule.scheduled_date,
    schedule.vaccine_id, schedule.dose_number;
end;
$$;

revoke all on function public.get_children_pnip_schedules(uuid[], date)
  from public;
grant execute on function public.get_children_pnip_schedules(uuid[], date)
  to authenticated;

commit;
