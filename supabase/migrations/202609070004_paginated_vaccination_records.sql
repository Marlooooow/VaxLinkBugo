-- Production vaccination-record browser for health workers.
-- Returns one child summary per row using stable cursor pagination. Full
-- vaccination history is intentionally fetched only after a child is opened.
begin;

create extension if not exists pg_trgm with schema extensions;

create index if not exists children_facility_active_created_idx
  on public.children (facility_id, created_at desc, id desc)
  where status = 'active';

create index if not exists guardian_child_links_child_approved_idx
  on public.guardian_child_links (child_id, is_primary desc, created_at)
  where status = 'approved';

create index if not exists vaccination_records_child_live_date_idx
  on public.vaccination_records (child_id, administered_on desc)
  where status <> 'voided';

create index if not exists children_full_name_trgm_idx
  on public.children using gin (lower(full_name) extensions.gin_trgm_ops);

create index if not exists guardians_full_name_trgm_idx
  on public.guardians using gin (lower(full_name) extensions.gin_trgm_ops);

create or replace function public.get_vaccination_record_summaries(
  p_search text default null,
  p_filter text default 'all',
  p_page_size integer default 20,
  p_cursor_sort_at timestamptz default null,
  p_cursor_child_id uuid default null
)
returns table (
  child_id uuid,
  child_code text,
  child_name text,
  child_birth_date date,
  child_sex text,
  guardian_id uuid,
  guardian_code text,
  guardian_name text,
  relationship text,
  recorded_count bigint,
  completed_count bigint,
  due_count bigint,
  overdue_count bigint,
  upcoming_count bigint,
  schedule_count bigint,
  latest_vaccine_name text,
  latest_dose_number integer,
  latest_administered_on date,
  sort_at timestamptz,
  total_count bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_facility uuid;
  safe_page_size integer := least(greatest(coalesce(p_page_size, 20), 10), 50);
  normalized_search text := lower(nullif(trim(p_search), ''));
  normalized_filter text := lower(coalesce(nullif(trim(p_filter), ''), 'all'));
begin
  if not public.is_health_worker() then
    raise exception 'Active health-worker access is required.';
  end if;

  target_facility := public.current_facility_id();
  if target_facility is null then
    raise exception 'The signed-in health worker has no active facility.';
  end if;

  if normalized_filter not in
      ('all', 'recorded', 'due_now', 'overdue', 'upcoming', 'completed') then
    raise exception 'Unsupported vaccination-record filter.';
  end if;

  return query
  with current_rules as (
    select distinct on (rule.vaccine_id, rule.dose_number)
      rule.vaccine_id,
      rule.dose_number,
      rule.recommended_age_days,
      rule.minimum_interval_days
    from public.pnip_schedule_rules rule
    where rule.active
      and rule.effective_from <= current_date
      and (rule.effective_to is null or rule.effective_to >= current_date)
    order by rule.vaccine_id, rule.dose_number, rule.effective_from desc
  ),
  child_scope as (
    select child.*
    from public.children child
    where child.facility_id = target_facility
      and child.status = 'active'
  ),
  owners as (
    select
      child.id as child_id,
      guardian.id as guardian_id,
      guardian.guardian_code,
      guardian.full_name as guardian_name,
      owner_link.relationship
    from child_scope child
    join lateral (
      select link.guardian_id, link.relationship
      from public.guardian_child_links link
      where link.child_id = child.id
        and link.status = 'approved'
      order by link.is_primary desc, link.created_at, link.id
      limit 1
    ) owner_link on true
    join public.guardians guardian on guardian.id = owner_link.guardian_id
  ),
  record_rollup as (
    select
      record.child_id,
      count(*) as recorded_count,
      max(record.administered_on) as latest_administered_on,
      (array_agg(definition.name order by record.administered_on desc, record.recorded_at desc))[1]
        as latest_vaccine_name,
      (array_agg(record.dose_number order by record.administered_on desc, record.recorded_at desc))[1]
        as latest_dose_number
    from public.vaccination_records record
    join child_scope child on child.id = record.child_id
    join public.vaccine_definitions definition on definition.id = record.vaccine_id
    where record.status <> 'voided'
    group by record.child_id
  ),
  schedule_entries as (
    select
      child.id as child_id,
      rule.vaccine_id,
      rule.dose_number,
      current_record.id as completed_record_id,
      case
        when rule.dose_number > 1 and previous_record.id is null then null
        when previous_record.id is not null
          and rule.minimum_interval_days is not null
          and previous_record.administered_on + rule.minimum_interval_days
              > child.birth_date + rule.recommended_age_days
          then previous_record.administered_on + rule.minimum_interval_days
        else child.birth_date + rule.recommended_age_days
      end as scheduled_on
    from child_scope child
    cross join current_rules rule
    left join public.vaccination_records current_record
      on current_record.child_id = child.id
     and current_record.vaccine_id = rule.vaccine_id
     and current_record.dose_number = rule.dose_number
     and current_record.status <> 'voided'
    left join public.vaccination_records previous_record
      on previous_record.child_id = child.id
     and previous_record.vaccine_id = rule.vaccine_id
     and previous_record.dose_number = rule.dose_number - 1
     and previous_record.status <> 'voided'
  ),
  schedule_rollup as (
    select
      entry.child_id,
      count(*) as schedule_count,
      count(*) filter (where entry.completed_record_id is not null) as completed_count,
      count(*) filter (
        where entry.completed_record_id is null and entry.scheduled_on = current_date
      ) as due_count,
      count(*) filter (
        where entry.completed_record_id is null and entry.scheduled_on < current_date
      ) as overdue_count,
      count(*) filter (
        where entry.completed_record_id is null and entry.scheduled_on > current_date
      ) as upcoming_count
    from schedule_entries entry
    group by entry.child_id
  ),
  summaries as (
    select
      child.id as child_id,
      child.child_code,
      child.full_name as child_name,
      child.birth_date as child_birth_date,
      child.sex as child_sex,
      owner.guardian_id,
      owner.guardian_code,
      owner.guardian_name,
      owner.relationship,
      coalesce(records.recorded_count, 0) as recorded_count,
      coalesce(schedule.completed_count, 0) as completed_count,
      coalesce(schedule.due_count, 0) as due_count,
      coalesce(schedule.overdue_count, 0) as overdue_count,
      coalesce(schedule.upcoming_count, 0) as upcoming_count,
      coalesce(schedule.schedule_count, 0) as schedule_count,
      records.latest_vaccine_name,
      records.latest_dose_number,
      records.latest_administered_on,
      coalesce(records.latest_administered_on::timestamptz, child.created_at) as sort_at
    from child_scope child
    join owners owner on owner.child_id = child.id
    left join record_rollup records on records.child_id = child.id
    left join schedule_rollup schedule on schedule.child_id = child.id
  ),
  filtered as (
    select summary.*
    from summaries summary
    where (
      normalized_search is null
      or lower(summary.child_name) like '%' || normalized_search || '%'
      or lower(summary.child_code) like '%' || normalized_search || '%'
      or lower(summary.guardian_name) like '%' || normalized_search || '%'
      or lower(summary.guardian_code) like '%' || normalized_search || '%'
      or exists (
        select 1
        from public.vaccination_records record
        join public.vaccine_definitions definition on definition.id = record.vaccine_id
        where record.child_id = summary.child_id
          and record.status <> 'voided'
          and lower(definition.name) like '%' || normalized_search || '%'
      )
    )
    and case normalized_filter
      when 'recorded' then summary.recorded_count > 0
      when 'due_now' then summary.due_count > 0
      when 'overdue' then summary.overdue_count > 0
      when 'upcoming' then summary.upcoming_count > 0
      when 'completed' then
        summary.schedule_count > 0
        and summary.completed_count = summary.schedule_count
      else true
    end
  ),
  counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
  )
  select
    page.child_id,
    page.child_code,
    page.child_name,
    page.child_birth_date,
    page.child_sex,
    page.guardian_id,
    page.guardian_code,
    page.guardian_name,
    page.relationship,
    page.recorded_count,
    page.completed_count,
    page.due_count,
    page.overdue_count,
    page.upcoming_count,
    page.schedule_count,
    page.latest_vaccine_name,
    page.latest_dose_number,
    page.latest_administered_on,
    page.sort_at,
    page.total_count
  from counted page
  where p_cursor_sort_at is null
     or p_cursor_child_id is null
     or (page.sort_at, page.child_id) < (p_cursor_sort_at, p_cursor_child_id)
  order by page.sort_at desc, page.child_id desc
  limit safe_page_size + 1;
end;
$$;

revoke all on function public.get_vaccination_record_summaries(
  text, text, integer, timestamptz, uuid
) from public;

grant execute on function public.get_vaccination_record_summaries(
  text, text, integer, timestamptz, uuid
) to authenticated;

commit;
