-- One facility-scoped query for the staff notification bell and inbox.
begin;

create index if not exists staff_notification_receipts_profile_notification_idx
  on public.staff_notification_receipts (profile_id, notification_id);

create index if not exists guardian_reset_facility_status_requested_idx
  on public.guardian_password_reset_requests (status, requested_at desc, guardian_id);

create index if not exists appointments_facility_status_updated_idx
  on public.appointments (facility_id, status, updated_at desc);

create index if not exists appointment_offers_status_created_idx
  on public.appointment_offers (status, created_at desc, appointment_id);

create index if not exists reminders_guardian_status_updated_idx
  on public.reminders (guardian_id, status, updated_at desc);

create index if not exists advisory_insights_facility_status_generated_idx
  on public.advisory_insights (facility_id, status, generated_at desc);

create or replace function public.get_staff_notification_page(
  p_unread_only boolean default false,
  p_page_size integer default 20,
  p_page_offset integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with inventory_totals as (
    select
      inventory.id,
      inventory.vaccine_id,
      inventory.reorder_level,
      inventory.updated_at,
      vaccine.name as vaccine_name,
      coalesce(sum(batch.quantity) filter (
        where batch.quantity > 0
          and batch.expiry_date >= current_date
          and batch.safety_status = 'usable'
          and batch.packaging_intact
          and batch.cold_chain_verified
          and batch.vvm_status in ('acceptable', 'not_applicable')
      ), 0)::integer as available_doses
    from public.vaccine_inventory inventory
    join public.vaccine_definitions vaccine on vaccine.id = inventory.vaccine_id
    left join public.vaccine_batches batch on batch.inventory_id = inventory.id
    where inventory.facility_id = public.current_facility_id()
    group by inventory.id, vaccine.name
  ),
  notification_rows as (
    select
      'request:' || request.id::text as id,
      'Child link request'::text as title,
      guardian.full_name || ' requested a link to ' || request.child_name || '.' as body,
      'requests'::text as target,
      request.id::text as entity_id,
      request.created_at
    from public.child_link_requests request
    join public.guardians guardian on guardian.id = request.guardian_id
    where guardian.facility_id = public.current_facility_id()
      and request.status = 'pending'

    union all

    select
      'stock:' || stock.id::text || ':' || (stock.available_doses = 0)::text,
      case when stock.available_doses = 0 then 'Stock unavailable' else 'Low stock' end,
      stock.vaccine_name || ': ' || stock.available_doses ||
        ' usable doses. Review stock.',
      'inventory',
      stock.vaccine_id,
      stock.updated_at
    from inventory_totals stock
    where stock.available_doses <= stock.reorder_level

    union all

    select
      'appointment:' || appointment.id::text || ':' || appointment.status,
      'Appointment ' || appointment.status,
      child.full_name || ' • ' || vaccine.name || '. Review appointment details.',
      'appointments',
      appointment.id::text,
      appointment.updated_at
    from public.appointments appointment
    join public.children child on child.id = appointment.child_id
    join public.vaccine_definitions vaccine on vaccine.id = appointment.vaccine_id
    where appointment.facility_id = public.current_facility_id()
      and appointment.status in ('cancelled', 'rescheduled')

    union all

    select
      'offer:' || offer.id::text || ':' || offer.status,
      case when offer.status = 'pending'
        then 'Earlier offer awaiting response'
        else 'Earlier appointment accepted'
      end,
      child.full_name || ' • ' || vaccine.name ||
        '. Review the earlier appointment offer.',
      'offers',
      offer.id::text,
      offer.created_at
    from public.appointment_offers offer
    join public.appointments appointment on appointment.id = offer.appointment_id
    join public.children child on child.id = appointment.child_id
    join public.vaccine_definitions vaccine on vaccine.id = appointment.vaccine_id
    where appointment.facility_id = public.current_facility_id()
      and offer.status in ('pending', 'accepted')

    union all

    select
      'follow-ups:' || current_date::text,
      'Daily follow-up summary',
      count(*) filter (where reminder.status = 'due_today') ||
        ' vaccine doses due today • ' ||
        count(*) filter (where reminder.status = 'overdue') ||
        ' overdue. Open reminders to review follow-up work.',
      'followUps',
      null::text,
      now()
    from public.reminders reminder
    join public.guardians guardian on guardian.id = reminder.guardian_id
    where guardian.facility_id = public.current_facility_id()
      and reminder.status in ('due_today', 'overdue')
    having count(*) > 0

    union all

    select
      'insight:' || insight.id::text,
      'Advisory: ' || insight.title,
      insight.summary || ' Recommendations require staff review.',
      'insights',
      insight.id::text,
      insight.generated_at
    from public.advisory_insights insight
    where insight.facility_id = public.current_facility_id()
      and insight.status = 'new_insight'

    union all

    select
      'password-reset:' || reset_request.id::text,
      'Guardian password reset requested',
      guardian.full_name || ' requested a password reset.',
      'passwordResets',
      reset_request.id::text,
      reset_request.requested_at
    from public.guardian_password_reset_requests reset_request
    join public.guardians guardian on guardian.id = reset_request.guardian_id
    where guardian.facility_id = public.current_facility_id()
      and reset_request.status = 'pending'
  ),
  secured as (
    select
      notification.*,
      receipt.notification_id is not null as is_read
    from notification_rows notification
    left join public.staff_notification_receipts receipt
      on receipt.profile_id = auth.uid()
      and receipt.notification_id = notification.id
    where public.is_health_worker()
  ),
  visible as (
    select * from secured
    where not p_unread_only or not is_read
  ),
  page as (
    select * from visible
    order by created_at desc, id desc
    offset greatest(coalesce(p_page_offset, 0), 0)
    limit least(greatest(coalesce(p_page_size, 20), 1), 50)
  ),
  totals as (
    select
      (select count(*)::integer from secured) as overall_count,
      (select count(*)::integer from visible) as total_count,
      (select count(*)::integer from secured where not is_read) as unread_count,
      (select count(*)::integer from page) as selected_count
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', page.id,
        'title', page.title,
        'body', page.body,
        'target', page.target,
        'entity_id', page.entity_id,
        'created_at', page.created_at
      ) order by page.created_at desc, page.id desc)
      from page
    ), '[]'::jsonb),
    'read_ids', coalesce((
      select jsonb_agg(page.id) from page where page.is_read
    ), '[]'::jsonb),
    'overall_count', totals.overall_count,
    'total_count', totals.total_count,
    'unread_count', totals.unread_count,
    'has_more', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
      < totals.total_count,
    'next_offset', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
  )
  from totals;
$$;

create or replace function public.get_staff_notification_unread_count()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (public.get_staff_notification_page(false, 1, 0)->>'unread_count')::integer,
    0
  );
$$;

revoke all on function public.get_staff_notification_page(boolean, integer, integer)
  from public;
grant execute on function public.get_staff_notification_page(boolean, integer, integer)
  to authenticated;
revoke all on function public.get_staff_notification_unread_count() from public;
grant execute on function public.get_staff_notification_unread_count()
  to authenticated;

commit;
