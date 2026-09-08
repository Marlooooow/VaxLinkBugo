begin;

create index if not exists appointment_offers_appointment_expiry_id_idx
  on public.appointment_offers (appointment_id, expires_at, id);

create or replace function public.get_facility_appointment_offer_page(
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
    where public.is_health_worker()
      and appointment.facility_id = public.current_facility_id()
      and offer.status <> 'withdrawn'
  ),
  filtered as (
    select * from base
    where (p_offer_id is null or id = p_offer_id)
      and (p_status is null or computed_status = p_status)
  ),
  page as (
    select * from filtered
    order by expires_at asc, id asc
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
      ) order by page.expires_at asc, page.id asc)
      from page
    ), '[]'::jsonb),
    'total_count', totals.total_count,
    'pending_count', totals.pending_count,
    'has_more', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
      < totals.total_count,
    'next_offset', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
  ) from totals;
$$;

revoke all on function public.get_facility_appointment_offer_page(
  text, uuid, integer, integer
) from public;
grant execute on function public.get_facility_appointment_offer_page(
  text, uuid, integer, integer
) to authenticated;

commit;
