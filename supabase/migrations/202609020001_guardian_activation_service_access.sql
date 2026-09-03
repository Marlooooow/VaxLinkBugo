begin;

-- Guardian activation runs before the guardian has a session. The Edge Function
-- uses Supabase's server-only service role to validate the invitation and related
-- records, then delegates all writes to the audited SECURITY DEFINER transaction.
-- Keep direct table access read-only and limited to the lookup tables it needs.
grant select on table
  public.guardian_invitations,
  public.guardians,
  public.facilities,
  public.profiles
to service_role;

revoke insert, update, delete on table
  public.guardian_invitations,
  public.guardians,
  public.facilities,
  public.profiles
from service_role;

revoke all on function public.activate_guardian_profile(uuid, uuid, text)
from public, anon, authenticated;
grant execute on function public.activate_guardian_profile(uuid, uuid, text)
to service_role;

commit;
