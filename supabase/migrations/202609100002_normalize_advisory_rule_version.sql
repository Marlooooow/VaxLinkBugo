begin;

-- Replace the development-phase label with a stable rule identifier in
-- existing database-generated child advisory records.
update public.advisory_insights
   set analysis_version = 'child-overdue-advisory-v2'
 where analysis_provider = 'database-rule-engine'
   and analysis_version in (
     'phase9-child-advisory-v1',
     'phase9-child-advisory-v2-background',
     'child-advisory-v2-background'
   );

-- Keep future background-generated advisories on the same stable identifier.
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
    'child-overdue-advisory-v2',
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

commit;
