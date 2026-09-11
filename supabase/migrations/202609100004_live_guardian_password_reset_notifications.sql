begin;

drop policy if exists guardian_reset_requests_staff_select
  on public.guardian_password_reset_requests;
create policy guardian_reset_requests_staff_select
on public.guardian_password_reset_requests
for select to authenticated
using (
  public.is_health_worker()
  and exists (
    select 1
    from public.guardians guardian
    where guardian.id = guardian_password_reset_requests.guardian_id
      and public.staff_at_facility(guardian.facility_id)
  )
);

drop policy if exists guardian_reset_requests_staff_update
  on public.guardian_password_reset_requests;
create policy guardian_reset_requests_staff_update
on public.guardian_password_reset_requests
for update to authenticated
using (
  public.is_health_worker()
  and exists (
    select 1
    from public.guardians guardian
    where guardian.id = guardian_password_reset_requests.guardian_id
      and public.staff_at_facility(guardian.facility_id)
  )
)
with check (
  public.is_health_worker()
  and exists (
    select 1
    from public.guardians guardian
    where guardian.id = guardian_password_reset_requests.guardian_id
      and public.staff_at_facility(guardian.facility_id)
  )
);

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'guardian_password_reset_requests'
  ) then
    alter publication supabase_realtime
      add table public.guardian_password_reset_requests;
  end if;
end
$$;

commit;
