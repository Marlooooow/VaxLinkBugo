-- Allow the existing authenticated stock functions to complete their
-- transaction while RLS continues to restrict access to the worker's facility.
begin;

grant update on public.vaccine_inventory to authenticated;
grant insert, update on public.vaccine_batches to authenticated;
grant insert on public.inventory_transactions to authenticated;
grant execute on function public.record_inventory_movement(uuid, text, integer, text, text)
  to authenticated;
grant execute on function public.receive_vaccine_stock(uuid, text, text, date, integer, text, boolean, boolean, text, text)
  to authenticated;

commit;
