begin;

create unique index if not exists reminders_guardian_child_vaccine_dose_idx
  on public.reminders (guardian_id, child_id, vaccine_id, dose_number);

-- Keep the reminder list backed by the same schedule used by the dashboard.
-- This is intentionally idempotent: registration, approval, retries, and daily
-- refreshes all converge on the same reminder rows rather than creating copies.
create function public.sync_child_reminders(target_child_id uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare synced_count integer := 0;
begin
  perform pg_advisory_xact_lock(hashtextextended(target_child_id::text, 0));

  with definitions(vaccine_id, dose_number, offset_days, month_offset) as (
    values
      ('bcg', 1, 0, 0), ('hepatitis_b', 1, 0, 0),
      ('pentavalent', 1, 42, 0), ('pentavalent', 2, 70, 0), ('pentavalent', 3, 98, 0),
      ('opv', 1, 42, 0), ('opv', 2, 70, 0), ('opv', 3, 98, 0),
      ('pcv', 1, 42, 0), ('pcv', 2, 70, 0), ('pcv', 3, 98, 0),
      ('ipv', 1, 98, 0), ('ipv', 2, 0, 9),
      ('mmr', 1, 0, 9), ('mmr', 2, 0, 12)
  ), scheduled as (
    select d.vaccine_id, d.dose_number,
      case when d.month_offset > 0
        then (c.birth_date + make_interval(months => d.month_offset))::date
        else c.birth_date + d.offset_days
      end as base_date,
      exists(select 1 from public.vaccination_records vr
        where vr.child_id = c.id and vr.vaccine_id = d.vaccine_id
          and vr.dose_number = d.dose_number and vr.status <> 'voided') as completed,
      exists(select 1 from public.vaccination_records vr
        where vr.child_id = c.id and vr.vaccine_id = d.vaccine_id
          and vr.dose_number = d.dose_number - 1 and vr.status <> 'voided') as prior_completed,
      (select max(vr.administered_on) from public.vaccination_records vr
        where vr.child_id = c.id and vr.vaccine_id = d.vaccine_id
          and vr.dose_number = d.dose_number - 1 and vr.status <> 'voided') as prior_date,
      c.id as child_id, g.id as guardian_id
    from definitions d
    join public.children c on c.id = target_child_id
    join public.guardian_child_links l on l.child_id = c.id and l.status = 'approved' and l.is_primary
    join public.guardians g on g.id = l.guardian_id
  ), effective as (
    select s.*,
      case when s.dose_number > 1 and s.prior_date is not null
        then greatest(s.base_date,
          case when s.vaccine_id = 'ipv'
            then (s.prior_date + interval '4 months')::date
            else s.prior_date + 28
          end)
        else s.base_date
      end as due_date
    from scheduled s
  )
  insert into public.reminders(
    reminder_code, guardian_id, child_id, vaccine_id, dose_number, due_on,
    status, delivery_channel, is_read, created_at, updated_at
  )
  select
    coalesce(r.reminder_code, public.live_entity_code('REM')),
    e.guardian_id, e.child_id, e.vaccine_id, e.dose_number, e.due_date,
    case when e.completed then 'completed'
      when e.due_date < current_date then 'overdue'
      when e.due_date = current_date then 'due_today'
      else 'upcoming'
    end,
    'in_app', e.completed, now(), now()
  from effective e
  left join public.reminders r
    on r.guardian_id = e.guardian_id and r.child_id = e.child_id
   and r.vaccine_id = e.vaccine_id and r.dose_number = e.dose_number
  where (e.dose_number = 1 or e.prior_completed or e.completed)
  on conflict (guardian_id, child_id, vaccine_id, dose_number)
  do update set
    due_on = excluded.due_on,
    status = excluded.status,
    delivery_channel = coalesce(public.reminders.delivery_channel, excluded.delivery_channel),
    is_read = coalesce(public.reminders.is_read, false),
    updated_at = now();

  get diagnostics synced_count = row_count;
  return synced_count;
end $$;

revoke all on function public.sync_child_reminders(uuid) from public, anon, authenticated;
grant execute on function public.sync_child_reminders(uuid) to service_role;

create function public.sync_guardian_reminders(target_guardian_id uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare synced_count integer := 0; child_id uuid;
begin
  if not (public.owns_guardian(target_guardian_id)
    or exists(select 1 from public.guardians g where g.id = target_guardian_id
      and public.staff_at_facility(g.facility_id))) then
    raise exception 'Not authorized';
  end if;

  for child_id in
    select l.child_id
    from public.guardian_child_links l
    where l.guardian_id = target_guardian_id and l.status = 'approved'
  loop
    synced_count := synced_count + public.sync_child_reminders(child_id);
  end loop;

  return synced_count;
end $$;

revoke all on function public.sync_guardian_reminders(uuid) from public, anon, authenticated;
grant execute on function public.sync_guardian_reminders(uuid) to authenticated;
grant execute on function public.sync_guardian_reminders(uuid) to service_role;

create function public.sync_reminder_after_vaccination()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is null or new.status = 'voided' then
    return new;
  end if;

  update public.reminders
  set status = 'completed',
      updated_at = now()
  where child_id = new.child_id
    and vaccine_id = new.vaccine_id
    and dose_number = new.dose_number
    and status <> 'completed';

  return new;
end $$;

create trigger vaccination_records_sync_reminders_after_write
after insert or update of vaccine_id, dose_number, status, administered_on on public.vaccination_records
for each row execute function public.sync_reminder_after_vaccination();

create function public.guardian_links_sync_reminders_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'approved' and new.is_primary then
    perform public.sync_child_reminders(new.child_id);
  end if;
  return new;
end $$;

create trigger guardian_links_sync_reminders_after_insert
after insert on public.guardian_child_links
for each row execute function public.guardian_links_sync_reminders_trigger();

commit;
