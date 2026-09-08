begin;

create index if not exists vaccine_batches_inventory_attention_idx
  on public.vaccine_batches (inventory_id, safety_status, expiry_date)
  where quantity > 0;

create or replace function public.get_inventory_attention_counts()
returns table(vaccine_id text, attention_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select
    inventory.vaccine_id,
    count(*) as attention_count
  from public.vaccine_batches batch
  join public.vaccine_inventory inventory on inventory.id = batch.inventory_id
  where public.is_health_worker()
    and inventory.facility_id = public.current_facility_id()
    and batch.quantity > 0
    and (
      batch.safety_status = 'quarantined'
      or (
        batch.expiry_date < current_date
        and batch.safety_status <> 'discarded'
      )
    )
  group by inventory.vaccine_id;
$$;

revoke all on function public.get_inventory_attention_counts() from public;
grant execute on function public.get_inventory_attention_counts()
  to authenticated;

commit;
