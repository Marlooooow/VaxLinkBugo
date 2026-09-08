-- Repair a hosted receive_vaccine_stock definition that referenced the
-- nonexistent vaccine_batches.vaccine_id column. A batch belongs to a vaccine
-- through vaccine_batches.inventory_id -> vaccine_inventory.id.
begin;

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
language plpgsql
security definer
set search_path = ''
as $$
declare
  inventory_record public.vaccine_inventory%rowtype;
  batch_record public.vaccine_batches%rowtype;
  previous_balance integer;
  transaction_record public.inventory_transactions%rowtype;
  safety text;
begin
  if auth.uid() is null then
    raise exception 'Please sign in again.';
  end if;

  if received_quantity is null or received_quantity <= 0 then
    raise exception 'Quantity must be greater than zero.';
  end if;

  if nullif(trim(lot), '') is null
     or expiry is null
     or nullif(trim(delivery_ref), '') is null then
    raise exception 'Lot number, expiry date, and delivery reference are required.';
  end if;

  if expiry <= current_date then
    raise exception 'Expiry date must be in the future.';
  end if;

  if vvm not in ('not_applicable', 'acceptable', 'not_acceptable', 'unknown') then
    raise exception 'Invalid VVM status.';
  end if;

  select vi.*
  into inventory_record
  from public.vaccine_inventory vi
  where vi.id = target_inventory_id
  for update;

  if inventory_record.id is null then
    raise exception 'Inventory item was not found.';
  end if;

  if not public.staff_at_facility(inventory_record.facility_id) then
    raise exception 'Not authorized to receive stock for this facility.';
  end if;

  -- vaccine_batches has inventory_id, not vaccine_id.
  select coalesce(sum(vb.quantity), 0)::integer
  into previous_balance
  from public.vaccine_batches vb
  where vb.inventory_id = inventory_record.id;

  safety := case
    when coalesce(package_ok, false)
      and coalesce(cold_chain_ok, false)
      and vvm <> 'not_acceptable'
    then 'usable'
    else 'quarantined'
  end;

  insert into public.vaccine_batches (
    inventory_id,
    lot_number,
    batch_code,
    expiry_date,
    quantity_received,
    quantity,
    manufacturer,
    delivery_reference,
    received_by,
    packaging_intact,
    cold_chain_verified,
    vvm_status,
    safety_status,
    safety_notes,
    safety_reviewed_by
  ) values (
    inventory_record.id,
    trim(lot),
    'VBAT-' || to_char(now(), 'YYYY') || '-' ||
      lpad(nextval('public.entity_code_seq')::text, 7, '0'),
    expiry,
    received_quantity,
    received_quantity,
    nullif(trim(manufacturer_name), ''),
    trim(delivery_ref),
    auth.uid(),
    coalesce(package_ok, false),
    coalesce(cold_chain_ok, false),
    vvm,
    safety,
    coalesce(review_notes, ''),
    auth.uid()
  )
  returning * into batch_record;

  update public.vaccine_inventory vi
  set updated_at = now()
  where vi.id = inventory_record.id;

  insert into public.inventory_transactions (
    transaction_code,
    inventory_id,
    batch_id,
    transaction_type,
    quantity_delta,
    balance_before,
    balance_after,
    reason,
    reference_number,
    performed_by
  ) values (
    'ITXN-' || to_char(now(), 'YYYY') || '-' ||
      lpad(nextval('public.entity_code_seq')::text, 7, '0'),
    inventory_record.id,
    batch_record.id,
    'received',
    received_quantity,
    previous_balance,
    previous_balance + received_quantity,
    'Stock received',
    trim(delivery_ref),
    auth.uid()
  )
  returning * into transaction_record;

  return transaction_record;
end;
$$;

revoke all on function public.receive_vaccine_stock(
  uuid, text, text, date, integer, text, boolean, boolean, text, text
) from public, anon;

grant execute on function public.receive_vaccine_stock(
  uuid, text, text, date, integer, text, boolean, boolean, text, text
) to authenticated;

commit;
