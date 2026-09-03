begin;

create function public.synchronize_guardian_login_identity(
  target_guardian_id uuid, resolver_id uuid, requested_username text
) returns void language plpgsql security definer set search_path = public as $$
declare g public.guardians;
begin
  select * into g from public.guardians where id = target_guardian_id for update;
  if not found or not exists (
    select 1 from public.profiles p
    where p.id = resolver_id and p.facility_id = g.facility_id
      and p.active and p.role in ('health_worker', 'administrator')
  ) then raise exception 'Not authorized'; end if;
  if lower(trim(requested_username)) <> lower(trim(g.guardian_code)) then
    raise exception 'Guardian ID username mismatch';
  end if;
  update public.profiles
  set username = lower(trim(g.guardian_code)), must_change_password = true, updated_at = now()
  where id = g.profile_id;
end $$;

revoke all on function public.synchronize_guardian_login_identity(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.synchronize_guardian_login_identity(uuid, uuid, text)
  to service_role;

commit;
