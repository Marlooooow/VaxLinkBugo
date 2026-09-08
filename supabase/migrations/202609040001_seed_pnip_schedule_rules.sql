-- Fixes: "No active PNIP schedule rule exists for <vaccine> dose <n>." raised by
-- public.create_referral_group() when generating a QR referral for any vaccine/dose.
--
-- Root cause: public.pnip_schedule_rules was created in
-- 202608300001_initial_schema.sql but no migration or seed file ever populated it,
-- even though create_referral_group() requires a matching active row to compute
-- the referral's scheduled_due_date. Every referral generation call failed with
-- this error regardless of child or vaccine, because the table was always empty.
--
-- The age offsets below mirror the schedule already used on the client
-- (lib/services/pnip_schedule_service.dart) and in
-- 202609020003_child_reminder_synchronization.sql, so referral due dates line up
-- with the reminders/schedule the guardian and health worker already see.
begin;

-- Migrations run before seed.sql on a clean reset. Ensure the referenced
-- vaccine catalog exists before inserting schedule rules.
insert into public.vaccine_definitions (
  id, vaccine_code, name, disease_prevented, active
) values
  ('bcg', 'VAC-BCG', 'BCG', 'Severe forms of tuberculosis', true),
  ('hepatitis_b', 'VAC-HEPB', 'Hepatitis B', 'Hepatitis B', true),
  ('pentavalent', 'VAC-PENTA', 'Pentavalent', 'Diphtheria, pertussis, tetanus, hepatitis B, and Hib', true),
  ('opv', 'VAC-OPV', 'OPV', 'Poliomyelitis', true),
  ('pcv', 'VAC-PCV', 'PCV', 'Pneumococcal disease', true),
  ('ipv', 'VAC-IPV', 'IPV', 'Poliomyelitis', true),
  ('mmr', 'VAC-MMR', 'MMR', 'Measles, mumps, and rubella', true)
on conflict (id) do update set
  vaccine_code = excluded.vaccine_code,
  name = excluded.name,
  disease_prevented = excluded.disease_prevented,
  active = excluded.active;

insert into public.pnip_schedule_rules (
  vaccine_id, dose_number, minimum_age_days, recommended_age_days,
  minimum_interval_days, catch_up_allowed, effective_from, effective_to,
  source_reference, active
) values
  ('bcg',         1, 0,   0,   null, true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),
  ('hepatitis_b', 1, 0,   0,   null, true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),

  ('pentavalent', 1, 42,  42,  null, true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),
  ('pentavalent', 2, 70,  70,  28,   true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),
  ('pentavalent', 3, 98,  98,  28,   true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),

  ('opv',         1, 42,  42,  null, true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),
  ('opv',         2, 70,  70,  28,   true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),
  ('opv',         3, 98,  98,  28,   true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),

  ('pcv',         1, 42,  42,  null, true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),
  ('pcv',         2, 70,  70,  28,   true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),
  ('pcv',         3, 98,  98,  28,   true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),

  -- Two-dose IPV routine schedule: IPV2 at least 4 months after IPV1.
  -- https://hta.dost.gov.ph/wp-content/uploads/2021/09/HTAC-Recommendation-and-ES-on-Two-dose-IPV.pdf
  ('ipv',         1, 98,  98,  null, true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),
  ('ipv',         2, 270, 270, 120,  true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),

  ('mmr',         1, 270, 270, null, true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true),
  ('mmr',         2, 365, 365, 28,   true, '2020-01-01', null, 'DOH Philippine National Immunization Program (PNIP) schedule', true)
on conflict (vaccine_id, dose_number, effective_from) do update set
  minimum_age_days = excluded.minimum_age_days,
  recommended_age_days = excluded.recommended_age_days,
  minimum_interval_days = excluded.minimum_interval_days,
  catch_up_allowed = excluded.catch_up_allowed,
  effective_to = excluded.effective_to,
  source_reference = excluded.source_reference,
  active = excluded.active;

commit;
