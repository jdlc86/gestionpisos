-- GestionPisos · Flujos de Trabajo · evidencia fotográfica ligada a ejecución
-- Vincula patrones reales en Aplicaciones y congela su silueta/version al crear cada ejecución.

alter table public.photo_verification_runs_v2
  drop constraint if exists photo_verification_runs_v2_source_type_check;

alter table public.photo_verification_runs_v2
  add constraint photo_verification_runs_v2_source_type_check
  check (source_type in ('cleaning_task','inspection','random_request','manual','workflow_execution'));

drop policy if exists photo_runs_actor_insert on public.photo_verification_runs_v2;
create policy photo_runs_actor_insert
on public.photo_verification_runs_v2
for insert to authenticated
with check (
  actor_user_id=(select auth.uid())
  and source_type<>'workflow_execution'
);

create table public.workflow_application_photo_resources_v2 (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.workflow_applications_v2(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  property_id uuid not null references public.properties_v2(id) on delete restrict,
  pattern_id uuid not null references public.photo_patterns_v2(id) on delete restrict,
  sort_order integer not null check (sort_order>0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(application_id,pattern_id),
  unique(application_id,sort_order)
);

create index workflow_application_photo_resources_v2_property_idx
  on public.workflow_application_photo_resources_v2(property_id,application_id);

create table public.workflow_execution_photo_resources_v2 (
  id uuid primary key default gen_random_uuid(),
  execution_id uuid not null references public.workflow_executions_v2(id) on delete restrict,
  application_resource_id uuid not null references public.workflow_application_photo_resources_v2(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  property_id uuid not null references public.properties_v2(id) on delete restrict,
  pattern_id uuid not null references public.photo_patterns_v2(id) on delete restrict,
  pattern_version integer not null check (pattern_version>0),
  pattern_snapshot jsonb not null check (jsonb_typeof(pattern_snapshot)='object'),
  sort_order integer not null check (sort_order>0),
  requires_accept boolean not null default false,
  status text not null default 'pending'
    check (status in ('pending','capturing','submitted','cancelled')),
  photo_run_id uuid references public.photo_verification_runs_v2(id) on delete restrict,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(execution_id,application_resource_id),
  unique(execution_id,sort_order)
);

create unique index workflow_execution_photo_resources_v2_run_uq
  on public.workflow_execution_photo_resources_v2(photo_run_id)
  where photo_run_id is not null;

create index workflow_execution_photo_resources_v2_execution_status_idx
  on public.workflow_execution_photo_resources_v2(execution_id,status,sort_order);

alter table public.workflow_application_photo_resources_v2 enable row level security;
alter table public.workflow_execution_photo_resources_v2 enable row level security;

revoke all on public.workflow_application_photo_resources_v2 from anon;
revoke all on public.workflow_execution_photo_resources_v2 from anon;
revoke insert,update,delete,truncate,references,trigger
  on public.workflow_application_photo_resources_v2 from authenticated;
revoke insert,update,delete,truncate,references,trigger
  on public.workflow_execution_photo_resources_v2 from authenticated;
grant select on public.workflow_application_photo_resources_v2 to authenticated;
grant select on public.workflow_execution_photo_resources_v2 to authenticated;

create policy workflow_application_photo_resources_v2_read
on public.workflow_application_photo_resources_v2
for select to authenticated
using (public.workflow_can_read_definitions_v1(organization_id));

create policy workflow_execution_photo_resources_v2_read
on public.workflow_execution_photo_resources_v2
for select to authenticated
using (
  public.workflow_can_read_definitions_v1(organization_id)
  or exists(
    select 1
    from public.workflow_executions_v2 e
    where e.id=execution_id
      and e.assigned_user_id=auth.uid()
  )
);

create or replace function public.workflow_create_application_core_v1(
  p_definition_version_id uuid,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null
)
returns table(
  application_id uuid,
  status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public,pg_temp
as $
declare
  v_actor uuid:=auth.uid();
  v_definition_id uuid;
  v_org uuid;
  v_scope_type text;
  v_existing_id uuid;
  v_existing_version uuid;
  v_application_id uuid;
  v_created_at timestamptz;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if coalesce(auth.jwt()->>'aal','aal1') <> 'aal2' then
    raise exception 'aal2_required' using errcode='42501';
  end if;

  select wv.definition_id,wv.organization_id,wv.spec->>'scopeType'
  into v_definition_id,v_org,v_scope_type
  from public.workflow_definition_versions_v2 wv
  where wv.id=p_definition_version_id;

  if v_definition_id is null then
    raise exception 'workflow_version_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_org) then
    raise exception 'workflow_application_not_authorized' using errcode='42501';
  end if;

  if v_scope_type='organization' then
    if p_property_id is not null or p_room_id is not null or p_occupancy_id is not null then
      raise exception 'workflow_scope_target_invalid' using errcode='22023';
    end if;
  elsif v_scope_type='property' then
    if p_property_id is null or p_room_id is not null or p_occupancy_id is not null then
      raise exception 'workflow_property_required' using errcode='22023';
    end if;

    if not exists(
      select 1 from public.properties_v2 p
      where p.id=p_property_id
        and p.organization_id=v_org
        and p.archived_at is null
        and p.status<>'archived'
    ) then
      raise exception 'workflow_property_not_available' using errcode='22023';
    end if;
  elsif v_scope_type='room' then
    if p_property_id is null or p_room_id is null or p_occupancy_id is not null then
      raise exception 'workflow_room_required' using errcode='22023';
    end if;

    if not exists(
      select 1
      from public.rooms_v2 r
      join public.properties_v2 p on p.id=r.property_id
      where r.id=p_room_id
        and r.property_id=p_property_id
        and p.organization_id=v_org
        and p.archived_at is null
        and p.status<>'archived'
        and r.archived_at is null
        and r.status<>'archived'
    ) then
      raise exception 'workflow_room_not_available' using errcode='22023';
    end if;
  elsif v_scope_type='occupancy' then
    if p_property_id is null or p_room_id is not null or p_occupancy_id is null then
      raise exception 'workflow_occupancy_required' using errcode='22023';
    end if;

    if not exists(
      select 1
      from public.occupancies_v2 o
      join public.properties_v2 p on p.id=o.property_id
      where o.id=p_occupancy_id
        and o.property_id=p_property_id
        and o.organization_id=v_org
        and p.organization_id=v_org
        and p.archived_at is null
        and p.status<>'archived'
        and o.status='active'
        and o.starts_on<=current_date
        and (o.ends_on is null or o.ends_on>=current_date)
    ) then
      raise exception 'workflow_occupancy_not_available' using errcode='22023';
    end if;
  else
    raise exception 'workflow_scope_invalid' using errcode='22023';
  end if;

  select wa.id,wa.definition_version_id
  into v_existing_id,v_existing_version
  from public.workflow_applications_v2 wa
  where wa.definition_id=v_definition_id
    and wa.status='configured'
    and (
      (v_scope_type='organization' and wa.scope_type='organization' and wa.organization_id=v_org)
      or
      (v_scope_type='property' and wa.scope_type='property' and wa.property_id=p_property_id)
      or
      (v_scope_type='room' and wa.scope_type='room' and wa.room_id=p_room_id)
      or
      (v_scope_type='occupancy' and wa.scope_type='occupancy' and wa.occupancy_id=p_occupancy_id)
    )
  for update;

  if v_existing_id is not null then
    if v_existing_version=p_definition_version_id then
      select wa.created_at into v_created_at
      from public.workflow_applications_v2 wa
      where wa.id=v_existing_id;

      return query select v_existing_id,'configured'::text,v_created_at;
      return;
    end if;

    raise exception 'workflow_application_version_conflict' using errcode='55000';
  end if;

  insert into public.workflow_applications_v2(
    definition_id,definition_version_id,organization_id,scope_type,
    property_id,room_id,occupancy_id,status,created_by
  ) values (
    v_definition_id,p_definition_version_id,v_org,v_scope_type,
    p_property_id,p_room_id,p_occupancy_id,'configured',v_actor
  )
  returning id,workflow_applications_v2.created_at
  into v_application_id,v_created_at;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_org,v_actor,'workflow_application_created','workflow_application',
    v_application_id::text,'success',
    jsonb_build_object(
      'definition_id',v_definition_id,
      'definition_version_id',p_definition_version_id,
      'scope_type',v_scope_type,
      'property_id',p_property_id,
      'room_id',p_room_id,
      'occupancy_id',p_occupancy_id
    )
  );

  return query select v_application_id,'configured'::text,v_created_at;
end;
$;


revoke all on function public.workflow_create_application_core_v1(uuid,uuid,uuid,uuid)
  from public,anon,authenticated;

create or replace function public.create_workflow_application_v1(
  p_definition_version_id uuid,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null
)
returns table(
  application_id uuid,
  status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public,pg_temp
as $
declare
  v_photo_required boolean:=false;
begin
  select coalesce((wv.spec->'steps'->>'photo')::boolean,false)
  into v_photo_required
  from public.workflow_definition_versions_v2 wv
  where wv.id=p_definition_version_id;

  if v_photo_required then
    raise exception 'workflow_photo_application_requires_v2' using errcode='0A000';
  end if;

  return query
  select a.application_id,a.status,a.created_at
  from public.workflow_create_application_core_v1(
    p_definition_version_id,p_property_id,p_room_id,p_occupancy_id
  ) a;
end;
$;

revoke all on function public.create_workflow_application_v1(uuid,uuid,uuid,uuid) from public;
revoke execute on function public.create_workflow_application_v1(uuid,uuid,uuid,uuid) from anon;
grant execute on function public.create_workflow_application_v1(uuid,uuid,uuid,uuid) to authenticated;

create or replace function public.create_workflow_application_v2(
  p_definition_version_id uuid,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[]
)
returns table(
  application_id uuid,
  status text,
  created_at timestamptz,
  photo_resource_count integer
)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_org uuid;
  v_spec jsonb;
  v_photo_required boolean:=false;
  v_photo_count integer:=coalesce(cardinality(p_photo_pattern_ids),0);
  v_valid_count integer:=0;
  v_application_id uuid;
  v_status text;
  v_created_at timestamptz;
  v_existing_ids uuid[];
  v_executions integer:=0;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select wv.organization_id,wv.spec
  into v_org,v_spec
  from public.workflow_definition_versions_v2 wv
  where wv.id=p_definition_version_id;

  if v_org is null then
    raise exception 'workflow_version_not_found' using errcode='P0002';
  end if;

  v_photo_required:=coalesce((v_spec->'steps'->>'photo')::boolean,false);

  if not v_photo_required and v_photo_count>0 then
    raise exception 'workflow_photo_resources_not_expected' using errcode='22023';
  end if;

  if v_photo_required then
    if p_property_id is null then
      raise exception 'workflow_photo_step_requires_property' using errcode='22023';
    end if;
    if v_photo_count<1 or v_photo_count>20 then
      raise exception 'workflow_photo_resources_required' using errcode='22023';
    end if;
    if exists(select 1 from unnest(p_photo_pattern_ids) x where x is null) then
      raise exception 'workflow_photo_pattern_invalid' using errcode='22023';
    end if;
    if (select count(distinct x) from unnest(p_photo_pattern_ids) x)<>v_photo_count then
      raise exception 'workflow_photo_pattern_duplicate' using errcode='22023';
    end if;

    select count(*)
    into v_valid_count
    from public.photo_patterns_v2 p
    where p.id=any(p_photo_pattern_ids)
      and p.organization_id=v_org
      and p.property_id=p_property_id
      and p.active=true
      and p.retired_at is null
      and jsonb_typeof(p.contour_data)='object'
      and jsonb_typeof(p.contour_data->'strokes')='array'
      and jsonb_array_length(p.contour_data->'strokes')>0;

    if v_valid_count<>v_photo_count then
      raise exception 'workflow_photo_pattern_not_available' using errcode='22023';
    end if;
  end if;

  select a.application_id,a.status,a.created_at
  into v_application_id,v_status,v_created_at
  from public.workflow_create_application_core_v1(
    p_definition_version_id,
    p_property_id,
    p_room_id,
    p_occupancy_id
  ) a;

  select array_agg(r.pattern_id order by r.sort_order)
  into v_existing_ids
  from public.workflow_application_photo_resources_v2 r
  where r.application_id=v_application_id;

  if v_photo_required then
    if v_existing_ids is not null then
      if v_existing_ids is distinct from p_photo_pattern_ids then
        raise exception 'workflow_application_photo_resources_conflict' using errcode='55000';
      end if;
    else
      select count(*) into v_executions
      from public.workflow_executions_v2 e
      where e.application_id=v_application_id;

      if v_executions>0 then
        raise exception 'workflow_application_photo_resources_locked' using errcode='55000';
      end if;

      insert into public.workflow_application_photo_resources_v2(
        application_id,organization_id,property_id,pattern_id,sort_order,created_by
      )
      select
        v_application_id,v_org,p_property_id,u.pattern_id,u.ord::integer,v_actor
      from unnest(p_photo_pattern_ids) with ordinality as u(pattern_id,ord);

      insert into public.audit_log_v2(
        organization_id,actor_user_id,action,entity_type,entity_id,result,details
      ) values (
        v_org,v_actor,'workflow_application_photo_resources_bound','workflow_application',
        v_application_id::text,'success',
        jsonb_build_object('pattern_ids',to_jsonb(p_photo_pattern_ids))
      );
    end if;
  elsif v_existing_ids is not null then
    raise exception 'workflow_application_photo_resources_unexpected' using errcode='55000';
  end if;

  return query
  select v_application_id,v_status,v_created_at,v_photo_count;
end;
$$;

revoke all on function public.create_workflow_application_v2(uuid,uuid,uuid,uuid,uuid[]) from public;
revoke execute on function public.create_workflow_application_v2(uuid,uuid,uuid,uuid,uuid[]) from anon;
grant execute on function public.create_workflow_application_v2(uuid,uuid,uuid,uuid,uuid[]) to authenticated;

create or replace function public.workflow_snapshot_photo_resources_internal_v1(
  p_execution_id uuid
)
returns integer
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_execution public.workflow_executions_v2;
  v_photo_required boolean:=false;
  v_bound integer:=0;
  v_snapshot integer:=0;
begin
  select * into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id
  for update;

  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  v_photo_required:=coalesce((v_execution.spec_snapshot->'steps'->>'photo')::boolean,false);
  if not v_photo_required then
    return 0;
  end if;

  if v_execution.property_id is null then
    raise exception 'workflow_photo_step_requires_property' using errcode='55000';
  end if;

  select count(*) into v_bound
  from public.workflow_application_photo_resources_v2 ar
  where ar.application_id=v_execution.application_id;

  if v_bound<1 then
    raise exception 'workflow_photo_resources_required' using errcode='55000';
  end if;

  if exists(
    select 1
    from public.workflow_application_photo_resources_v2 ar
    left join public.photo_patterns_v2 p on p.id=ar.pattern_id
    where ar.application_id=v_execution.application_id
      and (
        p.id is null
        or p.organization_id<>v_execution.organization_id
        or p.property_id<>v_execution.property_id
        or p.active<>true
        or p.retired_at is not null
        or jsonb_typeof(p.contour_data)<>'object'
        or jsonb_typeof(p.contour_data->'strokes')<>'array'
        or jsonb_array_length(p.contour_data->'strokes')<1
      )
  ) then
    raise exception 'workflow_photo_pattern_not_available' using errcode='55000';
  end if;

  insert into public.workflow_execution_photo_resources_v2(
    execution_id,application_resource_id,organization_id,property_id,
    pattern_id,pattern_version,pattern_snapshot,sort_order,requires_accept
  )
  select
    v_execution.id,
    ar.id,
    ar.organization_id,
    ar.property_id,
    p.id,
    p.version,
    jsonb_build_object(
      'pattern_id',p.id,
      'version',p.version,
      'name',p.name,
      'target_type',p.target_type,
      'target_key',p.target_key,
      'reference_storage_path',p.reference_storage_path,
      'contour_data',p.contour_data
    ),
    ar.sort_order,
    coalesce((v_execution.spec_snapshot->'steps'->>'accept')::boolean,false)
  from public.workflow_application_photo_resources_v2 ar
  join public.photo_patterns_v2 p on p.id=ar.pattern_id
  where ar.application_id=v_execution.application_id
  on conflict(execution_id,application_resource_id) do nothing;

  select count(*) into v_snapshot
  from public.workflow_execution_photo_resources_v2 er
  where er.execution_id=v_execution.id;

  if v_snapshot<>v_bound then
    raise exception 'workflow_photo_snapshot_incomplete' using errcode='55000';
  end if;

  return v_snapshot;
end;
$$;

revoke all on function public.workflow_snapshot_photo_resources_internal_v1(uuid)
  from public,anon,authenticated;

create or replace function public.workflow_require_photo_snapshot_internal_v1(
  p_execution_id uuid
)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_execution public.workflow_executions_v2;
  v_photo_required boolean:=false;
begin
  select * into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id;

  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  v_photo_required:=coalesce((v_execution.spec_snapshot->'steps'->>'photo')::boolean,false);
  if v_photo_required and not exists(
    select 1
    from public.workflow_execution_photo_resources_v2 er
    where er.execution_id=v_execution.id
  ) then
    raise exception 'workflow_execution_photo_snapshot_missing' using errcode='55000';
  end if;
end;
$$;

revoke all on function public.workflow_require_photo_snapshot_internal_v1(uuid)
  from public,anon,authenticated;

create or replace function public.execute_workflow_application_now_v1(
  p_application_id uuid,
  p_idempotency_key text,
  p_assigned_user_id uuid default null
)
returns table(
  execution_id uuid,
  status text,
  assigned_user_id uuid,
  created_at timestamptz,
  created_new boolean
)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_definition_id uuid;
  v_version_id uuid;
  v_org uuid;
  v_scope_type text;
  v_property_id uuid;
  v_room_id uuid;
  v_occupancy_id uuid;
  v_application_status text;
  v_spec jsonb;
  v_assignment_type text;
  v_assigned_user uuid;
  v_execution_id uuid;
  v_execution_status text;
  v_execution_created_at timestamptz;
  v_key text:=nullif(btrim(p_idempotency_key),'');
  v_is_root boolean:=false;
  v_is_admin boolean:=false;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_idempotency_key_invalid' using errcode='22023';
  end if;

  select
    wa.definition_id,
    wa.definition_version_id,
    wa.organization_id,
    wa.scope_type,
    wa.property_id,
    wa.room_id,
    wa.occupancy_id,
    wa.status,
    wv.spec
  into
    v_definition_id,
    v_version_id,
    v_org,
    v_scope_type,
    v_property_id,
    v_room_id,
    v_occupancy_id,
    v_application_status,
    v_spec
  from public.workflow_applications_v2 wa
  join public.workflow_definition_versions_v2 wv
    on wv.id=wa.definition_version_id
   and wv.definition_id=wa.definition_id
   and wv.organization_id=wa.organization_id
  where wa.id=p_application_id
  for update of wa;

  if v_definition_id is null then
    raise exception 'workflow_application_not_found' using errcode='P0002';
  end if;

  if v_application_status<>'configured' then
    raise exception 'workflow_application_not_executable' using errcode='55000';
  end if;

  select exists(
    select 1 from public.user_roles ur
    where ur.user_id=v_actor
      and ur.role='root'
      and ur.revoked_at is null
  ) into v_is_root;

  select exists(
    select 1 from public.user_roles ur
    where ur.user_id=v_actor
      and ur.organization_id=v_org
      and ur.role='admin'
      and ur.revoked_at is null
  ) into v_is_admin;

  if not (v_is_root or v_is_admin) then
    raise exception 'workflow_execution_not_authorized' using errcode='42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_application_id::text||':execute:'||v_key,0)
  );

  select e.id,e.status,e.assigned_user_id,e.created_at
  into v_execution_id,v_execution_status,v_assigned_user,v_execution_created_at
  from public.workflow_executions_v2 e
  where e.application_id=p_application_id
    and e.idempotency_key=v_key;

  if v_execution_id is not null then
    perform public.workflow_require_photo_snapshot_internal_v1(v_execution_id);
    perform public.workflow_materialize_execution_task_internal_v1(v_execution_id,v_actor);
    return query
    select v_execution_id,v_execution_status,v_assigned_user,v_execution_created_at,false;
    return;
  end if;

  -- Revalidar el destino real en el momento de ejecutar.
  if v_scope_type='property' then
    if not exists(
      select 1 from public.properties_v2 p
      where p.id=v_property_id
        and p.organization_id=v_org
        and p.archived_at is null
        and p.status<>'archived'
    ) then
      raise exception 'workflow_execution_property_unavailable' using errcode='55000';
    end if;
  elsif v_scope_type='room' then
    if not exists(
      select 1
      from public.rooms_v2 r
      join public.properties_v2 p on p.id=r.property_id
      where r.id=v_room_id
        and r.property_id=v_property_id
        and p.organization_id=v_org
        and p.archived_at is null
        and p.status<>'archived'
        and r.archived_at is null
        and r.status<>'archived'
    ) then
      raise exception 'workflow_execution_room_unavailable' using errcode='55000';
    end if;
  elsif v_scope_type='occupancy' then
    if not exists(
      select 1
      from public.occupancies_v2 o
      join public.properties_v2 p on p.id=o.property_id
      where o.id=v_occupancy_id
        and o.organization_id=v_org
        and o.property_id=v_property_id
        and p.organization_id=v_org
        and p.archived_at is null
        and p.status<>'archived'
        and o.status='active'
        and o.starts_on<=current_date
        and (o.ends_on is null or o.ends_on>=current_date)
    ) then
      raise exception 'workflow_execution_occupancy_unavailable' using errcode='55000';
    end if;
  elsif v_scope_type<>'organization' then
    raise exception 'workflow_scope_invalid' using errcode='22023';
  end if;

  v_assignment_type:=nullif(v_spec->>'assignmentType','');

  if v_assignment_type='manual' then
    if p_assigned_user_id is null then
      raise exception 'workflow_manual_assignee_required' using errcode='22023';
    end if;

    if exists(
      select 1 from public.user_roles ur
      where ur.user_id=p_assigned_user_id
        and ur.role='root'
        and ur.revoked_at is null
    ) then
      v_assigned_user:=p_assigned_user_id;
    elsif exists(
      select 1 from public.user_roles ur
      where ur.user_id=p_assigned_user_id
        and ur.organization_id=v_org
        and ur.role='admin'
        and ur.revoked_at is null
    ) then
      v_assigned_user:=p_assigned_user_id;
    elsif exists(
      select 1 from public.user_roles ur
      where ur.user_id=p_assigned_user_id
        and ur.organization_id=v_org
        and ur.role='employee'
        and ur.revoked_at is null
    ) and (
      v_property_id is null
      or exists(
        select 1
        from public.property_staff_access_v3 a
        where a.property_id=v_property_id
          and a.employee_user_id=p_assigned_user_id
          and a.revoked_at is null
          and (a.valid_until is null or a.valid_until>now())
          and a.can_write=true
          and a.assignment_type in ('responsible','access')
      )
    ) then
      v_assigned_user:=p_assigned_user_id;
    else
      raise exception 'workflow_manual_assignee_not_eligible' using errcode='42501';
    end if;
  elsif v_assignment_type='property_responsible' then
    if p_assigned_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved' using errcode='22023';
    end if;

    if v_property_id is null then
      raise exception 'workflow_property_responsible_scope_required' using errcode='22023';
    end if;

    select a.employee_user_id
    into v_assigned_user
    from public.property_staff_access_v3 a
    join public.user_roles ur
      on ur.user_id=a.employee_user_id
     and ur.organization_id=v_org
     and ur.role in ('employee','admin')
     and ur.revoked_at is null
    where a.property_id=v_property_id
      and a.assignment_type='responsible'
      and a.revoked_at is null
      and (a.valid_until is null or a.valid_until>now())
      and a.can_write=true
    limit 1;

    if v_assigned_user is null then
      raise exception 'workflow_property_responsible_unavailable' using errcode='55000';
    end if;
  elsif v_assignment_type in ('fixed_person','role','active_occupants_rotation') then
    raise exception 'workflow_assignment_not_supported' using errcode='0A000';
  else
    raise exception 'workflow_assignment_invalid' using errcode='22023';
  end if;

  insert into public.workflow_executions_v2 as new_execution(
    application_id,definition_id,definition_version_id,organization_id,
    scope_type,property_id,room_id,occupancy_id,
    trigger_kind,idempotency_key,assignment_type,assigned_user_id,
    status,spec_snapshot,created_by
  ) values (
    p_application_id,v_definition_id,v_version_id,v_org,
    v_scope_type,v_property_id,v_room_id,v_occupancy_id,
    'manual_now',v_key,v_assignment_type,v_assigned_user,
    'pending',v_spec,v_actor
  )
  returning new_execution.id,new_execution.status,new_execution.created_at
  into v_execution_id,v_execution_status,v_execution_created_at;

  perform public.workflow_snapshot_photo_resources_internal_v1(v_execution_id);

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution_id,v_org,'created',null,'pending',v_actor,
    jsonb_build_object(
      'trigger_kind','manual_now',
      'assignment_type',v_assignment_type,
      'assigned_user_id',v_assigned_user,
      'application_id',p_application_id,
      'definition_version_id',v_version_id
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_org,v_actor,'workflow_execution_created','workflow_execution',
    v_execution_id::text,'success',
    jsonb_build_object(
      'application_id',p_application_id,
      'definition_id',v_definition_id,
      'definition_version_id',v_version_id,
      'scope_type',v_scope_type,
      'property_id',v_property_id,
      'room_id',v_room_id,
      'occupancy_id',v_occupancy_id,
      'assignment_type',v_assignment_type,
      'assigned_user_id',v_assigned_user,
      'idempotency_key',v_key
    )
  );

  perform public.workflow_materialize_execution_task_internal_v1(v_execution_id,v_actor);

  return query
  select v_execution_id,v_execution_status,v_assigned_user,v_execution_created_at,true;
end;
$$;



revoke all on function public.execute_workflow_application_now_v1(uuid,text,uuid) from public;
revoke execute on function public.execute_workflow_application_now_v1(uuid,text,uuid) from anon;
grant execute on function public.execute_workflow_application_now_v1(uuid,text,uuid) to authenticated;

create unique index workflow_execution_events_v2_photo_request_uq
  on public.workflow_execution_events_v2(
    execution_id,
    ((details->>'request_key'))
  )
  where event_type='photo_evidence_submitted'
    and details ? 'request_key';

create or replace function public.start_workflow_photo_verification_v1(
  p_execution_photo_resource_id uuid
)
returns table(
  photo_resource_id uuid,
  run_id uuid,
  organization_id uuid,
  property_id uuid,
  room_id uuid,
  pattern_id uuid,
  pattern_version integer,
  created_new boolean
)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_resource public.workflow_execution_photo_resources_v2;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_run public.photo_verification_runs_v2;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select * into v_resource
  from public.workflow_execution_photo_resources_v2
  where id=p_execution_photo_resource_id
  for update;

  if v_resource.id is null then
    raise exception 'workflow_photo_resource_not_found' using errcode='P0002';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_resource.execution_id
  for update;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id
  for update;

  if v_execution.id is null or v_task.id is null then
    raise exception 'workflow_photo_execution_not_ready' using errcode='55000';
  end if;

  if v_actor is distinct from v_execution.assigned_user_id
    or v_actor is distinct from v_task.assigned_user_id then
    raise exception 'workflow_photo_actor_forbidden' using errcode='42501';
  end if;

  if v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_state_mismatch' using errcode='55000';
  end if;

  if v_resource.status='submitted' then
    raise exception 'workflow_photo_already_submitted' using errcode='55000';
  end if;

  if v_resource.requires_accept then
    if v_execution.status<>'active' then
      raise exception 'workflow_photo_accept_required' using errcode='55000';
    end if;
  else
    if v_execution.status='pending' then
      update public.tenant_tasks_v2
      set status='active',updated_at=now()
      where id=v_task.id
      returning * into v_task;

      update public.workflow_executions_v2
      set status='active',updated_at=now(),started_at=coalesce(started_at,now())
      where id=v_execution.id
      returning * into v_execution;

      insert into public.tenant_task_history_v2(
        task_id,action_key,action_label,from_status,to_status,note,actor_user_id
      ) values (
        v_task.id,'start_photo','Iniciar evidencia fotográfica',
        'pending','active',null,v_actor
      );

      insert into public.workflow_execution_events_v2(
        execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
      ) values (
        v_execution.id,v_execution.organization_id,'photo_step_started',
        'pending','active',v_actor,
        jsonb_build_object('task_id',v_task.id,'photo_resource_id',v_resource.id)
      );
    elsif v_execution.status<>'active' then
      raise exception 'workflow_photo_execution_not_active' using errcode='55000';
    end if;
  end if;

  if v_resource.photo_run_id is not null then
    select * into v_run
    from public.photo_verification_runs_v2
    where id=v_resource.photo_run_id;

    if v_run.id is null then
      raise exception 'workflow_photo_run_missing' using errcode='55000';
    end if;

    if v_run.status='capturing' then
      return query
      select v_resource.id,v_run.id,v_run.organization_id,v_run.property_id,v_run.room_id,
             v_resource.pattern_id,v_resource.pattern_version,false;
      return;
    end if;

    raise exception 'workflow_photo_run_state_invalid' using errcode='55000';
  end if;

  insert into public.photo_verification_runs_v2(
    organization_id,property_id,room_id,actor_user_id,
    source_type,source_id,verification_mode,status,purpose
  ) values (
    v_execution.organization_id,
    v_execution.property_id,
    v_execution.room_id,
    v_actor,
    'workflow_execution',
    v_execution.id,
    'manual',
    'capturing',
    'general'
  )
  returning * into v_run;

  update public.workflow_execution_photo_resources_v2
  set status='capturing',
      photo_run_id=v_run.id,
      started_at=coalesce(started_at,now())
  where id=v_resource.id
  returning * into v_resource;

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,v_execution.organization_id,'photo_capture_started',
    v_execution.status,v_execution.status,v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'photo_resource_id',v_resource.id,
      'photo_run_id',v_run.id,
      'pattern_id',v_resource.pattern_id
    )
  );

  return query
  select v_resource.id,v_run.id,v_run.organization_id,v_run.property_id,v_run.room_id,
         v_resource.pattern_id,v_resource.pattern_version,true;
end;
$$;

revoke all on function public.start_workflow_photo_verification_v1(uuid) from public;
revoke execute on function public.start_workflow_photo_verification_v1(uuid) from anon;
grant execute on function public.start_workflow_photo_verification_v1(uuid) to authenticated;

create or replace function public.submit_workflow_photo_verification_v1(
  p_run_id uuid,
  p_item_id uuid,
  p_request_key text
)
returns table(
  photo_resource_id uuid,
  photo_resource_status text,
  all_photos_complete boolean,
  task_status text,
  execution_status text,
  applied_new boolean
)
language plpgsql
security definer
set search_path=public,storage,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_run public.photo_verification_runs_v2;
  v_item public.photo_verification_items_v2;
  v_resource public.workflow_execution_photo_resources_v2;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_previous_event public.workflow_execution_events_v2;
  v_expected_path text;
  v_all_complete boolean:=false;
  v_other_steps boolean:=false;
  v_close_type text;
  v_target_status text;
  v_from_status text;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_photo_request_key_invalid' using errcode='22023';
  end if;

  select * into v_run
  from public.photo_verification_runs_v2
  where id=p_run_id
  for update;

  if v_run.id is null
    or v_run.source_type<>'workflow_execution'
    or v_run.source_id is null then
    raise exception 'workflow_photo_run_not_found' using errcode='P0002';
  end if;

  select * into v_resource
  from public.workflow_execution_photo_resources_v2
  where photo_run_id=v_run.id
  for update;

  if v_resource.id is null then
    raise exception 'workflow_photo_resource_not_found' using errcode='55000';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_resource.execution_id
  for update;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id
  for update;

  if v_actor is distinct from v_run.actor_user_id
    or v_actor is distinct from v_execution.assigned_user_id
    or v_actor is distinct from v_task.assigned_user_id then
    raise exception 'workflow_photo_actor_forbidden' using errcode='42501';
  end if;

  if v_run.source_id is distinct from v_execution.id
    or v_run.organization_id<>v_execution.organization_id
    or v_run.property_id<>v_execution.property_id
    or v_resource.pattern_id is null then
    raise exception 'workflow_photo_identity_mismatch' using errcode='55000';
  end if;

  if v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_state_mismatch' using errcode='55000';
  end if;

  v_from_status:=v_execution.status;

  select * into v_previous_event
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='photo_evidence_submitted'
    and ev.details->>'request_key'=v_key
  order by ev.id
  limit 1;

  if v_previous_event.id is not null then
    if v_previous_event.details->>'photo_resource_id' is distinct from v_resource.id::text
      or v_previous_event.details->>'photo_run_id' is distinct from p_run_id::text
      or v_previous_event.details->>'item_id' is distinct from p_item_id::text then
      raise exception 'workflow_photo_request_key_conflict' using errcode='55000';
    end if;

    select not exists(
      select 1 from public.workflow_execution_photo_resources_v2 er
      where er.execution_id=v_execution.id and er.status<>'submitted'
    ) into v_all_complete;

    return query
    select v_resource.id,v_resource.status,v_all_complete,v_task.status,v_execution.status,false;
    return;
  end if;

  if v_run.status='submitted' and v_resource.status='submitted' then
    select not exists(
      select 1 from public.workflow_execution_photo_resources_v2 er
      where er.execution_id=v_execution.id and er.status<>'submitted'
    ) into v_all_complete;

    return query
    select v_resource.id,v_resource.status,v_all_complete,v_task.status,v_execution.status,false;
    return;
  end if;

  if v_run.status<>'capturing' or v_resource.status<>'capturing' then
    raise exception 'workflow_photo_not_capturing' using errcode='55000';
  end if;

  select * into v_item
  from public.photo_verification_items_v2
  where id=p_item_id
    and run_id=v_run.id;

  if v_item.id is null
    or v_item.pattern_id is distinct from v_resource.pattern_id then
    raise exception 'workflow_photo_item_invalid' using errcode='22023';
  end if;

  v_expected_path:=v_run.organization_id::text||'/'||v_run.id::text||'/'||v_item.id::text||'.jpg';
  if v_item.storage_path is distinct from v_expected_path then
    raise exception 'workflow_photo_storage_path_invalid' using errcode='55000';
  end if;

  if not exists(
    select 1
    from storage.objects o
    where o.bucket_id='photo-verification'
      and o.name=v_expected_path
      and o.owner_id=v_actor::text
  ) then
    raise exception 'workflow_photo_object_missing' using errcode='55000';
  end if;

  update public.photo_verification_runs_v2
  set status='submitted',submitted_at=coalesce(submitted_at,now())
  where id=v_run.id
  returning * into v_run;

  update public.workflow_execution_photo_resources_v2
  set status='submitted',completed_at=coalesce(completed_at,now())
  where id=v_resource.id
  returning * into v_resource;

  select not exists(
    select 1
    from public.workflow_execution_photo_resources_v2 er
    where er.execution_id=v_execution.id
      and er.status<>'submitted'
  ) into v_all_complete;

  v_target_status:=v_execution.status;

  if v_all_complete then
    v_other_steps:=
      coalesce((v_execution.spec_snapshot->'steps'->>'checklist')::boolean,false)
      or coalesce((v_execution.spec_snapshot->'steps'->>'document')::boolean,false);
    v_close_type:=nullif(v_execution.spec_snapshot->>'closeType','');

    if not v_other_steps then
      if v_close_type='auto' then
        v_target_status:='completed';
      elsif v_close_type='human_review' then
        v_target_status:='waiting_review';
      end if;
    end if;
  end if;

  if v_target_status is distinct from v_execution.status then
    insert into public.tenant_task_history_v2(
      task_id,action_key,action_label,from_status,to_status,note,actor_user_id
    ) values (
      v_task.id,
      'photo_complete',
      case
        when v_target_status='completed' then 'Evidencia fotográfica completada'
        when v_target_status='waiting_review' then 'Evidencia fotográfica enviada a revisión'
        else 'Evidencia fotográfica'
      end,
      v_task.status,
      v_target_status,
      null,
      v_actor
    );

    update public.tenant_tasks_v2
    set status=v_target_status,updated_at=now()
    where id=v_task.id
    returning * into v_task;

    update public.workflow_executions_v2 as updated_execution
    set status=v_target_status,
        updated_at=now(),
        started_at=coalesce(updated_execution.started_at,now()),
        completed_at=case
          when v_target_status='completed' then coalesce(updated_execution.completed_at,now())
          else updated_execution.completed_at
        end
    where id=v_execution.id
    returning * into v_execution;
  end if;

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,
    v_execution.organization_id,
    'photo_evidence_submitted',
    v_from_status,
    v_execution.status,
    v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'photo_resource_id',v_resource.id,
      'photo_run_id',v_run.id,
      'item_id',v_item.id,
      'pattern_id',v_resource.pattern_id,
      'request_key',v_key,
      'all_photos_complete',v_all_complete
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,
    v_actor,
    'workflow_photo_evidence_submitted',
    'workflow_execution',
    v_execution.id::text,
    'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'photo_resource_id',v_resource.id,
      'photo_run_id',v_run.id,
      'item_id',v_item.id,
      'pattern_id',v_resource.pattern_id,
      'all_photos_complete',v_all_complete,
      'task_status',v_task.status,
      'execution_status',v_execution.status
    )
  );

  return query
  select v_resource.id,v_resource.status,v_all_complete,v_task.status,v_execution.status,true;
end;
$$;

revoke all on function public.submit_workflow_photo_verification_v1(uuid,uuid,text) from public;
revoke execute on function public.submit_workflow_photo_verification_v1(uuid,uuid,text) from anon;
grant execute on function public.submit_workflow_photo_verification_v1(uuid,uuid,text) to authenticated;

create or replace function private.photo_pattern_usage_v2(p_pattern_id uuid)
returns jsonb
language sql
security definer
set search_path=public,private,pg_temp
as $$
with u as (
  select 'cleaning'::text kind, r.cleaning_task_id ref_id, t.status ref_status, t.task_date::text ref_label
  from public.cleaning_photo_requests_v2 r
  join public.cleaning_tasks_v2 t on t.id=r.cleaning_task_id
  where r.pattern_id=p_pattern_id

  union all
  select 'verification', i.run_id, coalesce(v.status,'unknown'), coalesce(v.started_at::date::text,'')
  from public.photo_verification_items_v2 i
  join public.photo_verification_runs_v2 v on v.id=i.run_id
  where i.pattern_id=p_pattern_id

  union all
  select 'random_request', r.id, coalesce(r.status,'unknown'), coalesce(r.requested_at::date::text,'')
  from public.random_photo_requests_v2 r
  where r.pattern_id=p_pattern_id

  union all
  select 'workflow_application', ar.application_id, a.status, coalesce(a.created_at::date::text,'')
  from public.workflow_application_photo_resources_v2 ar
  join public.workflow_applications_v2 a on a.id=ar.application_id
  where ar.pattern_id=p_pattern_id

  union all
  select 'workflow_execution', er.execution_id, e.status, coalesce(e.created_at::date::text,'')
  from public.workflow_execution_photo_resources_v2 er
  join public.workflow_executions_v2 e on e.id=er.execution_id
  where er.pattern_id=p_pattern_id
)
select jsonb_build_object(
 'used',exists(select 1 from u),
 'active_use',exists(select 1 from u where
   (kind='cleaning' and ref_status in ('pending','accepted','in_progress','submitted'))
   or (kind='verification' and ref_status in ('capturing','submitted','pending'))
   or (kind='random_request' and ref_status not in ('completed','cancelled','expired'))
   or (kind='workflow_application' and ref_status='configured')
   or (kind='workflow_execution' and ref_status in ('pending','active','waiting_review'))),
 'uses',coalesce((
   select jsonb_agg(jsonb_build_object(
     'kind',kind,'id',ref_id,'status',ref_status,'label',ref_label
   ))
   from u
 ),'[]'::jsonb)
);
$$;

comment on table public.workflow_application_photo_resources_v2 is
  'Vincula una aplicación concreta con uno o más patrones fotográficos reales del mismo piso.';
comment on table public.workflow_execution_photo_resources_v2 is
  'Snapshot reproducible de los patrones requeridos por una ejecución, incluida silueta/version efectiva.';
comment on function public.create_workflow_application_v2(uuid,uuid,uuid,uuid,uuid[]) is
  'Crea/reutiliza una aplicación y enlaza atómicamente los patrones requeridos cuando la receta contiene paso foto.';
comment on function public.start_workflow_photo_verification_v1(uuid) is
  'Inicia o recupera idempotentemente el run de captura de un recurso fotográfico de workflow para el asignado.';
comment on function public.submit_workflow_photo_verification_v1(uuid,uuid,text) is
  'Valida objeto privado y finaliza foto + recurso + transición de tarea/ejecución en una única transacción.';


-- Mantener Factory Reset compatible con las nuevas FKs de recursos fotográficos.
-- GestionPisos · Factory reset · incluir datos operativos del motor de workflows
-- Mantiene la semántica de 20260917194500 y añade explícitamente las nuevas tablas.

create or replace function public.factory_reset_test_data_service(
  p_actor_user_id uuid,
  p_operator_user_id uuid,
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reset_at timestamptz := now();
  v_profile_organization_id uuid;
  v_active_organization_count integer := 0;
begin
  perform set_config('lock_timeout', '5s', true);
  perform set_config('statement_timeout', '30s', true);

  if p_actor_user_id is null or p_operator_user_id is null or p_organization_id is null then
    raise exception 'factory_reset_invalid_protected_identity';
  end if;

  if p_actor_user_id = p_operator_user_id then
    raise exception 'factory_reset_operator_must_be_independent';
  end if;

  -- ROOT is intentionally allowed to be global (organization_id = null).
  -- This matches get_effective_organization_id(): an active profile wins;
  -- otherwise a global ROOT may operate only when exactly one organization is active.
  if not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = p_actor_user_id
      and lower(ur.role::text) = 'root'
      and ur.revoked_at is null
  ) then
    raise exception 'factory_reset_root_required';
  end if;

  if not exists (
    select 1
    from public.organizations o
    where o.id = p_organization_id
      and lower(o.status::text) = 'active'
  ) then
    raise exception 'factory_reset_active_organization_required';
  end if;

  select p.organization_id
    into v_profile_organization_id
  from public.profiles p
  where p.user_id = p_actor_user_id
    and lower(p.status::text) = 'active'
  limit 1;

  if v_profile_organization_id is not null then
    if v_profile_organization_id <> p_organization_id then
      raise exception 'factory_reset_root_organization_mismatch';
    end if;
  else
    select count(*)
      into v_active_organization_count
    from public.organizations o
    where lower(o.status::text) = 'active';

    if v_active_organization_count <> 1 then
      raise exception 'factory_reset_root_organization_ambiguous';
    end if;
  end if;

  if not exists (
    select 1
    from public.platform_operators po
    where po.user_id = p_operator_user_id
      and po.active = true
      and po.can_recover_root = true
  ) then
    raise exception 'factory_reset_root_recovery_operator_required';
  end if;

  truncate table
    public.access_requests,
    public.admin_capability_holders,
    public.admin_capability_requests,
    public.audit_log_v2,
    public.broadcasts_v2,
    public.claims_v2,
    public.cleaning_audit_items_v2,
    public.cleaning_audit_policies_v2,
    public.cleaning_audits_v2,
    public.cleaning_debts_v2,
    public.cleaning_photo_request_policies_v2,
    public.cleaning_photo_requests_v2,
    public.cleaning_plans_v2,
    public.cleaning_swap_requests_v2,
    public.cleaning_tasks_v2,
    public.external_account_onboarding,
    public.incident_evidence_v2,
    public.incident_updates_v2,
    public.incidents_v2,
    public.internal_staff_onboarding,
    public.internal_staff_onboarding_access_snapshot,
    public.notifications_v2,
    public.occupancies_v2,
    public.owners,
    public.payment_obligations_v2,
    public.photo_patterns_v2,
    public.photo_verification_items_v2,
    public.photo_verification_runs_v2,
    public.properties,
    public.properties_v2,
    public.property_qr_tokens,
    public.property_staff_access_v2,
    public.property_staff_access_v3,
    public.property_staff_assignments,
    public.random_photo_requests_v2,
    public.reminder_rules_v2,
    public.rooms,
    public.rooms_v2,
    public.tenancies,
    public.tenant_documents_v2,
    public.tenant_privacy_events_v2,
    public.tenant_task_actions_v2,
    public.tenant_task_history_v2,
    public.tenant_tasks_v2,
    public.tenants_v2,
    public.verification_policies_v2,
    public.workflow_execution_photo_resources_v2,
    public.workflow_application_photo_resources_v2,
    public.workflow_execution_events_v2,
    public.workflow_executions_v2,
    public.workflow_applications_v2,
    public.workflow_definition_versions_v2,
    public.workflow_definitions_v2
  restart identity;

  delete from public.platform_operators
  where user_id <> p_operator_user_id;

  delete from public.profiles
  where user_id <> p_actor_user_id;

  delete from public.user_roles
  where user_id <> p_actor_user_id;

  delete from public.organizations
  where id <> p_organization_id;

  insert into public.audit_log_v2 (
    organization_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    result,
    details
  ) values (
    p_organization_id,
    p_actor_user_id,
    'factory_reset_completed',
    'organization',
    p_organization_id::text,
    'success',
    jsonb_build_object(
      'mode', 'test_factory_reset',
      'preserved_root_user_id', p_actor_user_id,
      'preserved_operator_user_id', p_operator_user_id,
      'historical_audit_cleared', true,
      'static_workflow_templates_preserved', true,
      'completed_at', v_reset_at
    )
  );

  return jsonb_build_object(
    'ok', true,
    'completed_at', v_reset_at,
    'preserved_root_user_id', p_actor_user_id,
    'preserved_operator_user_id', p_operator_user_id,
    'preserved_organization_id', p_organization_id
  );
end;
$$;

revoke all on function public.factory_reset_test_data_service(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.factory_reset_test_data_service(uuid, uuid, uuid) to service_role;

comment on function public.factory_reset_test_data_service(uuid, uuid, uuid) is
  'Service-role-only destructive test reset. Supports global ROOT using the same effective-organization rule as get_effective_organization_id; preserves ROOT, one ROOT-recovery operator, the active organization and static task templates while clearing workflow definitions, applications, executions, photo-resource bindings, events and materialized tasks.';

