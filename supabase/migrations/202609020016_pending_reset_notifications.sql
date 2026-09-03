begin;

create or replace function public.get_pending_guardian_password_resets()
returns table(
  id uuid,
  guardian_id uuid,
  requested_username text,
  requested_at timestamptz,
  guardian_name text
) language sql security definer set search_path = public as $$
  select r.id, r.guardian_id, r.requested_username, r.requested_at, g.full_name
  from public.guardian_password_reset_requests r
  join public.guardians g on g.id = r.guardian_id
  where r.status = 'pending'
    and public.is_health_worker()
    and public.staff_at_facility(g.facility_id)
  order by r.requested_at desc
$$;

revoke all on function public.get_pending_guardian_password_resets() from public, anon;
grant execute on function public.get_pending_guardian_password_resets() to authenticated;

commit;
