-- Non-sensitive reference seed. Authentication users are provisioned separately.
insert into public.facilities (id, facility_code, name, barangay, city)
values (
  '00000000-0000-4000-8100-000000000001',
  'FAC-BUGO-001',
  'Barangay Bugo Health Center',
  'Bugo',
  'Cagayan de Oro City'
)
on conflict (id) do update set name = excluded.name, updated_at = now();

insert into public.vaccine_definitions (id, vaccine_code, name, disease_prevented)
values
  ('bcg', 'VAC-BCG', 'BCG', 'Severe forms of tuberculosis'),
  ('hepatitis_b', 'VAC-HEPB', 'Hepatitis B', 'Hepatitis B'),
  ('pentavalent', 'VAC-PENTA', 'Pentavalent', 'Diphtheria, pertussis, tetanus, hepatitis B, and Hib'),
  ('opv', 'VAC-OPV', 'OPV', 'Poliomyelitis'),
  ('pcv', 'VAC-PCV', 'PCV', 'Pneumococcal disease'),
  ('ipv', 'VAC-IPV', 'IPV', 'Poliomyelitis'),
  ('mmr', 'VAC-MMR', 'MMR', 'Measles, mumps, and rubella')
on conflict (id) do update set name = excluded.name, disease_prevented = excluded.disease_prevented;

insert into public.vaccine_inventory (id, facility_id, vaccine_id, reorder_level)
values
  ('00000000-0000-4000-8200-000000000001', '00000000-0000-4000-8100-000000000001', 'pentavalent', 5),
  ('00000000-0000-4000-8200-000000000002', '00000000-0000-4000-8100-000000000001', 'opv', 5),
  ('00000000-0000-4000-8200-000000000003', '00000000-0000-4000-8100-000000000001', 'bcg', 5),
  ('00000000-0000-4000-8200-000000000004', '00000000-0000-4000-8100-000000000001', 'hepatitis_b', 5),
  ('00000000-0000-4000-8200-000000000005', '00000000-0000-4000-8100-000000000001', 'pcv', 5),
  ('00000000-0000-4000-8200-000000000006', '00000000-0000-4000-8100-000000000001', 'ipv', 5),
  ('00000000-0000-4000-8200-000000000007', '00000000-0000-4000-8100-000000000001', 'mmr', 5)
on conflict (id) do update set reorder_level = excluded.reorder_level, updated_at = now();
