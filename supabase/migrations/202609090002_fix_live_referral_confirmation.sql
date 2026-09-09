begin;

alter table public.external_vaccination_visits
  add column if not exists verification_method text;

create or replace function public.verify_live_referral_group(
  target_group_id uuid,
  supplied_token text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  group_record public.referral_groups%rowtype;
  actor_facility uuid;
  token_valid boolean := false;
begin
  select profile.facility_id into actor_facility
    from public.profiles profile
   where profile.id = auth.uid()
     and profile.active
     and profile.role in ('health_worker', 'administrator');
  if actor_facility is null then
    raise exception 'Only active health-center staff can verify referrals.';
  end if;

  select * into group_record
    from public.referral_groups
   where id = target_group_id;
  if not found then return 'not_found'; end if;

  token_valid := nullif(trim(supplied_token), '') is not null
    and group_record.qr_token_hash = encode(
      extensions.digest(trim(supplied_token), 'sha256'), 'hex'
    );

  if nullif(trim(supplied_token), '') is not null and not token_valid then
    return 'invalid_token';
  end if;
  if actor_facility <> group_record.originating_facility_id and not token_valid then
    return 'invalid_token';
  end if;
  if group_record.status = 'completed' then return 'completed'; end if;
  if group_record.status in ('cancelled', 'expired')
     or group_record.expires_on < current_date then
    return 'cancelled';
  end if;
  return 'valid';
end;
$$;

create or replace function public.get_verified_referral_group(
  target_group_id uuid,
  supplied_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  verification_status text;
  group_payload jsonb;
begin
  verification_status := public.verify_live_referral_group(
    target_group_id, supplied_token
  );
  if verification_status in ('not_found', 'invalid_token') then
    return jsonb_build_object('status', verification_status);
  end if;

  select jsonb_build_object(
    'referral_group_id', referral_group.id,
    'referral_group_code', referral_group.referral_group_code,
    'verification_token', '',
    'child_id', child.id,
    'child_name', child.full_name,
    'originating_facility', facility.name,
    'issued_at', referral_group.created_at,
    'referrals', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', referral_item.id,
          'referral_code', referral_item.referral_code,
          'referral_group_id', referral_group.id,
          'referral_group_code', referral_group.referral_group_code,
          'child_id', child.id,
          'child_name', child.full_name,
          'vaccine_id', referral_item.vaccine_id,
          'vaccine_name', vaccine.name,
          'dose_number', referral_item.dose_number,
          'scheduled_due_date', coalesce(
            referral_item.scheduled_due_date, referral_group.issued_on
          ),
          'originating_facility', facility.name,
          'status', case when referral_item.status = 'completed'
            then 'Completed' else 'Pending' end,
          'created_at', referral_group.created_at,
          'completed_at', referral_item.completed_at,
          'verification_token', ''
        ) order by referral_item.referral_code
      )
      from public.referral_items referral_item
      join public.vaccine_definitions vaccine
        on vaccine.id = referral_item.vaccine_id
      where referral_item.referral_group_id = referral_group.id
    ), '[]'::jsonb)
  ) into group_payload
  from public.referral_groups referral_group
  join public.children child on child.id = referral_group.child_id
  join public.facilities facility
    on facility.id = referral_group.originating_facility_id
  where referral_group.id = target_group_id;

  return jsonb_build_object(
    'status', verification_status,
    'group', group_payload
  );
end;
$$;

drop function if exists public.record_external_vaccinations(
  uuid, uuid[], date, text, text, text
);

create function public.record_external_vaccinations(
  target_group_id uuid,
  target_item_ids uuid[],
  administered_on_date date,
  receiving_facility text,
  receiving_worker text,
  visit_notes text default '',
  supplied_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  group_record public.referral_groups%rowtype;
  item_record public.referral_items%rowtype;
  actor_facility uuid;
  token_valid boolean := false;
  visit_id uuid := extensions.gen_random_uuid();
  visit_code text := 'EV-' || to_char(current_date, 'YYYY') || '-' ||
    lpad(nextval('public.entity_code_seq')::text, 6, '0');
  item_id uuid;
  vaccination_record_id uuid;
  record_code text;
  result jsonb := '[]'::jsonb;
begin
  select profile.facility_id into actor_facility
    from public.profiles profile
   where profile.id = auth.uid()
     and profile.active
     and profile.role in ('health_worker', 'administrator');
  if actor_facility is null then
    raise exception 'Only active health-center staff can complete referrals.';
  end if;

  select * into group_record
    from public.referral_groups
   where id = target_group_id
   for update;
  if not found then raise exception 'Referral group was not found.'; end if;

  token_valid := nullif(trim(supplied_token), '') is not null
    and group_record.qr_token_hash = encode(
      extensions.digest(trim(supplied_token), 'sha256'), 'hex'
    );
  if actor_facility <> group_record.originating_facility_id and not token_valid then
    raise exception 'Scan and verify the referral QR before recording this visit.';
  end if;
  if nullif(trim(supplied_token), '') is not null and not token_valid then
    raise exception 'The referral QR verification code is invalid.';
  end if;
  if group_record.status in ('completed', 'cancelled', 'expired')
     or group_record.expires_on < current_date then
    raise exception 'This referral is no longer available for recording.';
  end if;
  if coalesce(array_length(target_item_ids, 1), 0) = 0 then
    raise exception 'Select at least one referral item.';
  end if;
  if administered_on_date is null
     or administered_on_date < group_record.issued_on
     or administered_on_date > current_date then
    raise exception 'The administration date must be between the referral date and today.';
  end if;
  if nullif(trim(receiving_facility), '') is null
     or nullif(trim(receiving_worker), '') is null then
    raise exception 'Enter the administering facility and health worker.';
  end if;

  insert into public.external_vaccination_visits (
    id, visit_code, referral_group_id, administered_on,
    administering_facility, health_worker_name, notes, verified_by,
    verification_method
  ) values (
    visit_id, visit_code, group_record.id, administered_on_date,
    trim(receiving_facility), trim(receiving_worker),
    nullif(trim(visit_notes), ''), auth.uid(),
    case when token_valid then 'referral_qr' else 'manual_referral_review' end
  );

  foreach item_id in array target_item_ids loop
    select * into item_record
      from public.referral_items
     where id = item_id
       and referral_group_id = group_record.id
     for update;
    if not found then raise exception 'Referral item was not found.'; end if;
    if item_record.status <> 'pending' then
      raise exception 'A selected referral item is already completed.';
    end if;

    record_code := 'VR-' || to_char(current_date, 'YYYY') || '-' ||
      lpad(nextval('public.entity_code_seq')::text, 6, '0');
    insert into public.vaccination_records (
      vaccination_code, child_id, vaccine_id, dose_number, administered_on,
      facility_id, external_facility_name, administered_by,
      external_health_worker_name, referral_item_id, external_visit_id,
      evidence_type, source, status, notes, recorded_by, recorded_at
    ) values (
      record_code, group_record.child_id, item_record.vaccine_id,
      item_record.dose_number, administered_on_date, actor_facility,
      trim(receiving_facility), auth.uid(), trim(receiving_worker),
      item_record.id, visit_id, 'referral_qr', 'external_referral', 'recorded',
      nullif(trim(visit_notes), ''), auth.uid(), now()
    ) returning id into vaccination_record_id;

    insert into public.external_visit_items (
      visit_id, referral_item_id, vaccination_record_id
    ) values (visit_id, item_record.id, vaccination_record_id);

    update public.referral_items
       set status = 'completed', completed_at = now()
     where id = item_record.id;

    result := result || jsonb_build_array(jsonb_build_object(
      'id', item_record.id,
      'referral_code', item_record.referral_code,
      'vaccination_record_id', vaccination_record_id,
      'status', 'Completed',
      'completed_at', now()
    ));
  end loop;

  update public.referral_groups referral_group
     set status = case when not exists (
       select 1 from public.referral_items referral_item
        where referral_item.referral_group_id = referral_group.id
          and referral_item.status = 'pending'
     ) then 'completed' else 'partial' end
   where referral_group.id = group_record.id;

  return jsonb_build_object(
    'visit_id', visit_id,
    'visit_code', visit_code,
    'items', result
  );
end;
$$;

revoke all on function public.verify_live_referral_group(uuid, text)
  from public, anon;
grant execute on function public.verify_live_referral_group(uuid, text)
  to authenticated;

revoke all on function public.get_verified_referral_group(uuid, text)
  from public, anon;
grant execute on function public.get_verified_referral_group(uuid, text)
  to authenticated;

revoke all on function public.record_external_vaccinations(
  uuid, uuid[], date, text, text, text, text
) from public, anon;
grant execute on function public.record_external_vaccinations(
  uuid, uuid[], date, text, text, text, text
) to authenticated;

commit;
