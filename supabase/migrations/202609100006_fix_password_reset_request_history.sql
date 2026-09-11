begin;

-- A guardian may have many completed or cancelled password-reset requests over
-- time. Only an active pending request must be unique.
alter table public.guardian_password_reset_requests
  drop constraint if exists
  guardian_password_reset_requests_guardian_id_status_key;

create unique index if not exists
  guardian_password_reset_requests_one_pending_per_guardian_idx
on public.guardian_password_reset_requests (guardian_id)
where status = 'pending';

commit;
