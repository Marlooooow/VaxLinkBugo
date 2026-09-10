begin;

create table if not exists public.advisory_reference_counters (
  reference_year integer primary key,
  last_value bigint not null check (last_value > 0)
);

alter table public.advisory_reference_counters enable row level security;
revoke all on table public.advisory_reference_counters from public, anon, authenticated;

alter table public.advisory_insights
  add column if not exists reference_code text;

with numbered as (
  select
    insight.id,
    extract(
      year from insight.generated_at at time zone 'Asia/Manila'
    )::integer as reference_year,
    row_number() over (
      partition by extract(
        year from insight.generated_at at time zone 'Asia/Manila'
      )
      order by insight.generated_at, insight.id
    ) as reference_number
  from public.advisory_insights insight
  where insight.reference_code is null
)
update public.advisory_insights insight
set reference_code =
  'ADV-' || numbered.reference_year::text || '-' ||
  lpad(numbered.reference_number::text, 6, '0')
from numbered
where insight.id = numbered.id;

insert into public.advisory_reference_counters (reference_year, last_value)
select
  split_part(insight.reference_code, '-', 2)::integer,
  max(split_part(insight.reference_code, '-', 3)::bigint)
from public.advisory_insights insight
where insight.reference_code ~ '^ADV-[0-9]{4}-[0-9]{6,}$'
group by split_part(insight.reference_code, '-', 2)::integer
on conflict (reference_year) do update
set last_value = greatest(
  public.advisory_reference_counters.last_value,
  excluded.last_value
);

create or replace function public.next_advisory_reference(
  p_generated_at timestamptz default now()
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target_year integer := extract(
    year from p_generated_at at time zone 'Asia/Manila'
  )::integer;
  next_value bigint;
begin
  insert into public.advisory_reference_counters (
    reference_year,
    last_value
  )
  values (target_year, 1)
  on conflict (reference_year) do update
  set last_value = public.advisory_reference_counters.last_value + 1
  returning last_value into next_value;

  return 'ADV-' || target_year::text || '-' ||
    lpad(next_value::text, 6, '0');
end;
$$;

revoke all on function public.next_advisory_reference(timestamptz)
  from public, anon, authenticated;

create or replace function public.assign_advisory_reference()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.reference_code is null or btrim(new.reference_code) = '' then
    new.reference_code := public.next_advisory_reference(new.generated_at);
  end if;
  return new;
end;
$$;

revoke all on function public.assign_advisory_reference()
  from public, anon, authenticated;

drop trigger if exists advisory_insights_assign_reference
  on public.advisory_insights;
create trigger advisory_insights_assign_reference
before insert on public.advisory_insights
for each row execute function public.assign_advisory_reference();

alter table public.advisory_insights
  alter column reference_code set not null;

create unique index if not exists advisory_insights_reference_code_key
  on public.advisory_insights (reference_code);

comment on column public.advisory_insights.reference_code is
  'Human-readable staff reference; the technical insight_code remains internal.';

commit;
