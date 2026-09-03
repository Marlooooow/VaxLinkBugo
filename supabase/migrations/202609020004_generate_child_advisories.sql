begin;

-- Creates database-backed, child-specific advisory records from the current
-- reminder facts. The database remains authoritative for counts and dates;
-- an AI provider may later improve the wording, but does not decide eligibility.
create or replace function public.sync_child_advisory_insights()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  child_row record;
  overdue_count integer;
  oldest_due date;
  oldest_vaccine text;
  source_ids jsonb;
  synced_count integer := 0;
  insight_severity text;
begin
  if not public.is_health_worker() then
    raise exception 'Only health workers may synchronize advisory insights';
  end if;

  for child_row in
    select c.id, c.facility_id, c.full_name
    from public.children c
    where c.facility_id = public.current_facility_id()
      and exists (
        select 1
        from public.reminders r
        where r.child_id = c.id
          and r.status = 'overdue'
      )
  loop
    select count(*)::integer,
           min(r.due_on),
           (array_agg(r.vaccine_id order by r.due_on, r.dose_number))[1],
           to_jsonb(array_agg(r.id::text order by r.due_on, r.dose_number))
      into overdue_count, oldest_due, oldest_vaccine, source_ids
      from public.reminders r
     where r.child_id = child_row.id
       and r.status = 'overdue';

    insight_severity := case when overdue_count >= 3 then 'high' else 'medium' end;

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
      coalesce(source_ids, '[]'::jsonb),
      jsonb_build_object(
        'overdue_count', overdue_count,
        'oldest_due_date', oldest_due,
        'days_delayed', greatest(current_date - oldest_due, 0),
        'source', 'reminders'
      ),
      'database-rule-engine',
      'phase9-child-advisory-v1',
      'new_insight',
      now(),
      now()
    )
    on conflict (insight_code) do update set
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
      generated_at = excluded.generated_at;

    synced_count := synced_count + 1;
  end loop;

  return synced_count;
end;
$$;

revoke all on function public.sync_child_advisory_insights() from public, anon;
grant execute on function public.sync_child_advisory_insights() to authenticated;

commit;
