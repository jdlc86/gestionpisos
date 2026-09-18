-- GestionPisos · Flujos de Trabajo · publicación inmutable + aplicaciones concretas
-- Riesgo R3: nuevas operaciones administrativas, RLS y vinculación de ámbito real.
-- Este incremento NO crea ejecuciones, tareas ni recurrencias automáticas.

alter table public.workflow_definition_versions_v2
  add constraint workflow_definition_versions_v2_identity_unique
  unique (id, definition_id, organization_id);

create table public.workflow_applications_v2 (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null references public.workflow_definitions_v2(id) on delete restrict,
  definition_version_id uuid not null,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  scope_type text not null check (scope_type in ('organization','property','room','occupancy')),
  property_id uuid references public.properties_v2(id) on delete restrict,
  room_id uuid references public.rooms_v2(id) on delete restrict,
  occupancy_id uuid references public.occupancies_v2(id) on delete restrict,
  status text not null default 'configured' check (status in ('configured','archived')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint workflow_applications_v2_version_identity_fkey
    foreign key (definition_version_id, definition_id, organization_id)
    references public.workflow_definition_versions_v2(id, definition_id, organization_id)
    on delete restrict,
  constraint workflow_applications_v2_scope_shape_check check (
    (scope_type='organization' and property_id is null and room_id is null and occupancy_id is null)
    or
    (scope_type='property' and property_id is not null and room_id is null and occupancy_id is null)
    or
    (scope_type='room' and property_id is not null and room_id is not null and occupancy_id is null)
    or
    (scope_type='occupancy' and property_id is not null and room_id is null and occupancy_id is not null)
  ),
  constraint workflow_applications_v2_archive_shape_check check (
    (status='archived') = (archived_at is not null)
  )
);

create unique index workflow_applications_v2_current_org_uq
  on public.workflow_applications_v2(definition_id, organization_id)
  where status='configured' and scope_type='organization';

create unique index workflow_applications_v2_current_property_uq
  on public.workflow_applications_v2(definition_id, property_id)
  where status='configured' and scope_type='property';

create unique index workflow_applications_v2_current_room_uq
  on public.workflow_applications_v2(definition_id, room_id)
  where status='configured' and scope_type='room';

create unique index workflow_applications_v2_current_occupancy_uq
  on public.workflow_applications_v2(definition_id, occupancy_id)
  where status='configured' and scope_type='occupancy';

create index workflow_applications_v2_org_definition_idx
  on public.workflow_applications_v2(organization_id, definition_id, status, created_at desc);

alter table public.workflow_applications_v2 enable row level security;

revoke all on public.workflow_applications_v2 from anon;
revoke insert, update, delete, truncate, references, trigger on public.workflow_applications_v2 from authenticated;
grant select on public.workflow_applications_v2 to authenticated;

create policy workflow_applications_v2_read_authorized
on public.workflow_applications_v2
for select
to authenticated
using (public.workflow_can_read_definitions_v1(organization_id));

create or replace function public.workflow_can_manage_v1(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select auth.uid() is not null
    and (
      exists (
        select 1
        from public.user_roles ur
        where ur.user_id=auth.uid()
          and ur.role='root'
          and ur.revoked_at is null
      )
      or exists (
        select 1
        from public.user_roles ur
        where ur.user_id=auth.uid()
          and ur.organization_id=p_organization_id
          and ur.role='admin'
          and ur.revoked_at is null
      )
    );
$$;

revoke all on function public.workflow_can_manage_v1(uuid) from public;
revoke execute on function public.workflow_can_manage_v1(uuid) from anon;
grant execute on function public.workflow_can_manage_v1(uuid) to authenticated;

create or replace function public.publish_workflow_definition_v1(
  p_definition_id uuid,
  p_expected_revision bigint default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  published_at timestamptz
)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_org uuid;
  v_status text;
  v_revision bigint;
  v_complete boolean;
  v_spec jsonb;
  v_scope_type text;
  v_version integer;
  v_version_id uuid;
  v_published_at timestamptz;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if coalesce(auth.jwt()->>'aal','aal1') <> 'aal2' then
    raise exception 'aal2_required' using errcode='42501';
  end if;

  select wd.organization_id,wd.status,wd.revision,wd.authoring_complete,wd.draft_spec,wd.scope_type
  into v_org,v_status,v_revision,v_complete,v_spec,v_scope_type
  from public.workflow_definitions_v2 wd
  where wd.id=p_definition_id
  for update;

  if v_org is null then
    raise exception 'workflow_definition_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_org) then
    raise exception 'workflow_publish_not_authorized' using errcode='42501';
  end if;

  if p_expected_revision is not null and p_expected_revision<>v_revision then
    raise exception 'workflow_draft_conflict' using errcode='40001';
  end if;

  if v_status='published' then
    select wv.id,wv.version,wv.published_at
    into v_version_id,v_version,v_published_at
    from public.workflow_definition_versions_v2 wv
    where wv.definition_id=p_definition_id
      and wv.organization_id=v_org
    order by wv.version desc
    limit 1;

    if v_version_id is null then
      raise exception 'workflow_published_version_missing';
    end if;

    return query select p_definition_id,v_version_id,v_version,v_published_at;
    return;
  end if;

  if v_status<>'draft' then
    raise exception 'workflow_definition_not_publishable' using errcode='55000';
  end if;

  if not v_complete then
    raise exception 'workflow_authoring_incomplete' using errcode='22023';
  end if;

  if v_scope_type is null or v_scope_type not in ('organization','property','room','occupancy') then
    raise exception 'workflow_scope_invalid' using errcode='22023';
  end if;

  select coalesce(max(wv.version),0)+1
  into v_version
  from public.workflow_definition_versions_v2 wv
  where wv.definition_id=p_definition_id;

  insert into public.workflow_definition_versions_v2(
    definition_id,organization_id,version,spec,published_by
  ) values (
    p_definition_id,
    v_org,
    v_version,
    v_spec || jsonb_build_object('definitionRevision',v_revision),
    v_actor
  )
  returning id,workflow_definition_versions_v2.published_at
  into v_version_id,v_published_at;

  update public.workflow_definitions_v2
  set status='published',
      updated_by=v_actor,
      updated_at=now()
  where id=p_definition_id;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_org,v_actor,'workflow_definition_published','workflow_definition',
    p_definition_id::text,'success',
    jsonb_build_object(
      'version_id',v_version_id,
      'version',v_version,
      'definition_revision',v_revision,
      'scope_type',v_scope_type
    )
  );

  return query select p_definition_id,v_version_id,v_version,v_published_at;
end;
$$;

revoke all on function public.publish_workflow_definition_v1(uuid,bigint) from public;
revoke execute on function public.publish_workflow_definition_v1(uuid,bigint) from anon;
grant execute on function public.publish_workflow_definition_v1(uuid,bigint) to authenticated;

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
as $$
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
$$;

revoke all on function public.create_workflow_application_v1(uuid,uuid,uuid,uuid) from public;
revoke execute on function public.create_workflow_application_v1(uuid,uuid,uuid,uuid) from anon;
grant execute on function public.create_workflow_application_v1(uuid,uuid,uuid,uuid) to authenticated;

create or replace function public.archive_workflow_application_v1(
  p_application_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_org uuid;
  v_status text;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if coalesce(auth.jwt()->>'aal','aal1') <> 'aal2' then
    raise exception 'aal2_required' using errcode='42501';
  end if;

  select wa.organization_id,wa.status
  into v_org,v_status
  from public.workflow_applications_v2 wa
  where wa.id=p_application_id
  for update;

  if v_org is null then
    raise exception 'workflow_application_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_org) then
    raise exception 'workflow_application_not_authorized' using errcode='42501';
  end if;

  if v_status='archived' then
    return true;
  end if;

  update public.workflow_applications_v2
  set status='archived',archived_at=now(),updated_at=now()
  where id=p_application_id;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_org,v_actor,'workflow_application_archived','workflow_application',
    p_application_id::text,'success','{}'::jsonb
  );

  return true;
end;
$$;

revoke all on function public.archive_workflow_application_v1(uuid) from public;
revoke execute on function public.archive_workflow_application_v1(uuid) from anon;
grant execute on function public.archive_workflow_application_v1(uuid) to authenticated;

comment on table public.workflow_applications_v2 is
  'Vincula una versión publicada de una receta con una entidad real de su ámbito. Configurada no significa activa ni ejecutable.';
comment on function public.publish_workflow_definition_v1(uuid,bigint) is
  'Publica de forma inmutable la receta lógica. No selecciona piso/habitación/ocupación y no crea ejecuciones.';
comment on function public.create_workflow_application_v1(uuid,uuid,uuid,uuid) is
  'Aplica una versión publicada a una entidad real validada server-side. No activa recurrencias ni crea tareas.';
