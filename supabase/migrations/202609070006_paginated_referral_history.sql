-- One-query, server-filtered referral history page.
begin;

create index if not exists referral_groups_facility_issued_idx
  on public.referral_groups (originating_facility_id, issued_on desc, id desc);

create index if not exists referral_items_group_status_due_idx
  on public.referral_items (referral_group_id, status, scheduled_due_date);

create or replace function public.get_referral_group_page(
  p_search text default null,
  p_status text default null,
  p_overdue_only boolean default false,
  p_page_size integer default 20,
  p_page_offset integer default 0
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with base as (
    select
      referral_group.id,
      referral_group.referral_group_code,
      referral_group.child_id,
      referral_group.issued_on,
      referral_group.created_at,
      child.full_name as child_name,
      facility.name as facility_name,
      count(item.id) filter (where item.status = 'completed') as completed_items,
      count(item.id) as total_items,
      bool_or(item.status = 'pending' and item.scheduled_due_date < current_date)
        as is_overdue,
      case
        when count(item.id) > 0
          and count(item.id) filter (where item.status = 'completed') = count(item.id)
          then 'completed'
        when count(item.id) filter (where item.status = 'completed') > 0
          then 'partial'
        else 'pending'
      end as computed_status
    from public.referral_groups referral_group
    join public.children child on child.id = referral_group.child_id
    join public.facilities facility on facility.id = referral_group.originating_facility_id
    join public.referral_items item on item.referral_group_id = referral_group.id
    where public.is_health_worker()
      and referral_group.originating_facility_id = public.current_facility_id()
    group by referral_group.id, child.full_name, facility.name
  ),
  searched as (
    select base.*
    from base
    where (
      nullif(trim(p_search), '') is null
      or lower(base.child_name) like '%' || lower(trim(p_search)) || '%'
      or lower(base.referral_group_code) like '%' || lower(trim(p_search)) || '%'
      or exists (
        select 1
        from public.referral_items searched_item
        join public.vaccine_definitions vaccine
          on vaccine.id = searched_item.vaccine_id
        where searched_item.referral_group_id = base.id
          and (
            lower(searched_item.referral_code) like '%' || lower(trim(p_search)) || '%'
            or lower(vaccine.name) like '%' || lower(trim(p_search)) || '%'
          )
      )
    )
    and (p_status is null or base.computed_status = p_status)
    and (not p_overdue_only or base.is_overdue)
  ),
  page_groups as (
    select searched.*
    from searched
    order by searched.issued_on desc, searched.id desc
    offset greatest(coalesce(p_page_offset, 0), 0)
    limit least(greatest(coalesce(p_page_size, 20), 1), 50)
  ),
  page_items as (
    select
      page.issued_on,
      page.id,
      jsonb_build_object(
      'referral_group_id', page.id,
      'referral_group_code', page.referral_group_code,
      'verification_token', '',
      'child_id', page.child_id,
      'child_name', page.child_name,
      'originating_facility', page.facility_name,
      'issued_at', page.issued_on,
      'referrals', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', item.id,
            'referral_code', item.referral_code,
            'referral_group_id', page.id,
            'referral_group_code', page.referral_group_code,
            'child_id', page.child_id,
            'child_name', page.child_name,
            'vaccine_id', item.vaccine_id,
            'vaccine_name', vaccine.name,
            'dose_number', item.dose_number,
            'scheduled_due_date', coalesce(item.scheduled_due_date, page.issued_on),
            'originating_facility', page.facility_name,
            'status', case when item.status = 'completed' then 'Completed' else 'Pending' end,
            'created_at', page.created_at,
            'completed_at', item.completed_at
          ) order by item.referral_code
        )
        from public.referral_items item
        join public.vaccine_definitions vaccine on vaccine.id = item.vaccine_id
        where item.referral_group_id = page.id
      ), '[]'::jsonb)
    ) as item
    from page_groups page
  ),
  all_summary as (
    select jsonb_build_object(
      'pending', count(*) filter (where base.computed_status = 'pending'),
      'partial', count(*) filter (where base.computed_status = 'partial'),
      'completed', count(*) filter (where base.computed_status = 'completed'),
      'overdue', count(*) filter (where base.is_overdue)
    ) as value
    from base
  ),
  totals as (select count(*)::integer as value from searched),
  selected as (select count(*)::integer as value from page_groups)
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(
        page_items.item order by page_items.issued_on desc, page_items.id desc
      )
      from page_items
    ), '[]'::jsonb),
    'total_count', (select value from totals),
    'has_more', (select value from selected) + greatest(coalesce(p_page_offset, 0), 0)
      < (select value from totals),
    'next_offset', greatest(coalesce(p_page_offset, 0), 0) + (select value from selected),
    'summary', (select value from all_summary)
  );
$$;

revoke all on function public.get_referral_group_page(
  text, text, boolean, integer, integer
) from public;

grant execute on function public.get_referral_group_page(
  text, text, boolean, integer, integer
) to authenticated;

commit;
