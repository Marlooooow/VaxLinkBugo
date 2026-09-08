-- Paginated family directory and reminder-state summaries.
begin;

-- Completing a dose can make the next dose eligible. Rebuild that child's
-- reminder rows immediately instead of waiting for a later screen refresh.
create or replace function public.sync_reminder_after_vaccination()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status is null or new.status = 'voided' then
    return new;
  end if;

  update public.reminders
  set status = 'completed', updated_at = now()
  where child_id = new.child_id
    and vaccine_id = new.vaccine_id
    and dose_number = new.dose_number
    and status <> 'completed';

  perform public.sync_child_reminders(new.child_id);
  return new;
end;
$$;

create index if not exists guardians_facility_created_idx
  on public.guardians (facility_id, created_at desc, id desc);

create index if not exists reminders_child_due_status_idx
  on public.reminders (child_id, due_on, status);

create or replace function public.get_registered_family_summary_page(
  p_search text default null,
  p_status text default null,
  p_guardian_ids uuid[] default null,
  p_page_size integer default 20,
  p_cursor_created_at timestamptz default null,
  p_cursor_guardian_id uuid default null
)
returns table (
  guardian jsonb,
  child_summaries jsonb,
  registered_at timestamptz,
  guardian_id uuid,
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
  normalized_status text := lower(nullif(trim(p_status), ''));
begin
  if not public.is_health_worker() then
    raise exception 'Active health-worker access is required.';
  end if;
  target_facility := public.current_facility_id();

  if normalized_status is not null
     and normalized_status not in ('completed', 'due_now', 'upcoming', 'overdue') then
    raise exception 'Unsupported family schedule filter.';
  end if;

  return query
  with child_states as (
    select
      child.id as child_id,
      child.full_name,
      child.child_code,
      child.birth_date,
      child.sex,
      link.guardian_id,
      link.relationship,
      case
        when bool_or(reminder.status <> 'completed' and reminder.due_on < current_date)
          then 'overdue'
        when bool_or(reminder.status <> 'completed' and reminder.due_on = current_date)
          then 'due_now'
        when count(reminder.id) > 0
          and bool_and(reminder.status = 'completed') then 'completed'
        else 'upcoming'
      end as schedule_state
    from public.children child
    join public.guardian_child_links link
      on link.child_id = child.id and link.status = 'approved'
    left join public.reminders reminder on reminder.child_id = child.id
    where child.facility_id = target_facility
      and child.status = 'active'
    group by child.id, link.guardian_id, link.relationship
  ),
  summaries as (
    select
      guardian_row.id as guardian_id,
      guardian_row.created_at as registered_at,
      to_jsonb(guardian_row) as guardian,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'child', jsonb_build_object(
              'id', state.child_id,
              'child_code', state.child_code,
              'full_name', state.full_name,
              'birth_date', state.birth_date,
              'sex', state.sex
            ),
            'relationship', state.relationship,
            'schedule_state', state.schedule_state
          ) order by state.full_name, state.child_id
        ) filter (where state.child_id is not null),
        '[]'::jsonb
      ) as child_summaries,
      array_remove(array_agg(state.schedule_state), null) as states
    from public.guardians guardian_row
    left join child_states state on state.guardian_id = guardian_row.id
    where guardian_row.facility_id = target_facility
      and (p_guardian_ids is null or guardian_row.id = any(p_guardian_ids))
      and (
        normalized_search is null
        or lower(guardian_row.full_name) like '%' || normalized_search || '%'
        or lower(guardian_row.guardian_code) like '%' || normalized_search || '%'
        or exists (
          select 1 from child_states searched_child
          where searched_child.guardian_id = guardian_row.id
            and (
              lower(searched_child.full_name) like '%' || normalized_search || '%'
              or lower(searched_child.child_code) like '%' || normalized_search || '%'
            )
        )
      )
    group by guardian_row.id
  ),
  filtered as (
    select summary.*
    from summaries summary
    where normalized_status is null or normalized_status = any(summary.states)
  ),
  counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
  )
  select
    page.guardian,
    page.child_summaries,
    page.registered_at,
    page.guardian_id,
    page.total_count
  from counted page
  where p_cursor_created_at is null
     or p_cursor_guardian_id is null
     or (page.registered_at, page.guardian_id)
        < (p_cursor_created_at, p_cursor_guardian_id)
  order by page.registered_at desc, page.guardian_id desc
  limit safe_page_size + 1;
end;
$$;

revoke all on function public.get_registered_family_summary_page(
  text, text, uuid[], integer, timestamptz, uuid
) from public;

grant execute on function public.get_registered_family_summary_page(
  text, text, uuid[], integer, timestamptz, uuid
) to authenticated;

commit;
