begin;

create or replace function public.correct_guardian_details(target_guardian_id uuid, changes jsonb, correction_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare g public.guardians; before_g jsonb; correction public.guardian_corrections;
  before_links jsonb; after_links jsonb; before_requests jsonb; after_requests jsonb;
  display_name text;
begin
  select * into g from public.guardians where id = target_guardian_id;
  if not found or not public.staff_at_facility(g.facility_id) then raise exception 'Not authorized'; end if;
  perform pg_advisory_xact_lock(hashtextextended(g.facility_id::text, 0));
  select * into g from public.guardians where id = target_guardian_id for update;
  if nullif(trim(correction_reason), '') is null then raise exception 'A correction reason is required'; end if;
  display_name := public.request_person_name(changes);
  if coalesce(changes->>'sex', '') not in ('male','female') then raise exception 'Guardian name and sex are required'; end if;
  if nullif(trim(changes->>'birth_date'), '') is not null
    and (changes->>'birth_date')::date > current_date then
    raise exception 'Guardian birth date cannot be in the future';
  end if;
  if changes - array['full_name','first_name','middle_name','last_name','suffix','birth_date','sex','phone','address'] <> '{}'::jsonb then
    raise exception 'Unsupported correction fields';
  end if;
  before_g := to_jsonb(g);
  select coalesce(jsonb_agg(to_jsonb(l) order by l.id), '[]') into before_links from public.guardian_child_links l where l.guardian_id = g.id;
  select coalesce(jsonb_agg(to_jsonb(r) order by r.id), '[]') into before_requests from public.child_link_requests r where r.guardian_id = g.id and r.status='pending';
  update public.guardians set
    full_name = display_name,
    first_name = nullif(trim(changes->>'first_name'), ''),
    middle_name = nullif(trim(changes->>'middle_name'), ''),
    last_name = nullif(trim(changes->>'last_name'), ''),
    suffix = nullif(trim(changes->>'suffix'), ''),
    birth_date = nullif(trim(changes->>'birth_date'), '')::date,
    sex = changes->>'sex', phone = nullif(trim(changes->>'phone'), ''), address = trim(changes->>'address')
    where id = g.id returning * into g;
  update public.guardian_child_links set relationship = public.relationship_for_guardian_sex(g.sex, relationship) where guardian_id = g.id;
  update public.child_link_requests set relationship = public.relationship_for_guardian_sex(g.sex, relationship) where guardian_id = g.id and status='pending';
  if g.profile_id is not null then
    update public.profiles set full_name = g.full_name, first_name = g.first_name, middle_name = g.middle_name,
      last_name = g.last_name, suffix = g.suffix where id = g.profile_id;
  end if;
  select coalesce(jsonb_agg(to_jsonb(l) order by l.id), '[]') into after_links from public.guardian_child_links l where l.guardian_id = g.id;
  select coalesce(jsonb_agg(to_jsonb(r) order by r.id), '[]') into after_requests from public.child_link_requests r where r.guardian_id = g.id and r.status='pending';
  insert into public.guardian_corrections(correction_code, guardian_id, previous_values, updated_values, reason, corrected_by)
  values(public.live_entity_code('GCOR'), g.id, before_g || jsonb_build_object('links',before_links,'pending_requests',before_requests),
    to_jsonb(g) || jsonb_build_object('links',after_links,'pending_requests',after_requests), trim(correction_reason), auth.uid()) returning * into correction;
  return jsonb_build_object('guardian', to_jsonb(g), 'correction', to_jsonb(correction));
end $$;

commit;
