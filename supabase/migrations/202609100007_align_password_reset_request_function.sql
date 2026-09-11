begin;

create or replace function public.request_guardian_password_reset(
  requested_username text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  target_guardian uuid;
  normalized_code text;
begin
  normalized_code := upper(trim(requested_username));

  select guardian.id into target_guardian
  from public.guardians guardian
  join public.profiles profile on profile.id = guardian.profile_id
  where upper(guardian.guardian_code) = normalized_code
    and profile.role = 'guardian'
    and profile.active = true;

  if target_guardian is null then
    return false;
  end if;

  insert into public.guardian_password_reset_requests (
    guardian_id,
    requested_username
  )
  values (target_guardian, normalized_code)
  on conflict (guardian_id) where status = 'pending'
  do nothing;

  return true;
end
$$;

revoke all on function public.request_guardian_password_reset(text)
from public;
grant execute on function public.request_guardian_password_reset(text)
to anon, authenticated;

commit;
