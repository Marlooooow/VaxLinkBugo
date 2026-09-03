-- VaxLink Bugo production foundation.
-- Apply with the Supabase CLI or SQL editor; never place a service-role key in the app.

create extension if not exists pgcrypto;

create table public.facilities (
  id uuid primary key default gen_random_uuid(),
  facility_code text not null unique,
  name text not null,
  barangay text not null,
  city text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  facility_id uuid references public.facilities(id),
  username text not null unique,
  full_name text not null,
  role text not null check (role in ('guardian', 'health_worker', 'administrator')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.guardians (
  id uuid primary key default gen_random_uuid(),
  guardian_code text not null unique,
  profile_id uuid unique references public.profiles(id),
  registered_by uuid references public.profiles(id),
  facility_id uuid not null references public.facilities(id),
  full_name text not null,
  sex text not null check (sex in ('male', 'female')),
  birth_date date,
  phone text,
  email text,
  address text,
  access_status text not null default 'offline' check (
    access_status in ('offline', 'invitation_pending', 'active', 'disabled')
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.children (
  id uuid primary key default gen_random_uuid(),
  child_code text not null unique,
  facility_id uuid not null references public.facilities(id),
  registered_by uuid references public.profiles(id),
  full_name text not null,
  sex text not null check (sex in ('male', 'female')),
  birth_date date not null,
  birth_place text,
  address text,
  status text not null default 'active' check (status in ('active', 'inactive', 'deceased')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.guardian_child_links (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references public.guardians(id) on delete cascade,
  child_id uuid not null references public.children(id) on delete cascade,
  relationship text not null check (relationship in (
    'mother', 'father', 'grandmother', 'grandfather', 'aunt', 'uncle',
    'sibling', 'foster_guardian', 'legal_guardian', 'other'
  )),
  is_primary boolean not null default false,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'revoked')),
  requested_by uuid references public.profiles(id),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (guardian_id, child_id)
);

create table public.guardian_invitations (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references public.guardians(id) on delete cascade,
  activation_code_hash text not null unique,
  expires_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending', 'used', 'expired', 'revoked')),
  issued_by uuid not null references public.profiles(id),
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.child_link_requests (
  id uuid primary key default gen_random_uuid(),
  request_code text not null unique,
  guardian_id uuid not null references public.guardians(id),
  child_name text not null,
  birth_date date not null,
  sex text not null check (sex in ('male', 'female')),
  relationship text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'merged')),
  linked_child_id uuid references public.children(id),
  reviewed_by uuid references public.profiles(id),
  review_notes text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.guardian_corrections (
  id uuid primary key default gen_random_uuid(),
  correction_code text not null unique,
  guardian_id uuid not null references public.guardians(id),
  previous_values jsonb not null,
  updated_values jsonb not null,
  reason text not null,
  corrected_by uuid not null references public.profiles(id),
  corrected_at timestamptz not null default now()
);

create table public.child_corrections (
  id uuid primary key default gen_random_uuid(),
  correction_code text not null unique,
  child_id uuid not null references public.children(id),
  previous_values jsonb not null,
  updated_values jsonb not null,
  reason text not null,
  corrected_by uuid not null references public.profiles(id),
  corrected_at timestamptz not null default now()
);

create table public.vaccine_definitions (
  id text primary key,
  vaccine_code text not null unique,
  name text not null,
  disease_prevented text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.pnip_schedule_rules (
  id uuid primary key default gen_random_uuid(),
  vaccine_id text not null references public.vaccine_definitions(id),
  dose_number integer not null check (dose_number > 0),
  minimum_age_days integer not null check (minimum_age_days >= 0),
  recommended_age_days integer not null check (recommended_age_days >= minimum_age_days),
  minimum_interval_days integer check (minimum_interval_days is null or minimum_interval_days >= 0),
  catch_up_allowed boolean not null default true,
  effective_from date not null,
  effective_to date,
  source_reference text not null,
  active boolean not null default true,
  unique (vaccine_id, dose_number, effective_from)
);

create table public.vaccination_records (
  id uuid primary key default gen_random_uuid(),
  vaccination_code text not null unique,
  child_id uuid not null references public.children(id),
  vaccine_id text not null references public.vaccine_definitions(id),
  schedule_rule_id uuid references public.pnip_schedule_rules(id),
  dose_number integer not null check (dose_number > 0),
  administered_on date not null,
  facility_id uuid references public.facilities(id),
  external_facility_name text,
  administered_by uuid references public.profiles(id),
  external_health_worker_name text,
  referral_item_id uuid,
  external_visit_id uuid,
  screening_id uuid,
  evidence_type text,
  source text not null check (source in ('local', 'external_referral', 'previous_record')),
  status text not null default 'recorded' check (status in ('recorded', 'corrected', 'voided')),
  notes text,
  recorded_by uuid not null references public.profiles(id),
  recorded_at timestamptz not null default now(),
  corrected_at timestamptz,
  correction_reason text,
  unique (child_id, vaccine_id, dose_number)
);

create table public.vaccination_screenings (
  id uuid primary key default gen_random_uuid(),
  screening_code text not null unique,
  child_id uuid not null references public.children(id),
  history_reviewed boolean not null,
  current_condition_assessed boolean not null,
  contraindications_reviewed boolean not null,
  guardian_consent_confirmed boolean not null,
  outcome text not null check (outcome in ('cleared', 'deferred', 'referred')),
  notes text,
  screened_by uuid not null references public.profiles(id),
  screened_at timestamptz not null default now()
);

create table public.first_visit_reviews (
  id uuid primary key default gen_random_uuid(),
  review_code text not null unique,
  child_id uuid not null unique references public.children(id),
  has_documented_previous_vaccinations boolean not null,
  reviewed_by uuid not null references public.profiles(id),
  reviewed_at timestamptz not null default now()
);

create table public.referral_groups (
  id uuid primary key default gen_random_uuid(),
  referral_group_code text not null unique,
  child_id uuid not null references public.children(id),
  originating_facility_id uuid not null references public.facilities(id),
  issued_by uuid not null references public.profiles(id),
  issued_on date not null,
  expires_on date,
  status text not null default 'pending' check (status in ('pending', 'partial', 'completed', 'cancelled', 'expired')),
  qr_token_hash text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.referral_items (
  id uuid primary key default gen_random_uuid(),
  referral_code text not null unique,
  referral_group_id uuid not null references public.referral_groups(id) on delete cascade,
  vaccine_id text not null references public.vaccine_definitions(id),
  dose_number integer not null check (dose_number > 0),
  status text not null default 'pending' check (status in ('pending', 'completed', 'cancelled')),
  completed_at timestamptz,
  unique (referral_group_id, vaccine_id, dose_number)
);

create table public.external_vaccination_visits (
  id uuid primary key default gen_random_uuid(),
  referral_group_id uuid not null references public.referral_groups(id),
  administered_on date not null,
  administering_facility text not null,
  health_worker_name text not null,
  notes text,
  verified_by uuid not null references public.profiles(id),
  verified_at timestamptz not null default now(),
  correction_reason text,
  corrected_at timestamptz
);

create table public.external_visit_items (
  visit_id uuid not null references public.external_vaccination_visits(id) on delete cascade,
  referral_item_id uuid not null references public.referral_items(id),
  vaccination_record_id uuid unique references public.vaccination_records(id),
  primary key (visit_id, referral_item_id)
);

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  appointment_code text not null unique,
  guardian_id uuid not null references public.guardians(id),
  reminder_id uuid,
  child_id uuid not null references public.children(id),
  vaccine_id text not null references public.vaccine_definitions(id),
  dose_number integer not null check (dose_number > 0),
  facility_id uuid not null references public.facilities(id),
  scheduled_for timestamptz not null,
  pnip_due_date date not null,
  priority text not null default 'routine' check (priority in ('routine', 'catch_up', 'clinical_priority')),
  status text not null default 'scheduled' check (
    status in ('scheduled', 'confirmed', 'checked_in', 'completed', 'cancelled', 'no_show', 'rescheduled', 'waitlisted', 'referred')
  ),
  source text not null check (source in ('pnip_reminder', 'stock_deferral', 'health_worker', 'guardian_request')),
  reason text,
  previous_appointment_id uuid references public.appointments(id),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.appointment_offers (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  offer_code text not null unique,
  offered_for timestamptz not null,
  expires_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired', 'withdrawn')),
  responded_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.reminders (
  id uuid primary key default gen_random_uuid(),
  reminder_code text not null unique,
  guardian_id uuid not null references public.guardians(id),
  child_id uuid not null references public.children(id),
  appointment_id uuid references public.appointments(id),
  vaccine_id text not null references public.vaccine_definitions(id),
  dose_number integer not null check (dose_number > 0),
  due_on date not null,
  status text not null check (status in ('upcoming', 'due_today', 'overdue', 'completed', 'dismissed')),
  delivery_channel text not null default 'in_app' check (delivery_channel in ('in_app', 'sms', 'email', 'printed_follow_up')),
  is_read boolean not null default false,
  last_contacted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.reminder_preferences (
  guardian_id uuid primary key references public.guardians(id) on delete cascade,
  in_app_enabled boolean not null default true,
  sms_enabled boolean not null default false,
  email_enabled boolean not null default false,
  advance_notice_days integer not null default 3 check (advance_notice_days between 0 and 30),
  updated_at timestamptz not null default now()
);

create table public.reminder_follow_ups (
  id uuid primary key default gen_random_uuid(),
  follow_up_code text not null unique,
  reminder_id uuid not null references public.reminders(id),
  child_id uuid not null references public.children(id),
  action text not null check (action in ('mock_sms', 'assign', 'phone_call', 'printed_list', 'home_visit')),
  outcome text not null check (outcome in (
    'reminder_sent', 'assigned', 'contacted', 'no_answer', 'invalid_contact',
    'visit_scheduled', 'declined', 'home_visit_required', 'printed'
  )),
  assigned_to uuid references public.profiles(id),
  notes text,
  performed_by uuid not null references public.profiles(id),
  performed_at timestamptz not null default now()
);

create table public.advisory_insights (
  id uuid primary key default gen_random_uuid(),
  insight_code text not null unique,
  facility_id uuid not null references public.facilities(id),
  type text not null check (type in ('delayed_vaccination', 'stock_risk', 'waitlist_pressure')),
  severity text not null check (severity in ('low', 'medium', 'high')),
  title text not null,
  summary text not null,
  rationale text not null,
  recommended_action text not null,
  child_id uuid references public.children(id),
  vaccine_id text references public.vaccine_definitions(id),
  source_entity_ids jsonb not null default '[]'::jsonb,
  source_snapshot jsonb not null default '{}'::jsonb,
  analysis_provider text not null,
  analysis_version text not null,
  status text not null default 'new_insight' check (status in ('new_insight', 'reviewed', 'actioned', 'dismissed')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  generated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.cold_chain_checks (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities(id),
  status text not null check (status in ('acceptable', 'attention_required', 'not_checked')),
  notes text,
  checked_by uuid not null references public.profiles(id),
  checked_at timestamptz not null default now()
);

create table public.vaccine_inventory (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities(id),
  vaccine_id text not null references public.vaccine_definitions(id),
  reorder_level integer not null default 0 check (reorder_level >= 0),
  updated_at timestamptz not null default now(),
  unique (facility_id, vaccine_id)
);

create table public.vaccine_batches (
  id uuid primary key default gen_random_uuid(),
  inventory_id uuid not null references public.vaccine_inventory(id) on delete cascade,
  lot_number text not null,
  batch_code text not null unique,
  expiry_date date not null,
  quantity_received integer not null check (quantity_received > 0),
  quantity integer not null check (quantity >= 0),
  manufacturer text,
  delivery_reference text,
  received_by uuid not null references public.profiles(id),
  packaging_intact boolean not null,
  cold_chain_verified boolean not null,
  vvm_status text not null check (vvm_status in ('not_applicable', 'acceptable', 'not_acceptable', 'unknown')),
  safety_status text not null default 'quarantined' check (safety_status in ('usable', 'quarantined', 'discarded')),
  safety_notes text,
  safety_reviewed_at timestamptz not null default now(),
  safety_reviewed_by uuid not null references public.profiles(id),
  received_at timestamptz not null default now(),
  unique (inventory_id, lot_number)
);

create table public.inventory_transactions (
  id uuid primary key default gen_random_uuid(),
  transaction_code text not null unique,
  inventory_id uuid not null references public.vaccine_inventory(id),
  batch_id uuid references public.vaccine_batches(id),
  transaction_type text not null check (transaction_type in ('received', 'adjustment_increase', 'adjustment_decrease', 'administration', 'wastage', 'batch_safety_review')),
  quantity_delta integer not null check (quantity_delta <> 0),
  balance_before integer not null check (balance_before >= 0),
  balance_after integer not null check (balance_after >= 0),
  reason text not null,
  reference_number text,
  performed_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.vaccination_records
  add constraint vaccination_records_referral_item_fk
  foreign key (referral_item_id) references public.referral_items(id),
  add constraint vaccination_records_external_visit_fk
  foreign key (external_visit_id) references public.external_vaccination_visits(id),
  add constraint vaccination_records_screening_fk
  foreign key (screening_id) references public.vaccination_screenings(id);

alter table public.appointments
  add constraint appointments_reminder_fk
  foreign key (reminder_id) references public.reminders(id);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  entity_type text not null,
  entity_id text not null,
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now()
);

create index vaccination_records_child_idx on public.vaccination_records(child_id, administered_on desc);
create index referral_groups_child_idx on public.referral_groups(child_id, issued_on desc);
create index appointments_child_idx on public.appointments(child_id, scheduled_for);
create index reminders_status_due_idx on public.reminders(status, due_on);
create index inventory_transactions_inventory_idx on public.inventory_transactions(inventory_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger facilities_updated_at before update on public.facilities
for each row execute function public.set_updated_at();
create trigger profiles_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger guardians_updated_at before update on public.guardians
for each row execute function public.set_updated_at();
create trigger children_updated_at before update on public.children
for each row execute function public.set_updated_at();
create trigger referral_groups_updated_at before update on public.referral_groups
for each row execute function public.set_updated_at();
create trigger appointments_updated_at before update on public.appointments
for each row execute function public.set_updated_at();
create trigger reminders_updated_at before update on public.reminders
for each row execute function public.set_updated_at();

create or replace function public.is_health_worker()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('health_worker', 'administrator') and active
  );
$$;

create or replace function public.guardian_can_access_child(target_child uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.guardians g
    join public.guardian_child_links l on l.guardian_id = g.id
    where g.profile_id = auth.uid()
      and l.child_id = target_child
      and l.status = 'approved'
  );
$$;

create or replace function public.activate_guardian_profile(
  invitation_id uuid,
  auth_user_id uuid,
  requested_username text
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  invitation_record public.guardian_invitations%rowtype;
  guardian_record public.guardians%rowtype;
begin
  select * into invitation_record
  from public.guardian_invitations
  where id = invitation_id
  for update;

  if invitation_record.id is null
     or invitation_record.status <> 'pending'
     or invitation_record.expires_at <= now() then
    raise exception 'Invitation is no longer available.';
  end if;

  select * into guardian_record
  from public.guardians
  where id = invitation_record.guardian_id
  for update;

  if guardian_record.id is null or guardian_record.profile_id is not null then
    raise exception 'Guardian access is already linked.';
  end if;

  insert into public.profiles (id, facility_id, username, full_name, role, active)
  values (
    auth_user_id,
    guardian_record.facility_id,
    lower(trim(requested_username)),
    guardian_record.full_name,
    'guardian',
    true
  );

  update public.guardians
  set profile_id = auth_user_id, access_status = 'active'
  where id = guardian_record.id;

  update public.guardian_invitations
  set status = 'used', used_at = now()
  where id = invitation_record.id;
end;
$$;

revoke all on function public.activate_guardian_profile(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.activate_guardian_profile(uuid, uuid, text) to service_role;

create sequence public.entity_code_seq;
grant usage, select on sequence public.entity_code_seq to authenticated;

create or replace function public.record_inventory_movement(
  target_batch_id uuid,
  movement_type text,
  movement_quantity integer,
  movement_reason text,
  movement_reference text default null
)
returns public.inventory_transactions
language plpgsql security invoker set search_path = '' as $$
declare
  batch_record public.vaccine_batches%rowtype;
  inventory_record public.vaccine_inventory%rowtype;
  previous_balance integer;
  next_batch_balance integer;
  next_total_balance integer;
  transaction_record public.inventory_transactions%rowtype;
begin
  if movement_quantity = 0 then
    raise exception 'Quantity must be a non-zero whole number.';
  end if;
  if movement_type not in ('adjustment_increase', 'adjustment_decrease', 'administration', 'wastage') then
    raise exception 'Unsupported stock movement type.';
  end if;
  if movement_type in ('adjustment_decrease', 'administration', 'wastage') and movement_quantity > 0 then
    movement_quantity := -movement_quantity;
  end if;

  select * into batch_record from public.vaccine_batches
  where id = target_batch_id for update;
  if batch_record.id is null then raise exception 'Vaccine batch was not found.'; end if;

  select * into inventory_record from public.vaccine_inventory
  where id = batch_record.inventory_id for update;

  select coalesce(sum(quantity), 0)::integer into previous_balance
  from public.vaccine_batches where inventory_id = inventory_record.id;

  next_batch_balance := batch_record.quantity + movement_quantity;
  next_total_balance := previous_balance + movement_quantity;
  if next_batch_balance < 0 or next_total_balance < 0 then
    raise exception 'The adjustment exceeds the available stock.';
  end if;

  update public.vaccine_batches set quantity = next_batch_balance
  where id = batch_record.id;
  update public.vaccine_inventory set updated_at = now()
  where id = inventory_record.id;

  insert into public.inventory_transactions (
    transaction_code, inventory_id, batch_id, transaction_type,
    quantity_delta, balance_before, balance_after, reason,
    reference_number, performed_by
  ) values (
    'ITXN-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 7, '0'),
    inventory_record.id, batch_record.id, movement_type,
    movement_quantity, previous_balance, next_total_balance,
    trim(movement_reason), nullif(trim(movement_reference), ''), auth.uid()
  ) returning * into transaction_record;

  return transaction_record;
end;
$$;

create or replace function public.receive_vaccine_stock(
  target_inventory_id uuid,
  lot text,
  manufacturer_name text,
  expiry date,
  received_quantity integer,
  delivery_ref text,
  package_ok boolean,
  cold_chain_ok boolean,
  vvm text,
  review_notes text
)
returns public.inventory_transactions
language plpgsql security invoker set search_path = '' as $$
declare
  inventory_record public.vaccine_inventory%rowtype;
  batch_record public.vaccine_batches%rowtype;
  previous_balance integer;
  transaction_record public.inventory_transactions%rowtype;
  safety text;
begin
  if received_quantity <= 0 then raise exception 'Quantity must be greater than zero.'; end if;
  if trim(lot) = '' or expiry is null or trim(delivery_ref) = '' then
    raise exception 'Lot number, expiry date, and delivery reference are required.';
  end if;
  if expiry <= current_date then raise exception 'Expiry date must be in the future.'; end if;

  select * into inventory_record from public.vaccine_inventory
  where id = target_inventory_id for update;
  if inventory_record.id is null then raise exception 'Inventory item was not found.'; end if;
  select coalesce(sum(quantity), 0)::integer into previous_balance
  from public.vaccine_batches where inventory_id = inventory_record.id;
  safety := case when package_ok and cold_chain_ok and vvm <> 'not_acceptable' then 'usable' else 'quarantined' end;

  insert into public.vaccine_batches (
    inventory_id, lot_number, batch_code, expiry_date, quantity_received,
    quantity, manufacturer, delivery_reference, received_by, packaging_intact,
    cold_chain_verified, vvm_status, safety_status, safety_notes,
    safety_reviewed_by
  ) values (
    inventory_record.id, trim(lot),
    'VBAT-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 7, '0'),
    expiry, received_quantity, received_quantity, trim(manufacturer_name),
    trim(delivery_ref), auth.uid(), package_ok, cold_chain_ok, vvm,
    safety, coalesce(review_notes, ''), auth.uid()
  ) returning * into batch_record;

  update public.vaccine_inventory set updated_at = now() where id = inventory_record.id;
  insert into public.inventory_transactions (
    transaction_code, inventory_id, batch_id, transaction_type,
    quantity_delta, balance_before, balance_after, reason,
    reference_number, performed_by
  ) values (
    'ITXN-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.entity_code_seq')::text, 7, '0'),
    inventory_record.id, batch_record.id, 'received', received_quantity,
    previous_balance, previous_balance + received_quantity, 'Stock received',
    trim(delivery_ref), auth.uid()
  ) returning * into transaction_record;
  return transaction_record;
end;
$$;

alter table public.facilities enable row level security;
alter table public.profiles enable row level security;
alter table public.guardians enable row level security;
alter table public.children enable row level security;
alter table public.guardian_child_links enable row level security;
alter table public.guardian_invitations enable row level security;
alter table public.child_link_requests enable row level security;
alter table public.guardian_corrections enable row level security;
alter table public.child_corrections enable row level security;
alter table public.vaccine_definitions enable row level security;
alter table public.pnip_schedule_rules enable row level security;
alter table public.vaccination_records enable row level security;
alter table public.vaccination_screenings enable row level security;
alter table public.first_visit_reviews enable row level security;
alter table public.referral_groups enable row level security;
alter table public.referral_items enable row level security;
alter table public.external_vaccination_visits enable row level security;
alter table public.external_visit_items enable row level security;
alter table public.appointments enable row level security;
alter table public.appointment_offers enable row level security;
alter table public.reminders enable row level security;
alter table public.reminder_preferences enable row level security;
alter table public.reminder_follow_ups enable row level security;
alter table public.advisory_insights enable row level security;
alter table public.cold_chain_checks enable row level security;
alter table public.vaccine_inventory enable row level security;
alter table public.vaccine_batches enable row level security;
alter table public.inventory_transactions enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_self_or_staff_select on public.profiles for select
using (id = auth.uid() or public.is_health_worker());
create policy profiles_staff_manage on public.profiles for all
using (public.is_health_worker()) with check (public.is_health_worker());

create policy facilities_authenticated_read on public.facilities for select to authenticated using (true);
create policy vaccines_authenticated_read on public.vaccine_definitions for select to authenticated using (true);
create policy rules_authenticated_read on public.pnip_schedule_rules for select to authenticated using (true);

create policy guardians_self_or_staff_select on public.guardians for select
using (profile_id = auth.uid() or public.is_health_worker());
create policy guardians_staff_manage on public.guardians for all
using (public.is_health_worker()) with check (public.is_health_worker());

create policy children_guardian_or_staff_select on public.children for select
using (public.guardian_can_access_child(id) or public.is_health_worker());
create policy children_staff_manage on public.children for all
using (public.is_health_worker()) with check (public.is_health_worker());

create policy links_related_or_staff_select on public.guardian_child_links for select
using (
  public.is_health_worker() or
  exists (select 1 from public.guardians g where g.id = guardian_id and g.profile_id = auth.uid())
);
create policy links_staff_manage on public.guardian_child_links for all
using (public.is_health_worker()) with check (public.is_health_worker());

create policy link_requests_related_read on public.child_link_requests for select
using (public.is_health_worker() or exists (
  select 1 from public.guardians g where g.id = guardian_id and g.profile_id = auth.uid()
));
create policy link_requests_guardian_insert on public.child_link_requests for insert
with check (exists (
  select 1 from public.guardians g where g.id = guardian_id and g.profile_id = auth.uid()
));
create policy link_requests_staff_manage on public.child_link_requests for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy guardian_corrections_staff on public.guardian_corrections for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy child_corrections_staff on public.child_corrections for all
using (public.is_health_worker()) with check (public.is_health_worker());

create policy vaccination_guardian_or_staff_select on public.vaccination_records for select
using (public.guardian_can_access_child(child_id) or public.is_health_worker());
create policy vaccination_staff_manage on public.vaccination_records for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy screenings_guardian_or_staff_read on public.vaccination_screenings for select
using (public.guardian_can_access_child(child_id) or public.is_health_worker());
create policy screenings_staff_manage on public.vaccination_screenings for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy first_visit_guardian_or_staff_read on public.first_visit_reviews for select
using (public.guardian_can_access_child(child_id) or public.is_health_worker());
create policy first_visit_staff_manage on public.first_visit_reviews for all
using (public.is_health_worker()) with check (public.is_health_worker());

create policy referrals_guardian_or_staff_select on public.referral_groups for select
using (public.guardian_can_access_child(child_id) or public.is_health_worker());
create policy referrals_staff_manage on public.referral_groups for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy referral_items_related_read on public.referral_items for select
using (exists (
  select 1 from public.referral_groups g
  where g.id = referral_group_id
    and (public.guardian_can_access_child(g.child_id) or public.is_health_worker())
));
create policy referral_items_staff_manage on public.referral_items for all
using (public.is_health_worker()) with check (public.is_health_worker());

create policy appointments_guardian_or_staff_select on public.appointments for select
using (public.guardian_can_access_child(child_id) or public.is_health_worker());
create policy appointments_staff_manage on public.appointments for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy appointment_offers_related_read on public.appointment_offers for select
using (exists (
  select 1 from public.appointments a
  where a.id = appointment_id
    and (public.guardian_can_access_child(a.child_id) or public.is_health_worker())
));

create policy reminders_guardian_or_staff_select on public.reminders for select
using (public.guardian_can_access_child(child_id) or public.is_health_worker());
create policy reminders_guardian_update on public.reminders for update
using (public.guardian_can_access_child(child_id))
with check (public.guardian_can_access_child(child_id));
create policy reminders_staff_manage on public.reminders for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy reminder_preferences_related on public.reminder_preferences for select
using (public.is_health_worker() or exists (
  select 1 from public.guardians g where g.id = guardian_id and g.profile_id = auth.uid()
));
create policy reminder_preferences_guardian_update on public.reminder_preferences for all
using (exists (select 1 from public.guardians g where g.id = guardian_id and g.profile_id = auth.uid()))
with check (exists (select 1 from public.guardians g where g.id = guardian_id and g.profile_id = auth.uid()));
create policy reminder_preferences_staff on public.reminder_preferences for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy follow_ups_staff on public.reminder_follow_ups for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy advisory_staff on public.advisory_insights for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy cold_chain_staff on public.cold_chain_checks for all
using (public.is_health_worker()) with check (public.is_health_worker());

create policy inventory_staff_only on public.vaccine_inventory for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy batches_staff_only on public.vaccine_batches for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy transactions_staff_only on public.inventory_transactions for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy visits_staff_only on public.external_vaccination_visits for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy visit_items_staff_only on public.external_visit_items for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy invitations_staff_only on public.guardian_invitations for all
using (public.is_health_worker()) with check (public.is_health_worker());
create policy audit_staff_read on public.audit_logs for select
using (public.is_health_worker());
