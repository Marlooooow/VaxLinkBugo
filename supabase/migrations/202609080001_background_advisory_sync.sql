begin;

-- Synchronize one child's rule-based advisory without depending on a client
-- session. This private function is used by reminder triggers and the periodic
-- reconciliation job; the existing authenticated RPC remains the public entry
-- point used by the application.
create or replace function public.sync_child_advisory_insight(
  target_child_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  child_row record;
  overdue_count integer := 0;
  oldest_due date;
  oldest_vaccine text;
  source_ids jsonb := '[]'::jsonb;
  insight_severity text;
begin
  select c.id, c.facility_id, c.full_name
    into child_row
    from public.children c
   where c.id = target_child_id;

  if not found then
    return 0;
  end if;

  select count(*)::integer,
         min(r.due_on),
         (array_agg(r.vaccine_id order by r.due_on, r.dose_number))[1],
         coalesce(
           to_jsonb(array_agg(r.id::text order by r.due_on, r.dose_number)),
           '[]'::jsonb
         )
    into overdue_count, oldest_due, oldest_vaccine, source_ids
    from public.reminders r
   where r.child_id = target_child_id
     and r.status = 'overdue';

  if overdue_count = 0 then
    update public.advisory_insights insight
       set status = 'dismissed',
           source_snapshot = insight.source_snapshot || jsonb_build_object(
             'automatically_resolved', true,
             'resolved_at', now()
           ),
           generated_at = now()
     where insight.insight_code = 'AI-DELAY-CHILD-' || target_child_id::text
       and insight.analysis_provider = 'database-rule-engine'
       and insight.status <> 'dismissed';
    return 0;
  end if;

  insight_severity := case
    when overdue_count >= 3 then 'high'
    else 'medium'
  end;

  insert into public.advisory_insights (
    insight_code, facility_id, type, severity, title, summary, rationale,
    recommended_action, child_id, vaccine_id, source_entity_ids,
    source_snapshot, analysis_provider, analysis_version, status,
    generated_at, created_at
  ) values (
    'AI-DELAY-CHILD-' || child_row.id::text,
    child_row.facility_id,
    'delayed_vaccination',
    insight_severity,
    'Delayed vaccination follow-up',
    child_row.full_name || ' has ' || overdue_count || ' overdue vaccine dose(s).',
    'The oldest overdue PNIP reminder is dated ' || oldest_due::text || '.',
    'Review the child record and eligibility, then contact the guardian for follow-up.',
    child_row.id,
    oldest_vaccine,
    source_ids,
    jsonb_build_object(
      'overdue_count', overdue_count,
      'oldest_due_date', oldest_due,
      'days_delayed', greatest(current_date - oldest_due, 0),
      'source', 'reminders'
    ),
    'database-rule-engine',
    'phase9-child-advisory-v2-background',
    'new_insight',
    now(),
    now()
  )
  on conflict (insight_code) do update set
    facility_id = excluded.facility_id,
    severity = excluded.severity,
    summary = excluded.summary,
    rationale = excluded.rationale,
    recommended_action = excluded.recommended_action,
    child_id = excluded.child_id,
    vaccine_id = excluded.vaccine_id,
    source_entity_ids = excluded.source_entity_ids,
    source_snapshot = excluded.source_snapshot,
    analysis_provider = excluded.analysis_provider,
    analysis_version = excluded.analysis_version,
    status = case
      when public.advisory_insights.source_snapshot->>'automatically_resolved' = 'true'
        then 'new_insight'
      else public.advisory_insights.status
    end,
    reviewed_by = case
      when public.advisory_insights.source_snapshot->>'automatically_resolved' = 'true'
        then null
      else public.advisory_insights.reviewed_by
    end,
    reviewed_at = case
      when public.advisory_insights.source_snapshot->>'automatically_resolved' = 'true'
        then null
      else public.advisory_insights.reviewed_at
    end,
    generated_at = excluded.generated_at;

  return 1;
end;
$$;

revoke all on function public.sync_child_advisory_insight(uuid)
  from public, anon, authenticated;

create or replace function public.sync_facility_child_advisory_insights(
  target_facility_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  child_row record;
  active_count integer := 0;
begin
  for child_row in
    select c.id
      from public.children c
     where c.facility_id = target_facility_id
  loop
    active_count := active_count
      + public.sync_child_advisory_insight(child_row.id);
  end loop;
  return active_count;
end;
$$;

revoke all on function public.sync_facility_child_advisory_insights(uuid)
  from public, anon, authenticated;

-- Preserve the authenticated RPC used by the live Flutter repository while
-- delegating its work to the same implementation as the background process.
create or replace function public.sync_child_advisory_insights()
returns integer
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_health_worker() then
    raise exception 'Only health workers may synchronize advisory insights';
  end if;

  return public.sync_facility_child_advisory_insights(
    public.current_facility_id()
  );
end;
$$;

revoke all on function public.sync_child_advisory_insights()
  from public, anon;
grant execute on function public.sync_child_advisory_insights()
  to authenticated;

create or replace function public.sync_advisory_after_reminder_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('vaxlink.skip_advisory_trigger', true) = 'on' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    perform public.sync_child_advisory_insight(old.child_id);
    return old;
  end if;

  if tg_op = 'UPDATE' and old.child_id is distinct from new.child_id then
    perform public.sync_child_advisory_insight(old.child_id);
  end if;

  perform public.sync_child_advisory_insight(new.child_id);
  return new;
end;
$$;

drop trigger if exists reminders_sync_advisory_after_write
  on public.reminders;
create trigger reminders_sync_advisory_after_write
after insert or delete or update of child_id, vaccine_id, dose_number, due_on, status
on public.reminders
for each row execute function public.sync_advisory_after_reminder_write();

-- Recalculate reminders and advisories for every facility. Execution remains
-- private so a client cannot trigger an unrestricted facility-wide operation.
create or replace function public.run_advisory_background_sync()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  child_row record;
  active_count integer := 0;
begin
  -- sync_child_reminders can touch several dose rows for one child. Suppress
  -- the row trigger during this bulk pass and calculate that child's advisory
  -- once immediately afterward.
  perform set_config('vaxlink.skip_advisory_trigger', 'on', true);

  for child_row in select c.id from public.children c
  loop
    perform public.sync_child_reminders(child_row.id);
    active_count := active_count
      + public.sync_child_advisory_insight(child_row.id);
  end loop;

  perform set_config('vaxlink.skip_advisory_trigger', 'off', true);
  return active_count;
end;
$$;

revoke all on function public.run_advisory_background_sync()
  from public, anon, authenticated;
grant execute on function public.run_advisory_background_sync()
  to service_role;

-- Bring existing reminder and advisory rows up to date immediately when the
-- migration is applied; later changes are handled by the trigger and cron job.
select public.run_advisory_background_sync();

commit;

-- pg_cron is available on hosted Supabase projects. These guarded blocks keep
-- the migration usable in local environments where the extension is absent;
-- event-driven reminder triggers still provide immediate synchronization.
do $$
begin
  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    raise notice 'pg_cron is unavailable; reminder-triggered advisory sync remains active.';
  end;
end;
$$;

do $$
declare
  existing_job_id bigint;
begin
  if to_regnamespace('cron') is null then
    return;
  end if;

  for existing_job_id in
    select jobid from cron.job
     where jobname = 'vaxlink-advisory-reconciliation'
  loop
    perform cron.unschedule(existing_job_id);
  end loop;

  perform cron.schedule(
    'vaxlink-advisory-reconciliation',
    '17 * * * *',
    'select public.run_advisory_background_sync();'
  );
exception when others then
  raise notice 'Advisory cron schedule was not installed: %', sqlerrm;
end;
$$;
