begin;

create or replace function public.create_live_appointment(
  target_guardian_id uuid, target_child_id uuid, target_vaccine_id text,
  target_dose_number integer, target_due_date date, target_scheduled_for timestamptz,
  target_source text, target_reason text, target_reminder_id uuid default null,
  target_status text default 'scheduled'
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  child_record public.children%rowtype;
  appointment_id uuid := extensions.gen_random_uuid();
begin
  select * into child_record from public.children where id = target_child_id and status = 'active';
  if child_record.id is null then raise exception 'Child was not found.'; end if;
  if not (public.staff_at_facility(child_record.facility_id) or public.owns_guardian(target_guardian_id)) then
    raise exception 'You do not have permission to schedule this appointment.';
  end if;
  if target_status not in ('scheduled', 'waitlisted') then raise exception 'Unsupported appointment status.'; end if;
  insert into public.appointments (
    id, appointment_code, guardian_id, reminder_id, child_id, vaccine_id, dose_number,
    facility_id, scheduled_for, pnip_due_date, status, source, reason, created_by
  ) values (
    appointment_id, 'APT-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 6, '0'),
    target_guardian_id, target_reminder_id, target_child_id, target_vaccine_id, target_dose_number,
    child_record.facility_id, target_scheduled_for, target_due_date, target_status, target_source,
    nullif(trim(target_reason), ''), auth.uid()
  );
  return appointment_id;
end;
$$;

create or replace function public.reschedule_live_appointment(
  target_appointment_id uuid, target_scheduled_for timestamptz, target_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  original public.appointments%rowtype;
  replacement_id uuid := extensions.gen_random_uuid();
begin
  select * into original from public.appointments where id = target_appointment_id for update;
  if original.id is null then raise exception 'Appointment was not found.'; end if;
  if not public.staff_at_facility(original.facility_id) then raise exception 'Only health-center staff can reschedule appointments.'; end if;
  if original.status not in ('scheduled', 'confirmed', 'waitlisted') then raise exception 'This appointment can no longer be rescheduled.'; end if;
  update public.appointments set status = 'rescheduled' where id = original.id;
  insert into public.appointments (
    id, appointment_code, guardian_id, reminder_id, child_id, vaccine_id, dose_number,
    facility_id, scheduled_for, pnip_due_date, priority, status, source, reason,
    previous_appointment_id, created_by
  ) values (
    replacement_id, 'APT-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 6, '0'),
    original.guardian_id, original.reminder_id, original.child_id, original.vaccine_id, original.dose_number,
    original.facility_id, target_scheduled_for, original.pnip_due_date, original.priority, 'scheduled',
    original.source, nullif(trim(target_reason), ''), original.id, auth.uid()
  );
  return replacement_id;
end;
$$;

create or replace function public.update_live_appointment_status(target_appointment_id uuid, target_status text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare a public.appointments%rowtype;
begin
  select * into a from public.appointments where id = target_appointment_id for update;
  if a.id is null then raise exception 'Appointment was not found.'; end if;
  if not public.staff_at_facility(a.facility_id) then raise exception 'Only health-center staff can update this appointment.'; end if;
  if target_status not in ('scheduled','confirmed','checked_in','completed','cancelled','no_show','waitlisted','referred') then raise exception 'Unsupported appointment status.'; end if;
  update public.appointments set status = target_status where id = a.id;
  return a.id;
end;
$$;

create or replace function public.respond_to_live_appointment_offer(target_offer_id uuid, accept_offer boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare offer public.appointment_offers%rowtype; appointment public.appointments%rowtype; replacement_id uuid;
begin
  select * into offer from public.appointment_offers where id = target_offer_id for update;
  if offer.id is null then raise exception 'Earlier appointment offer was not found.'; end if;
  select * into appointment from public.appointments where id = offer.appointment_id for update;
  if not (public.owns_guardian(appointment.guardian_id) or public.staff_at_facility(appointment.facility_id)) then raise exception 'You do not have permission to respond to this offer.'; end if;
  if offer.status <> 'pending' or offer.expires_at <= now() then raise exception 'This earlier appointment offer is no longer active.'; end if;
  if not accept_offer then
    update public.appointment_offers set status = 'declined', responded_at = now() where id = offer.id;
    return null;
  end if;
  replacement_id := public.reschedule_live_appointment(appointment.id, offer.offered_for, 'Guardian accepted an earlier appointment offer.');
  update public.appointment_offers set status = 'accepted', responded_at = now() where id = offer.id;
  return replacement_id;
end;
$$;

revoke all on function public.create_live_appointment(uuid,uuid,text,integer,date,timestamptz,text,text,uuid,text) from public, anon;
revoke all on function public.reschedule_live_appointment(uuid,timestamptz,text) from public, anon;
revoke all on function public.update_live_appointment_status(uuid,text) from public, anon;
revoke all on function public.respond_to_live_appointment_offer(uuid,boolean) from public, anon;
grant execute on function public.create_live_appointment(uuid,uuid,text,integer,date,timestamptz,text,text,uuid,text) to authenticated;
grant execute on function public.reschedule_live_appointment(uuid,timestamptz,text) to authenticated;
grant execute on function public.update_live_appointment_status(uuid,text) to authenticated;
grant execute on function public.respond_to_live_appointment_offer(uuid,boolean) to authenticated;
commit;
