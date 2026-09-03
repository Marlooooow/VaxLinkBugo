begin;

drop function if exists public.request_guardian_password_reset(text);

create function public.request_guardian_password_reset(requested_username text)
returns boolean language plpgsql security definer set search_path = public as $$
declare target_guardian uuid;
begin
  select g.id into target_guardian
  from public.profiles p
  join public.guardians g on g.profile_id = p.id
  where lower(p.username) = lower(trim(requested_username))
    and p.role = 'guardian' and p.active = true;
  if target_guardian is null then return false; end if;
  insert into public.guardian_password_reset_requests(guardian_id, requested_username)
  values (target_guardian, lower(trim(requested_username)))
  on conflict (guardian_id, status) do nothing;
  return true;
end $$;

revoke all on function public.request_guardian_password_reset(text) from public;
grant execute on function public.request_guardian_password_reset(text) to anon, authenticated;

commit;
