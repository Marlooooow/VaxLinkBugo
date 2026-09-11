begin;

create extension if not exists pg_trgm with schema extensions;

create index if not exists outreach_sessions_facility_status_date_idx
  on public.outreach_sessions (
    facility_id, status, scheduled_on desc, created_at desc, id desc
  );

create index if not exists vaccine_batches_inventory_safety_expiry_idx
  on public.vaccine_batches (
    inventory_id, safety_status, expiry_date, id
  ) where quantity > 0;
create index if not exists outreach_sessions_title_trgm_idx
  on public.outreach_sessions using gin (
    lower(title) extensions.gin_trgm_ops
  );
create index if not exists outreach_sessions_location_trgm_idx
  on public.outreach_sessions using gin (
    lower(location) extensions.gin_trgm_ops
  );
create index if not exists outreach_sessions_code_trgm_idx
  on public.outreach_sessions using gin (
    lower(session_code) extensions.gin_trgm_ops
  );
create index if not exists vaccine_batches_lot_trgm_idx
  on public.vaccine_batches using gin (
    lower(lot_number) extensions.gin_trgm_ops
  );
create index if not exists vaccine_batches_code_trgm_idx
  on public.vaccine_batches using gin (
    lower(batch_code) extensions.gin_trgm_ops
  );

create or replace function public.get_outreach_session_page(
  p_search text default null,
  p_status text default null,
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
    select session.*
    from public.outreach_sessions session
    where public.is_health_worker()
      and session.facility_id = public.current_facility_id()
      and (p_status is null or session.status = p_status)
      and (
        nullif(trim(p_search), '') is null
        or lower(session.title) like '%' || lower(trim(p_search)) || '%'
        or lower(session.location) like '%' || lower(trim(p_search)) || '%'
        or lower(session.session_code) like '%' || lower(trim(p_search)) || '%'
      )
  ),
  page as (
    select filtered.*
    from filtered
    order by scheduled_on desc, created_at desc, id desc
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
      select jsonb_agg(to_jsonb(page) order by scheduled_on desc, created_at desc, id desc)
      from page
    ), '[]'::jsonb),
    'total_count', totals.total_count,
    'has_more', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
      < totals.total_count,
    'next_offset', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
  ) from totals;
$$;

create or replace function public.get_eligible_outreach_batch_page(
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
    select
      batch.id,
      batch.batch_code,
      inventory.facility_id,
      inventory.vaccine_id,
      vaccine.name as vaccine_name,
      batch.lot_number,
      batch.manufacturer,
      batch.expiry_date,
      batch.quantity_received,
      batch.quantity as available_doses,
      batch.received_at,
      batch.received_by as received_by_user_id,
      batch.packaging_intact,
      batch.cold_chain_verified,
      case batch.vvm_status
        when 'not_applicable' then 'notApplicable'
        when 'not_acceptable' then 'notAcceptable'
        else batch.vvm_status
      end as vvm_status,
      batch.safety_status,
      batch.safety_notes,
      batch.safety_reviewed_at,
      batch.safety_reviewed_by as safety_reviewed_by_user_id
    from public.vaccine_batches batch
    join public.vaccine_inventory inventory on inventory.id = batch.inventory_id
    join public.vaccine_definitions vaccine on vaccine.id = inventory.vaccine_id
    where public.is_health_worker()
      and inventory.facility_id = public.current_facility_id()
      and batch.safety_status = 'usable'
      and batch.quantity > 0
      and batch.expiry_date > current_date
      and (
        nullif(trim(p_search), '') is null
        or lower(vaccine.name) like '%' || lower(trim(p_search)) || '%'
        or lower(batch.lot_number) like '%' || lower(trim(p_search)) || '%'
        or lower(batch.batch_code) like '%' || lower(trim(p_search)) || '%'
        or lower(coalesce(batch.manufacturer, '')) like '%' || lower(trim(p_search)) || '%'
      )
  ),
  page as (
    select filtered.*
    from filtered
    order by expiry_date, vaccine_name, id
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
      select jsonb_agg(to_jsonb(page) order by expiry_date, vaccine_name, id)
      from page
    ), '[]'::jsonb),
    'total_count', totals.total_count,
    'has_more', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
      < totals.total_count,
    'next_offset', greatest(coalesce(p_page_offset, 0), 0) + totals.selected_count
  ) from totals;
$$;

revoke all on function public.get_outreach_session_page(
  text, text, integer, integer
) from public;
grant execute on function public.get_outreach_session_page(
  text, text, integer, integer
) to authenticated;

revoke all on function public.get_eligible_outreach_batch_page(
  text, integer, integer
) from public;
grant execute on function public.get_eligible_outreach_batch_page(
  text, integer, integer
) to authenticated;

commit;
