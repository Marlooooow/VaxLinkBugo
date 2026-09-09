-- Give guardians, children, and staff independent, concurrency-safe yearly
-- display-code sequences. UUID primary keys remain unchanged.
begin;

create table if not exists public.entity_code_counters (
  entity_prefix text not null,
  code_year integer not null,
  last_value bigint not null check (last_value > 0),
  updated_at timestamptz not null default now(),
  primary key (entity_prefix, code_year),
  check (entity_prefix in ('CH', 'GRD', 'STF')),
  check (code_year between 2000 and 9999)
);

-- Start each counter after the highest existing code for that entity and year.
-- Existing codes are deliberately preserved.
insert into public.entity_code_counters (
  entity_prefix,
  code_year,
  last_value
)
select
  existing.entity_prefix,
  existing.code_year,
  max(existing.code_number)
from (
  select
    'CH'::text as entity_prefix,
    split_part(child_code, '-', 2)::integer as code_year,
    split_part(child_code, '-', 3)::bigint as code_number
  from public.children
  where child_code ~ '^CH-[0-9]{4}-[0-9]+$'

  union all

  select
    'GRD'::text,
    split_part(guardian_code, '-', 2)::integer,
    split_part(guardian_code, '-', 3)::bigint
  from public.guardians
  where guardian_code ~ '^GRD-[0-9]{4}-[0-9]+$'

  union all

  select
    'STF'::text,
    split_part(staff_code, '-', 2)::integer,
    split_part(staff_code, '-', 3)::bigint
  from public.staff_members
  where staff_code ~ '^STF-[0-9]{4}-[0-9]+$'
) existing
group by existing.entity_prefix, existing.code_year
on conflict (entity_prefix, code_year) do update
set
  last_value = greatest(
    public.entity_code_counters.last_value,
    excluded.last_value
  ),
  updated_at = now();

create or replace function public.live_entity_code(prefix text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  normalized_prefix text := upper(trim(prefix));
  current_code_year integer := extract(year from current_date)::integer;
  next_number bigint;
begin
  if normalized_prefix in ('CH', 'GRD', 'STF') then
    insert into public.entity_code_counters as counter (
      entity_prefix,
      code_year,
      last_value,
      updated_at
    )
    values (normalized_prefix, current_code_year, 1, now())
    on conflict (entity_prefix, code_year) do update
    set
      last_value = counter.last_value + 1,
      updated_at = now()
    returning last_value into next_number;

    return normalized_prefix || '-' || current_code_year::text || '-' ||
      lpad(next_number::text, greatest(6, length(next_number::text)), '0');
  end if;

  -- Preserve the existing global sequence behavior for other operational IDs.
  return normalized_prefix || '-' || to_char(current_date, 'YYYY') || '-' ||
    lpad(
      nextval('public.entity_code_seq'::regclass)::text,
      6,
      '0'
    );
end;
$$;

revoke all on table public.entity_code_counters from public, anon, authenticated;
revoke all on function public.live_entity_code(text) from public;
grant execute on function public.live_entity_code(text) to authenticated;

commit;
