begin;

-- The reset-guardian-password Edge Function uses the service-role client to
-- resolve and complete requests. Table privileges are still required even
-- though service_role bypasses row-level security.
grant select, update
on table public.guardian_password_reset_requests
to service_role;

commit;
