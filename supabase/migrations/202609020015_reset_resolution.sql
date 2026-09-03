begin;

drop function if exists public.complete_guardian_password_reset(uuid, uuid);

create function public.complete_guardian_password_reset(
  target_request_id uuid, resolver_id uuid
) returns void language plpgsql security definer set search_path = public as $$
declare g public.guardians; request_record public.guardian_password_reset_requests;
begin
  select * into request_record from public.guardian_password_reset_requests
    where id = target_request_id and status = 'pending' for update;
  if not found then raise exception 'Reset request is no longer pending'; end if;
  select * into g from public.guardians where id = request_record.guardian_id for update;
  if not found or not exists (
    select 1 from public.profiles p
    where p.id = resolver_id and p.facility_id = g.facility_id
      and p.active and p.role in ('health_worker', 'administrator')
  ) then raise exception 'Not authorized'; end if;
  update public.profiles set must_change_password = true, updated_at = now() where id = g.profile_id;
  update public.guardian_password_reset_requests
  set status = 'completed', resolved_by = resolver_id, resolved_at = now()
  where id = request_record.id and status = 'pending';
  insert into public.audit_logs(actor_id, facility_id, action, entity_type, entity_id, new_values)
  values (resolver_id, g.facility_id, 'guardian_password_reset', 'guardians', g.id::text,
    jsonb_build_object('guardian_id', g.id, 'profile_id', g.profile_id));
end $$;

revoke all on function public.complete_guardian_password_reset(uuid, uuid) from public, anon, authenticated;
grant execute on function public.complete_guardian_password_reset(uuid, uuid) to service_role;
grant select on public.guardian_password_reset_requests to authenticated;

commit;
