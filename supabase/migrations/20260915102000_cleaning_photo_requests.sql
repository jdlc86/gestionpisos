-- Freeze the set of photos requested for each cleaning task.
-- Selection is random once, then stable across reloads/retries.

create table public.cleaning_photo_requests_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  property_id uuid not null references public.properties_v2(id) on delete cascade,
  cleaning_task_id uuid not null references public.cleaning_tasks_v2(id) on delete cascade,
  pattern_id uuid not null references public.photo_patterns_v2(id),
  request_kind text not null default 'cleaning'
    check (request_kind in ('cleaning','maintenance','state')),
  ordinal integer not null check (ordinal > 0),
  completed_run_id uuid references public.photo_verification_runs_v2(id),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(cleaning_task_id,pattern_id,request_kind),
  unique(cleaning_task_id,ordinal)
);

alter table public.cleaning_photo_requests_v2 enable row level security;
revoke all on table public.cleaning_photo_requests_v2 from anon,authenticated;

create table public.cleaning_photo_request_policies_v2 (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  cleaning_pattern_count integer not null default 2 check (cleaning_pattern_count between 1 and 20),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

alter table public.cleaning_photo_request_policies_v2 enable row level security;
revoke all on table public.cleaning_photo_request_policies_v2 from anon,authenticated;

create or replace function private.ensure_cleaning_photo_requests_v2(
  p_cleaning_task_id uuid
)
returns setof public.cleaning_photo_requests_v2
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_task public.cleaning_tasks_v2;
  v_count integer;
begin
  select * into v_task from public.cleaning_tasks_v2
  where id=p_cleaning_task_id for update;
  if not found then raise exception 'cleaning_task_not_found' using errcode='P0002'; end if;

  if exists(select 1 from public.cleaning_photo_requests_v2 where cleaning_task_id=v_task.id) then
    return query select * from public.cleaning_photo_requests_v2
      where cleaning_task_id=v_task.id order by ordinal;
    return;
  end if;

  select coalesce(p.cleaning_pattern_count,2) into v_count
  from (select 1) x
  left join public.cleaning_photo_request_policies_v2 p
    on p.organization_id=v_task.organization_id;

  insert into public.cleaning_photo_requests_v2(
    organization_id,property_id,cleaning_task_id,pattern_id,request_kind,ordinal
  )
  select
    v_task.organization_id,v_task.property_id,v_task.id,p.id,'cleaning',
    row_number() over (order by random())::integer
  from (
    select pp.id
    from public.photo_patterns_v2 pp
    where pp.organization_id=v_task.organization_id
      and pp.property_id=v_task.property_id
      and pp.active=true
      and pp.retired_at is null
      and pp.contour_data is not null
      and jsonb_typeof(pp.contour_data)='object'
    order by random()
    limit v_count
  ) p;

  if not exists(select 1 from public.cleaning_photo_requests_v2 where cleaning_task_id=v_task.id) then
    raise exception 'no_active_cleaning_patterns' using errcode='55000';
  end if;

  return query select * from public.cleaning_photo_requests_v2
    where cleaning_task_id=v_task.id order by ordinal;
end;
$$;

revoke all on function private.ensure_cleaning_photo_requests_v2(uuid) from public,anon,authenticated;

comment on table public.cleaning_photo_requests_v2 is
  'Frozen per-task photo checklist. Cleaning requests may later coexist with maintenance/state requests without changing their business semantics.';
comment on function private.ensure_cleaning_photo_requests_v2(uuid) is
  'Randomly chooses active patterns once for a cleaning task, then returns the same frozen checklist on every retry.';
