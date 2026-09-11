begin;

create table public.outreach_sessions (
  id uuid primary key default gen_random_uuid(),
  session_code text not null unique,
  facility_id uuid not null references public.facilities(id),
  title text not null check (length(trim(title)) between 3 and 120),
  location text not null check (length(trim(location)) between 3 and 240),
  scheduled_on date not null,
  status text not null default 'draft'
    check (status in ('draft', 'active', 'reconciliation', 'completed', 'cancelled')),
  packaging_intact boolean not null default false,
  cold_chain_verified boolean not null default false,
  vvm_status text not null default 'unknown'
    check (vvm_status in ('not_applicable', 'acceptable', 'not_acceptable', 'unknown')),
  safety_notes text,
  closure_notes text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  submitted_at timestamptz,
  completed_at timestamptz,
  completed_by uuid references public.profiles(id),
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles(id)
);

create table public.outreach_stock_allocations (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.outreach_sessions(id) on delete cascade,
  batch_id uuid not null references public.vaccine_batches(id),
  allocated_quantity integer not null check (allocated_quantity > 0),
  administered_quantity integer not null default 0 check (administered_quantity >= 0),
  wasted_quantity integer not null default 0 check (wasted_quantity >= 0),
  returned_quantity integer not null default 0 check (returned_quantity >= 0),
  quarantined_quantity integer not null default 0 check (quarantined_quantity >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (session_id, batch_id),
  check (
    administered_quantity + wasted_quantity + returned_quantity +
    quarantined_quantity <= allocated_quantity
  )
);

create table public.outreach_operations (
  operation_key uuid primary key,
  session_id uuid not null references public.outreach_sessions(id) on delete cascade,
  operation_type text not null,
  response_payload jsonb not null default '{}'::jsonb,
  performed_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.outreach_stock_transactions (
  id uuid primary key default gen_random_uuid(),
  transaction_code text not null unique,
  session_id uuid not null references public.outreach_sessions(id) on delete cascade,
  allocation_id uuid not null references public.outreach_stock_allocations(id),
  transaction_type text not null
    check (transaction_type in ('release', 'administration', 'wastage', 'return', 'quarantine')),
  quantity integer not null check (quantity > 0),
  child_id uuid references public.children(id),
  vaccination_record_id uuid references public.vaccination_records(id),
  reason text not null,
  operation_key uuid not null references public.outreach_operations(operation_key),
  performed_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create index outreach_sessions_facility_date_idx
  on public.outreach_sessions (facility_id, scheduled_on desc, created_at desc);
create index outreach_allocations_session_idx
  on public.outreach_stock_allocations (session_id, created_at);
create index outreach_transactions_session_idx
  on public.outreach_stock_transactions (session_id, created_at desc);

alter table public.inventory_transactions
  drop constraint if exists inventory_transactions_transaction_type_check;
alter table public.inventory_transactions
  add constraint inventory_transactions_transaction_type_check
  check (transaction_type in (
    'received', 'adjustment_increase', 'adjustment_decrease', 'administration',
    'wastage', 'batch_safety_review', 'outreach_release', 'outreach_return'
  ));

alter table public.vaccination_records
  add column if not exists outreach_session_id uuid
    references public.outreach_sessions(id),
  add column if not exists outreach_allocation_id uuid
    references public.outreach_stock_allocations(id);
alter table public.vaccination_records
  drop constraint if exists vaccination_records_source_check;
alter table public.vaccination_records
  add constraint vaccination_records_source_check
  check (source in ('local', 'external_referral', 'previous_record', 'outreach'));
create index vaccination_records_outreach_session_idx
  on public.vaccination_records (outreach_session_id, administered_on desc);

alter table public.outreach_sessions enable row level security;
alter table public.outreach_stock_allocations enable row level security;
alter table public.outreach_operations enable row level security;
alter table public.outreach_stock_transactions enable row level security;

create policy outreach_sessions_facility_staff
on public.outreach_sessions for select to authenticated
using (public.staff_at_facility(facility_id));
create policy outreach_sessions_facility_staff_insert
on public.outreach_sessions for insert to authenticated
with check (public.staff_at_facility(facility_id) and created_by = auth.uid());
create policy outreach_sessions_facility_staff_update
on public.outreach_sessions for update to authenticated
using (public.staff_at_facility(facility_id))
with check (public.staff_at_facility(facility_id));

create policy outreach_allocations_facility_staff
on public.outreach_stock_allocations for select to authenticated
using (exists (
  select 1 from public.outreach_sessions session
  where session.id = session_id and public.staff_at_facility(session.facility_id)
));
create policy outreach_transactions_facility_staff
on public.outreach_stock_transactions for select to authenticated
using (exists (
  select 1 from public.outreach_sessions session
  where session.id = session_id and public.staff_at_facility(session.facility_id)
));
create policy outreach_operations_facility_staff
on public.outreach_operations for select to authenticated
using (exists (
  select 1 from public.outreach_sessions session
  where session.id = session_id and public.staff_at_facility(session.facility_id)
));

grant select on public.outreach_sessions, public.outreach_stock_allocations,
  public.outreach_stock_transactions, public.outreach_operations to authenticated;

create or replace function public.create_outreach_session(
  session_title text,
  session_location text,
  session_date date,
  session_notes text default ''
)
returns public.outreach_sessions
language plpgsql security definer set search_path = public as $$
declare actor public.profiles; saved public.outreach_sessions;
begin
  select * into actor from public.profiles
  where id = auth.uid() and active and role in ('health_worker', 'administrator');
  if actor.id is null then raise exception 'Only active health workers can create outreach sessions.'; end if;
  if session_date < current_date then raise exception 'An outreach session cannot be scheduled in the past.'; end if;
  insert into public.outreach_sessions (
    session_code, facility_id, title, location, scheduled_on, safety_notes, created_by
  ) values (
    public.live_entity_code('OUT'), actor.facility_id, trim(session_title),
    trim(session_location), session_date, nullif(trim(session_notes), ''), actor.id
  ) returning * into saved;
  return saved;
end $$;

create or replace function public.release_outreach_stock(
  target_session_id uuid,
  target_batch_id uuid,
  release_quantity integer,
  request_key uuid
)
returns public.outreach_stock_allocations
language plpgsql security definer set search_path = public as $$
declare
  actor public.profiles; session_row public.outreach_sessions;
  batch_row public.vaccine_batches; allocation_row public.outreach_stock_allocations;
  inventory_balance integer; existing_payload jsonb;
begin
  select response_payload into existing_payload from public.outreach_operations
  where operation_key = request_key;
  if found then
    select * into allocation_row from public.outreach_stock_allocations
    where id = (existing_payload->>'allocation_id')::uuid;
    return allocation_row;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(request_key::text, 0));
  select response_payload into existing_payload from public.outreach_operations
  where operation_key = request_key;
  if found then
    select * into allocation_row from public.outreach_stock_allocations
    where id = (existing_payload->>'allocation_id')::uuid;
    return allocation_row;
  end if;
  select * into actor from public.profiles where id = auth.uid() and active
    and role in ('health_worker', 'administrator');
  select * into session_row from public.outreach_sessions
    where id = target_session_id for update;
  if actor.id is null or session_row.id is null or actor.facility_id <> session_row.facility_id then
    raise exception 'You do not have permission to release stock for this session.';
  end if;
  if session_row.status <> 'draft' then raise exception 'Stock can only be released while the session is in draft.'; end if;
  if release_quantity <= 0 then raise exception 'Release quantity must be greater than zero.'; end if;
  select batch.* into batch_row from public.vaccine_batches batch
  join public.vaccine_inventory inventory on inventory.id = batch.inventory_id
  where batch.id = target_batch_id and inventory.facility_id = actor.facility_id
  for update of batch;
  if batch_row.id is null then raise exception 'Vaccine batch was not found.'; end if;
  if batch_row.safety_status <> 'usable' or batch_row.expiry_date <= current_date then
    raise exception 'Only usable, unexpired vaccine stock can be released.';
  end if;
  if batch_row.quantity < release_quantity then raise exception 'The release exceeds available batch stock.'; end if;
  if exists (
    select 1 from public.vaccine_batches earlier_batch
    where earlier_batch.inventory_id = batch_row.inventory_id
      and earlier_batch.safety_status = 'usable'
      and earlier_batch.quantity > 0
      and earlier_batch.expiry_date > current_date
      and (earlier_batch.expiry_date, earlier_batch.id) <
        (batch_row.expiry_date, batch_row.id)
  ) then
    raise exception 'Release the earliest-expiring usable batch first (FEFO).';
  end if;
  select coalesce(sum(quantity), 0)::integer into inventory_balance
  from public.vaccine_batches where inventory_id = batch_row.inventory_id;
  update public.vaccine_batches set quantity = quantity - release_quantity where id = batch_row.id;
  update public.vaccine_inventory set updated_at = now() where id = batch_row.inventory_id;
  insert into public.outreach_stock_allocations (session_id, batch_id, allocated_quantity)
  values (session_row.id, batch_row.id, release_quantity)
  on conflict (session_id, batch_id) do update
    set allocated_quantity = outreach_stock_allocations.allocated_quantity + excluded.allocated_quantity,
        updated_at = now()
  returning * into allocation_row;
  insert into public.outreach_operations(operation_key, session_id, operation_type, response_payload, performed_by)
  values (request_key, session_row.id, 'release', jsonb_build_object('allocation_id', allocation_row.id), actor.id);
  insert into public.outreach_stock_transactions(
    transaction_code, session_id, allocation_id, transaction_type, quantity,
    reason, operation_key, performed_by
  ) values (
    public.live_entity_code('OTXN'), session_row.id, allocation_row.id, 'release',
    release_quantity, 'Stock released to outreach session', request_key, actor.id
  );
  insert into public.inventory_transactions(
    transaction_code, inventory_id, batch_id, transaction_type, quantity_delta,
    balance_before, balance_after, reason, reference_number, performed_by
  ) values (
    public.live_entity_code('ITXN'), batch_row.inventory_id, batch_row.id,
    'outreach_release', -release_quantity, inventory_balance,
    inventory_balance - release_quantity, 'Stock transferred to outreach session',
    session_row.session_code, actor.id
  );
  return allocation_row;
end $$;

create or replace function public.start_outreach_session(
  target_session_id uuid,
  package_ok boolean,
  cold_chain_ok boolean,
  vvm text,
  safety_remarks text default ''
)
returns public.outreach_sessions
language plpgsql security definer set search_path = public as $$
declare actor public.profiles; saved public.outreach_sessions;
begin
  select * into actor from public.profiles where id = auth.uid() and active
    and role in ('health_worker', 'administrator');
  select * into saved from public.outreach_sessions where id = target_session_id for update;
  if actor.id is null or saved.id is null or actor.facility_id <> saved.facility_id then
    raise exception 'You do not have permission to start this outreach session.';
  end if;
  if saved.status <> 'draft' then raise exception 'Only a draft outreach session can be started.'; end if;
  if saved.scheduled_on <> current_date then
    raise exception 'The outreach session can only start on its scheduled date.';
  end if;
  if not exists(select 1 from public.outreach_stock_allocations where session_id = saved.id) then
    raise exception 'Release at least one vaccine batch before starting the session.';
  end if;
  if not package_ok or not cold_chain_ok or vvm not in ('acceptable', 'not_applicable') then
    raise exception 'Required vaccine safety checks must be acceptable before starting.';
  end if;
  update public.outreach_sessions set status = 'active', packaging_intact = package_ok,
    cold_chain_verified = cold_chain_ok, vvm_status = vvm,
    safety_notes = nullif(trim(safety_remarks), ''), started_at = now()
  where id = saved.id returning * into saved;
  return saved;
end $$;

create or replace function public.record_outreach_vaccinations(
  target_session_id uuid,
  screening jsonb,
  records jsonb,
  request_key uuid
)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  actor public.profiles; session_row public.outreach_sessions;
  screening_row public.vaccination_screenings; input_row jsonb;
  allocation_row record; saved public.vaccination_records; result jsonb := '[]'::jsonb;
  existing_payload jsonb;
begin
  select response_payload into existing_payload from public.outreach_operations where operation_key = request_key;
  if found then return existing_payload; end if;
  perform pg_advisory_xact_lock(hashtextextended(request_key::text, 0));
  select response_payload into existing_payload from public.outreach_operations where operation_key = request_key;
  if found then return existing_payload; end if;
  select * into actor from public.profiles where id = auth.uid() and active
    and role in ('health_worker', 'administrator');
  select * into session_row from public.outreach_sessions where id = target_session_id for update;
  if actor.id is null or session_row.id is null or actor.facility_id <> session_row.facility_id then
    raise exception 'You do not have permission to record this outreach vaccination.';
  end if;
  if session_row.status <> 'active' then raise exception 'The outreach session must be active.'; end if;
  if jsonb_typeof(records) <> 'array' or jsonb_array_length(records) = 0 then
    raise exception 'At least one vaccine must be selected.';
  end if;
  if not public.can_access_live_child((screening->>'child_id')::uuid) then
    raise exception 'You do not have permission to vaccinate this child.';
  end if;
  insert into public.vaccination_screenings(
    screening_code, child_id, history_reviewed, current_condition_assessed,
    contraindications_reviewed, guardian_consent_confirmed, outcome, notes,
    screened_by, screened_at
  ) values (
    public.live_entity_code('SCR'), (screening->>'child_id')::uuid,
    (screening->>'history_reviewed')::boolean,
    (screening->>'current_condition_assessed')::boolean,
    (screening->>'contraindications_reviewed')::boolean,
    (screening->>'guardian_consent_confirmed')::boolean,
    screening->>'outcome', coalesce(screening->>'notes', ''), actor.id, now()
  ) returning * into screening_row;
  insert into public.outreach_operations(operation_key, session_id, operation_type, response_payload, performed_by)
  values (request_key, session_row.id, 'vaccination', '{}'::jsonb, actor.id);
  for input_row in select value from jsonb_array_elements(records)
  loop
    select allocation.id, allocation.batch_id,
      allocation.allocated_quantity - allocation.administered_quantity -
      allocation.wasted_quantity - allocation.returned_quantity -
      allocation.quarantined_quantity as available_quantity
    into allocation_row
    from public.outreach_stock_allocations allocation
    join public.vaccine_batches batch on batch.id = allocation.batch_id
    join public.vaccine_inventory inventory on inventory.id = batch.inventory_id
    where allocation.session_id = session_row.id
      and inventory.vaccine_id = input_row->>'vaccine_id'
      and allocation.allocated_quantity > allocation.administered_quantity +
        allocation.wasted_quantity + allocation.returned_quantity + allocation.quarantined_quantity
    order by batch.expiry_date, batch.id
    limit 1 for update of allocation;
    if allocation_row.id is null then
      raise exception 'Insufficient outreach stock for %', input_row->>'vaccine_id';
    end if;
    insert into public.vaccination_records(
      vaccination_code, child_id, vaccine_id, dose_number, administered_on,
      facility_id, administered_by, screening_id, source, notes, recorded_by,
      recorded_at, outreach_session_id, outreach_allocation_id
    ) values (
      public.live_entity_code('VAX'), (input_row->>'child_id')::uuid,
      input_row->>'vaccine_id', (input_row->>'dose_number')::integer,
      current_date, session_row.facility_id, actor.id, screening_row.id,
      'outreach', coalesce(input_row->>'notes', ''), actor.id, now(),
      session_row.id, allocation_row.id
    ) returning * into saved;
    update public.outreach_stock_allocations
      set administered_quantity = administered_quantity + 1, updated_at = now()
      where id = allocation_row.id;
    insert into public.outreach_stock_transactions(
      transaction_code, session_id, allocation_id, transaction_type, quantity,
      child_id, vaccination_record_id, reason, operation_key, performed_by
    ) values (
      public.live_entity_code('OTXN'), session_row.id, allocation_row.id,
      'administration', 1, saved.child_id, saved.id,
      'Vaccine administered during outreach session', request_key, actor.id
    );
    result := result || jsonb_build_array(to_jsonb(saved));
  end loop;
  update public.outreach_operations set response_payload = jsonb_build_object('records', result)
    where operation_key = request_key;
  perform public.sync_child_reminders((screening->>'child_id')::uuid);
  return jsonb_build_object('records', result);
end $$;

create or replace function public.record_outreach_stock_disposition(
  target_session_id uuid,
  target_allocation_id uuid,
  disposition text,
  disposition_quantity integer,
  disposition_reason text,
  request_key uuid
)
returns public.outreach_stock_allocations
language plpgsql security definer set search_path = public as $$
declare
  actor public.profiles; session_row public.outreach_sessions;
  allocation_row public.outreach_stock_allocations; batch_row public.vaccine_batches;
  inventory_balance integer; available_quantity integer; existing_payload jsonb;
begin
  select response_payload into existing_payload from public.outreach_operations where operation_key = request_key;
  if found then
    select * into allocation_row from public.outreach_stock_allocations
      where id = (existing_payload->>'allocation_id')::uuid;
    return allocation_row;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(request_key::text, 0));
  select response_payload into existing_payload from public.outreach_operations where operation_key = request_key;
  if found then
    select * into allocation_row from public.outreach_stock_allocations
      where id = (existing_payload->>'allocation_id')::uuid;
    return allocation_row;
  end if;
  select * into actor from public.profiles where id = auth.uid() and active
    and role in ('health_worker', 'administrator');
  select * into session_row from public.outreach_sessions where id = target_session_id for update;
  select * into allocation_row from public.outreach_stock_allocations
    where id = target_allocation_id and session_id = target_session_id for update;
  if actor.id is null or session_row.id is null or allocation_row.id is null
     or actor.facility_id <> session_row.facility_id then
    raise exception 'You do not have permission to reconcile this outreach stock.';
  end if;
  if session_row.status not in ('active', 'reconciliation') then
    raise exception 'This outreach session is not open for reconciliation.';
  end if;
  if disposition not in ('wastage', 'return', 'quarantine') then raise exception 'Unsupported stock disposition.'; end if;
  if disposition_quantity <= 0 then raise exception 'Quantity must be greater than zero.'; end if;
  available_quantity := allocation_row.allocated_quantity - allocation_row.administered_quantity -
    allocation_row.wasted_quantity - allocation_row.returned_quantity - allocation_row.quarantined_quantity;
  if disposition_quantity > available_quantity then raise exception 'The quantity exceeds remaining outreach stock.'; end if;
  select * into batch_row from public.vaccine_batches where id = allocation_row.batch_id for update;
  if disposition = 'return' and batch_row.safety_status <> 'usable' then
    raise exception 'Stock cannot return to a batch that is not currently usable.';
  end if;
  insert into public.outreach_operations(operation_key, session_id, operation_type, response_payload, performed_by)
  values (request_key, session_row.id, disposition,
    jsonb_build_object('allocation_id', allocation_row.id), actor.id);
  if disposition = 'return' then
    select coalesce(sum(quantity), 0)::integer into inventory_balance
      from public.vaccine_batches where inventory_id = batch_row.inventory_id;
    update public.vaccine_batches set quantity = quantity + disposition_quantity where id = batch_row.id;
    update public.vaccine_inventory set updated_at = now() where id = batch_row.inventory_id;
    update public.outreach_stock_allocations set returned_quantity = returned_quantity + disposition_quantity,
      updated_at = now() where id = allocation_row.id returning * into allocation_row;
    insert into public.inventory_transactions(
      transaction_code, inventory_id, batch_id, transaction_type, quantity_delta,
      balance_before, balance_after, reason, reference_number, performed_by
    ) values (
      public.live_entity_code('ITXN'), batch_row.inventory_id, batch_row.id,
      'outreach_return', disposition_quantity, inventory_balance,
      inventory_balance + disposition_quantity, trim(disposition_reason),
      session_row.session_code, actor.id
    );
  elsif disposition = 'wastage' then
    update public.outreach_stock_allocations set wasted_quantity = wasted_quantity + disposition_quantity,
      updated_at = now() where id = allocation_row.id returning * into allocation_row;
  else
    update public.outreach_stock_allocations set quarantined_quantity = quarantined_quantity + disposition_quantity,
      updated_at = now() where id = allocation_row.id returning * into allocation_row;
  end if;
  insert into public.outreach_stock_transactions(
    transaction_code, session_id, allocation_id, transaction_type, quantity,
    reason, operation_key, performed_by
  ) values (
    public.live_entity_code('OTXN'), session_row.id, allocation_row.id,
    disposition, disposition_quantity, trim(disposition_reason), request_key, actor.id
  );
  return allocation_row;
end $$;

create or replace function public.submit_outreach_session(
  target_session_id uuid,
  submission_notes text default ''
)
returns public.outreach_sessions
language plpgsql security definer set search_path = public as $$
declare actor public.profiles; saved public.outreach_sessions; unaccounted integer;
begin
  select * into actor from public.profiles where id = auth.uid() and active
    and role in ('health_worker', 'administrator');
  select * into saved from public.outreach_sessions where id = target_session_id for update;
  if actor.id is null or saved.id is null or actor.facility_id <> saved.facility_id then
    raise exception 'You do not have permission to submit this outreach session.';
  end if;
  if saved.status <> 'active' then raise exception 'Only an active outreach session can be submitted.'; end if;
  select coalesce(sum(allocated_quantity - administered_quantity - wasted_quantity -
    returned_quantity - quarantined_quantity), 0)::integer into unaccounted
  from public.outreach_stock_allocations where session_id = saved.id;
  if unaccounted <> 0 then raise exception 'All outreach doses must be administered, returned, wasted, or quarantined before submission.'; end if;
  update public.outreach_sessions set status = 'reconciliation', submitted_at = now(),
    closure_notes = nullif(trim(submission_notes), '')
  where id = saved.id returning * into saved;
  return saved;
end $$;

create or replace function public.complete_outreach_session(target_session_id uuid)
returns public.outreach_sessions
language plpgsql security definer set search_path = public as $$
declare actor public.profiles; saved public.outreach_sessions;
begin
  select * into actor from public.profiles where id = auth.uid() and active and role = 'administrator';
  select * into saved from public.outreach_sessions where id = target_session_id for update;
  if actor.id is null or saved.id is null or actor.facility_id <> saved.facility_id then
    raise exception 'Only an administrator at this facility can complete the outreach session.';
  end if;
  if saved.status <> 'reconciliation' then raise exception 'The session must be submitted for reconciliation first.'; end if;
  update public.outreach_sessions set status = 'completed', completed_at = now(), completed_by = actor.id
    where id = saved.id returning * into saved;
  return saved;
end $$;

revoke all on function public.create_outreach_session(text, text, date, text) from public, anon;
revoke all on function public.release_outreach_stock(uuid, uuid, integer, uuid) from public, anon;
revoke all on function public.start_outreach_session(uuid, boolean, boolean, text, text) from public, anon;
revoke all on function public.record_outreach_vaccinations(uuid, jsonb, jsonb, uuid) from public, anon;
revoke all on function public.record_outreach_stock_disposition(uuid, uuid, text, integer, text, uuid) from public, anon;
revoke all on function public.submit_outreach_session(uuid, text) from public, anon;
revoke all on function public.complete_outreach_session(uuid) from public, anon;
grant execute on function public.create_outreach_session(text, text, date, text) to authenticated;
grant execute on function public.release_outreach_stock(uuid, uuid, integer, uuid) to authenticated;
grant execute on function public.start_outreach_session(uuid, boolean, boolean, text, text) to authenticated;
grant execute on function public.record_outreach_vaccinations(uuid, jsonb, jsonb, uuid) to authenticated;
grant execute on function public.record_outreach_stock_disposition(uuid, uuid, text, integer, text, uuid) to authenticated;
grant execute on function public.submit_outreach_session(uuid, text) to authenticated;
grant execute on function public.complete_outreach_session(uuid) to authenticated;

commit;
