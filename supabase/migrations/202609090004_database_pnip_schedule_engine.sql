-- Make public.pnip_schedule_rules the single source of truth for live child
-- schedules, assessments, and reminder synchronization.
begin;

create or replace function public.calculate_child_pnip_schedule(
  target_child_id uuid,
  schedule_as_of date default current_date
)
returns table (
  schedule_rule_id uuid,
  vaccine_id text,
  vaccine_name text,
  dose_number integer,
  scheduled_date date,
  status text,
  administered_date date,
  vaccination_record_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  with active_rules as (
    select distinct on (rule.vaccine_id, rule.dose_number)
      rule.id,
      rule.vaccine_id,
      vaccine.name as vaccine_name,
      rule.dose_number,
      rule.recommended_age_days,
      rule.minimum_interval_days
    from public.pnip_schedule_rules rule
    join public.vaccine_definitions vaccine
      on vaccine.id = rule.vaccine_id
     and vaccine.active
    where rule.active
      and rule.effective_from <= schedule_as_of
      and (rule.effective_to is null or rule.effective_to >= schedule_as_of)
    order by
      rule.vaccine_id,
      rule.dose_number,
      rule.effective_from desc,
      rule.id desc
  ),
  recorded_doses as (
    select
      record.id,
      record.vaccine_id,
      record.dose_number,
      record.administered_on
    from public.vaccination_records record
    where record.child_id = target_child_id
      and record.status <> 'voided'
  ),
  calculated as (
    select
      rule.id as schedule_rule_id,
      rule.vaccine_id,
      rule.vaccine_name,
      rule.dose_number,
      greatest(
        child.birth_date + rule.recommended_age_days,
        case
          when prior.administered_on is not null
            and rule.minimum_interval_days is not null
          then prior.administered_on + rule.minimum_interval_days
          else child.birth_date + rule.recommended_age_days
        end
      )::date as scheduled_date,
      completed.administered_on as administered_date,
      completed.id as vaccination_record_id,
      prior.id as prior_record_id
    from public.children child
    cross join active_rules rule
    left join recorded_doses completed
      on completed.vaccine_id = rule.vaccine_id
     and completed.dose_number = rule.dose_number
    left join recorded_doses prior
      on prior.vaccine_id = rule.vaccine_id
     and prior.dose_number = rule.dose_number - 1
    where child.id = target_child_id
      and child.status = 'active'
  )
  select
    item.schedule_rule_id,
    item.vaccine_id,
    item.vaccine_name,
    item.dose_number,
    item.scheduled_date,
    case
      when item.vaccination_record_id is not null then 'completed'
      when item.dose_number > 1 and item.prior_record_id is null
        then 'notEligible'
      when item.scheduled_date < schedule_as_of then 'overdue'
      when item.scheduled_date = schedule_as_of then 'due'
      else 'upcoming'
    end as status,
    item.administered_date,
    item.vaccination_record_id
  from calculated item
  order by
    item.scheduled_date,
    case item.vaccine_id
      when 'bcg' then 1
      when 'hepatitis_b' then 2
      when 'pentavalent' then 3
      when 'opv' then 4
      when 'pcv' then 5
      when 'ipv' then 6
      when 'mmr' then 7
      else 100
    end,
    item.dose_number;
$$;

revoke all on function public.calculate_child_pnip_schedule(uuid, date)
  from public, anon, authenticated;

create or replace function public.get_child_pnip_schedule(
  target_child_id uuid,
  schedule_as_of date default current_date
)
returns table (
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
declare
  child_facility_id uuid;
begin
  select child.facility_id
    into child_facility_id
    from public.children child
   where child.id = target_child_id;

  if child_facility_id is null then
    raise exception 'Child record was not found.';
  end if;

  if not (
    public.guardian_can_access_child(target_child_id)
    or public.staff_at_facility(child_facility_id)
  ) then
    raise exception 'You do not have permission to view this child schedule.';
  end if;

  return query
  select *
    from public.calculate_child_pnip_schedule(
      target_child_id,
      schedule_as_of
    );
end;
$$;

revoke all on function public.get_child_pnip_schedule(uuid, date)
  from public, anon;
grant execute on function public.get_child_pnip_schedule(uuid, date)
  to authenticated;

create or replace function public.sync_child_reminders(target_child_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  synced_count integer := 0;
begin
  perform pg_advisory_xact_lock(hashtextextended(target_child_id::text, 0));

  insert into public.reminders (
    reminder_code,
    guardian_id,
    child_id,
    vaccine_id,
    dose_number,
    due_on,
    status,
    delivery_channel,
    is_read,
    created_at,
    updated_at
  )
  select
    coalesce(existing.reminder_code, public.live_entity_code('REM')),
    guardian.id,
    target_child_id,
    schedule.vaccine_id,
    schedule.dose_number,
    schedule.scheduled_date,
    case schedule.status
      when 'completed' then 'completed'
      when 'overdue' then 'overdue'
      when 'due' then 'due_today'
      else 'upcoming'
    end,
    'in_app',
    schedule.status = 'completed',
    now(),
    now()
  from public.calculate_child_pnip_schedule(target_child_id, current_date)
    schedule
  join public.guardian_child_links link
    on link.child_id = target_child_id
   and link.status = 'approved'
   and link.is_primary
  join public.guardians guardian
    on guardian.id = link.guardian_id
  left join public.reminders existing
    on existing.guardian_id = guardian.id
   and existing.child_id = target_child_id
   and existing.vaccine_id = schedule.vaccine_id
   and existing.dose_number = schedule.dose_number
  where schedule.status <> 'notEligible'
  on conflict (guardian_id, child_id, vaccine_id, dose_number)
  do update set
    due_on = excluded.due_on,
    status = excluded.status,
    delivery_channel = coalesce(
      public.reminders.delivery_channel,
      excluded.delivery_channel
    ),
    is_read = case
      when excluded.status = 'completed' then true
      else public.reminders.is_read
    end,
    updated_at = now();

  get diagnostics synced_count = row_count;
  return synced_count;
end;
$$;

revoke all on function public.sync_child_reminders(uuid)
  from public, anon, authenticated;
grant execute on function public.sync_child_reminders(uuid) to service_role;

-- Reconcile existing reminders immediately using the database rule table.
select public.run_advisory_background_sync();

commit;
