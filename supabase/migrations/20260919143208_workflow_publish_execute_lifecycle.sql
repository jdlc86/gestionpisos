-- GestionPisos · Flujos · ciclo Publicar / Ejecutar y frontera historica
-- 2026-09-19
--
-- Regla funcional:
--   * una creacion nueva no persiste borradores parciales;
--   * Publicar crea definicion + version + destino, sin tarea;
--   * Ejecutar hace la misma publicacion y ademas crea una ejecucion/tarea atomica;
--   * mientras una definicion no tenga ejecuciones puede editarse en sitio o eliminarse;
--   * desde la primera ejecucion, las ediciones futuras usan versiones y solo se permite archivar.
--
-- No cambia RLS de tablas ni expone escritura directa al cliente. Todas las mutaciones
-- siguen pasando por RPC SECURITY DEFINER con auth.uid(), AAL2 y workflow_can_manage_v1.

alter table public.workflow_definitions_v2
  add column if not exists creation_request_key text;

create unique index if not exists workflow_definitions_v2_creation_request_uq
  on public.workflow_definitions_v2 (creation_request_key)
  where creation_request_key is not null;

alter table public.workflow_definitions_v2
  drop constraint if exists workflow_definitions_v2_creation_request_key_check;

alter table public.workflow_definitions_v2
  add constraint workflow_definitions_v2_creation_request_key_check
  check (
    creation_request_key is null
    or char_length(btrim(creation_request_key)) between 1 and 200
  );

create or replace function public.publish_workflow_ready_v1(
  p_spec jsonb,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_execute boolean default false,
  p_request_key text default null,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  published_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_request_key text := nullif(btrim(p_request_key),'');
  v_existing_definition public.workflow_definitions_v2;
  v_existing_version public.workflow_definition_versions_v2;
  v_existing_application public.workflow_applications_v2;
  v_draft record;
  v_published record;
  v_application record;
  v_execution_id uuid;
  v_execution_status text;
  v_execution_assigned_user_id uuid;
  v_existing_photo_ids uuid[];
  v_scope text;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if coalesce(auth.jwt()->>'aal','aal1') <> 'aal2' then
    raise exception 'aal2_required' using errcode='42501';
  end if;

  if v_request_key is null or char_length(v_request_key)>200 then
    raise exception 'workflow_request_key_invalid' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('workflow-ready:'||v_request_key,0));

  select wd.* into v_existing_definition
  from public.workflow_definitions_v2 wd
  where wd.creation_request_key=v_request_key
  for update;

  if v_existing_definition.id is not null then
    if v_existing_definition.created_by<>v_actor then
      raise exception 'workflow_creation_request_conflict' using errcode='42501';
    end if;

    select wv.* into v_existing_version
    from public.workflow_definition_versions_v2 wv
    where wv.definition_id=v_existing_definition.id
      and wv.organization_id=v_existing_definition.organization_id
    order by wv.version desc
    limit 1;

    if v_existing_version.id is null then
      raise exception 'workflow_creation_receipt_invalid' using errcode='55000';
    end if;

    select wa.* into v_existing_application
    from public.workflow_applications_v2 wa
    where wa.definition_id=v_existing_definition.id
      and wa.definition_version_id=v_existing_version.id
      and wa.status='configured'
    order by wa.created_at desc
    limit 1;

    if v_existing_application.id is null then
      raise exception 'workflow_creation_receipt_invalid' using errcode='55000';
    end if;

    v_scope:=v_existing_version.spec->>'scopeType';
    if (v_scope='organization' and (
          p_property_id is not null or p_room_id is not null or p_occupancy_id is not null
        ))
       or (v_scope='property' and (
          v_existing_application.property_id is distinct from p_property_id
          or p_room_id is not null or p_occupancy_id is not null
        ))
       or (v_scope='room' and (
          v_existing_application.property_id is distinct from p_property_id
          or v_existing_application.room_id is distinct from p_room_id
          or p_occupancy_id is not null
        ))
       or (v_scope='occupancy' and (
          v_existing_application.property_id is distinct from p_property_id
          or v_existing_application.occupancy_id is distinct from p_occupancy_id
          or p_room_id is not null
        )) then
      raise exception 'workflow_creation_request_conflict' using errcode='55000';
    end if;

    select array_agg(r.pattern_id order by r.sort_order)
    into v_existing_photo_ids
    from public.workflow_application_photo_resources_v2 r
    where r.application_id=v_existing_application.id;

    if coalesce(v_existing_photo_ids,'{}'::uuid[])
       is distinct from coalesce(p_photo_pattern_ids,'{}'::uuid[]) then
      raise exception 'workflow_creation_request_conflict' using errcode='55000';
    end if;

    if p_execute then
      select execution_id,status,assigned_user_id
      into v_execution_id,v_execution_status,v_execution_assigned_user_id
      from public.execute_workflow_application_now_v1(
        v_existing_application.id,
        p_idempotency_key,
        p_assigned_user_id
      )
      limit 1;
    end if;

    return query
    select
      v_existing_definition.id,
      v_existing_version.id,
      v_existing_version.version,
      v_existing_application.id,
      v_execution_id,
      v_execution_status,
      v_execution_assigned_user_id,
      v_existing_version.published_at;
    return;
  end if;

  select * into v_draft
  from public.save_workflow_definition_draft_v2(p_spec,null,null)
  limit 1;

  update public.workflow_definitions_v2 wd
  set creation_request_key=v_request_key
  where wd.id=v_draft.definition_id;

  select * into v_published
  from public.publish_workflow_definition_v1(
    v_draft.definition_id,
    v_draft.revision
  )
  limit 1;

  select * into v_application
  from public.create_workflow_application_v2(
    v_published.version_id,
    p_property_id,
    p_room_id,
    p_occupancy_id,
    coalesce(p_photo_pattern_ids,'{}'::uuid[])
  )
  limit 1;

  if p_execute then
    select execution_id,status,assigned_user_id
    into v_execution_id,v_execution_status,v_execution_assigned_user_id
    from public.execute_workflow_application_now_v1(
      v_application.application_id,
      p_idempotency_key,
      p_assigned_user_id
    )
    limit 1;
  end if;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  )
  select
    wd.organization_id,v_actor,
    case when p_execute then 'workflow_ready_published_and_executed' else 'workflow_ready_published' end,
    'workflow_definition',wd.id::text,'success',
    jsonb_build_object(
      'version_id',v_published.version_id,
      'application_id',v_application.application_id,
      'execution_id',v_execution_id,
      'request_key',v_request_key
    )
  from public.workflow_definitions_v2 wd
  where wd.id=v_draft.definition_id;

  return query
  select
    v_draft.definition_id,
    v_published.version_id,
    v_published.version,
    v_application.application_id,
    v_execution_id,
    v_execution_status,
    v_execution_assigned_user_id,
    v_published.published_at;
end;
$$;

revoke all on function public.publish_workflow_ready_v1(jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid) from public;
grant execute on function public.publish_workflow_ready_v1(jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid) to authenticated;

create or replace function public.update_unexecuted_workflow_v1(
  p_definition_id uuid,
  p_spec jsonb,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_expected_revision bigint default null,
  p_execute boolean default false,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  revision bigint
)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_definition public.workflow_definitions_v2;
  v_version public.workflow_definition_versions_v2;
  v_spec jsonb;
  v_new_revision bigint;
  v_application record;
  v_execution_id uuid;
  v_execution_status text;
  v_execution_assigned_user_id uuid;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if coalesce(auth.jwt()->>'aal','aal1') <> 'aal2' then
    raise exception 'aal2_required' using errcode='42501';
  end if;

  select wd.* into v_definition
  from public.workflow_definitions_v2 wd
  where wd.id=p_definition_id
  for update;

  if v_definition.id is null then
    raise exception 'workflow_definition_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_definition.organization_id) then
    raise exception 'workflow_author_role_required' using errcode='42501';
  end if;

  if v_definition.status<>'published' then
    raise exception 'workflow_definition_not_editable' using errcode='55000';
  end if;

  if p_expected_revision is not null and p_expected_revision<>v_definition.revision then
    raise exception 'workflow_draft_conflict' using errcode='40001';
  end if;

  if exists(
    select 1
    from public.workflow_executions_v2 e
    join public.workflow_applications_v2 a on a.id=e.application_id
    where a.definition_id=p_definition_id
  ) then
    raise exception 'workflow_definition_has_history' using errcode='55000';
  end if;

  v_spec:=private.workflow_sanitize_authoring_spec_v2(p_spec);
  if not public.workflow_authoring_complete_v1(v_spec) then
    raise exception 'workflow_authoring_incomplete' using errcode='22023';
  end if;

  select wv.* into v_version
  from public.workflow_definition_versions_v2 wv
  where wv.definition_id=p_definition_id
    and wv.organization_id=v_definition.organization_id
  order by wv.version desc
  limit 1
  for update;

  if v_version.id is null then
    raise exception 'workflow_published_version_missing' using errcode='55000';
  end if;

  v_new_revision:=v_definition.revision+1;

  update public.workflow_definitions_v2 wd
  set name=v_spec->>'flowName',
      flow_type=nullif(v_spec->>'flowType',''),
      description=nullif(v_spec->>'flowDescription',''),
      scope_type=nullif(v_spec->>'scopeType',''),
      trigger_type=nullif(v_spec->>'triggerType',''),
      assignment_type=nullif(v_spec->>'assignmentType',''),
      close_type=nullif(v_spec->>'closeType',''),
      draft_spec=v_spec,
      authoring_complete=true,
      revision=v_new_revision,
      updated_by=v_actor,
      updated_at=now()
  where wd.id=p_definition_id;

  update public.workflow_definition_versions_v2 wv
  set spec=v_spec || jsonb_build_object('definitionRevision',v_new_revision)
  where wv.id=v_version.id;

  delete from public.workflow_definition_revision_drafts_v2 rd
  where rd.definition_id=p_definition_id;

  delete from public.workflow_application_photo_resources_v2 r
  where r.application_id in (
    select a.id
    from public.workflow_applications_v2 a
    where a.definition_id=p_definition_id
  );

  delete from public.workflow_applications_v2 a
  where a.definition_id=p_definition_id;

  select * into v_application
  from public.create_workflow_application_v2(
    v_version.id,
    p_property_id,
    p_room_id,
    p_occupancy_id,
    coalesce(p_photo_pattern_ids,'{}'::uuid[])
  )
  limit 1;

  if p_execute then
    select execution_id,status,assigned_user_id
    into v_execution_id,v_execution_status,v_execution_assigned_user_id
    from public.execute_workflow_application_now_v1(
      v_application.application_id,
      p_idempotency_key,
      p_assigned_user_id
    )
    limit 1;
  end if;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_definition.organization_id,v_actor,
    case when p_execute then 'workflow_unexecuted_updated_and_executed' else 'workflow_unexecuted_updated' end,
    'workflow_definition',p_definition_id::text,'success',
    jsonb_build_object(
      'version_id',v_version.id,
      'version',v_version.version,
      'revision',v_new_revision,
      'application_id',v_application.application_id,
      'execution_id',v_execution_id
    )
  );

  return query
  select
    p_definition_id,
    v_version.id,
    v_version.version,
    v_application.application_id,
    v_execution_id,
    v_execution_status,
    v_execution_assigned_user_id,
    v_new_revision;
end;
$$;

revoke all on function public.update_unexecuted_workflow_v1(uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid) from public;
grant execute on function public.update_unexecuted_workflow_v1(uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid) to authenticated;

create or replace function public.publish_workflow_revision_ready_v1(
  p_definition_id uuid,
  p_expected_revision bigint,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_execute boolean default false,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  published_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_definition public.workflow_definitions_v2;
  v_published record;
  v_application record;
  v_execution_id uuid;
  v_execution_status text;
  v_execution_assigned_user_id uuid;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if coalesce(auth.jwt()->>'aal','aal1') <> 'aal2' then
    raise exception 'aal2_required' using errcode='42501';
  end if;

  select wd.* into v_definition
  from public.workflow_definitions_v2 wd
  where wd.id=p_definition_id
  for update;

  if v_definition.id is null then
    raise exception 'workflow_definition_not_found' using errcode='P0002';
  end if;

  if not exists(
    select 1
    from public.workflow_executions_v2 e
    join public.workflow_applications_v2 a on a.id=e.application_id
    where a.definition_id=p_definition_id
  ) then
    raise exception 'workflow_revision_requires_history' using errcode='55000';
  end if;

  select * into v_published
  from public.publish_workflow_definition_revision_v1(
    p_definition_id,
    p_expected_revision
  )
  limit 1;

  update public.workflow_applications_v2 a
  set status='archived',
      archived_at=coalesce(a.archived_at,now()),
      updated_at=now()
  where a.definition_id=p_definition_id
    and a.definition_version_id<>v_published.version_id
    and a.status='configured';

  select * into v_application
  from public.create_workflow_application_v2(
    v_published.version_id,
    p_property_id,
    p_room_id,
    p_occupancy_id,
    coalesce(p_photo_pattern_ids,'{}'::uuid[])
  )
  limit 1;

  if p_execute then
    select execution_id,status,assigned_user_id
    into v_execution_id,v_execution_status,v_execution_assigned_user_id
    from public.execute_workflow_application_now_v1(
      v_application.application_id,
      p_idempotency_key,
      p_assigned_user_id
    )
    limit 1;
  end if;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_definition.organization_id,v_actor,
    case when p_execute then 'workflow_revision_ready_published_and_executed' else 'workflow_revision_ready_published' end,
    'workflow_definition',p_definition_id::text,'success',
    jsonb_build_object(
      'version_id',v_published.version_id,
      'version',v_published.version,
      'application_id',v_application.application_id,
      'execution_id',v_execution_id
    )
  );

  return query
  select
    p_definition_id,
    v_published.version_id,
    v_published.version,
    v_application.application_id,
    v_execution_id,
    v_execution_status,
    v_execution_assigned_user_id,
    v_published.published_at;
end;
$$;

revoke all on function public.publish_workflow_revision_ready_v1(uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid) from public;
grant execute on function public.publish_workflow_revision_ready_v1(uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid) to authenticated;

create or replace function public.delete_unexecuted_workflow_v1(p_definition_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_definition public.workflow_definitions_v2;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if coalesce(auth.jwt()->>'aal','aal1') <> 'aal2' then
    raise exception 'aal2_required' using errcode='42501';
  end if;

  select wd.* into v_definition
  from public.workflow_definitions_v2 wd
  where wd.id=p_definition_id
  for update;

  if v_definition.id is null then
    raise exception 'workflow_definition_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_definition.organization_id) then
    raise exception 'workflow_definition_delete_forbidden' using errcode='42501';
  end if;

  if exists(
    select 1
    from public.workflow_executions_v2 e
    join public.workflow_applications_v2 a on a.id=e.application_id
    where a.definition_id=p_definition_id
  ) then
    raise exception 'workflow_definition_has_history' using errcode='55000';
  end if;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_definition.organization_id,v_actor,'workflow_definition_deleted_unexecuted',
    'workflow_definition',p_definition_id::text,'success',
    jsonb_build_object('name',v_definition.name,'revision',v_definition.revision)
  );

  delete from public.workflow_definition_revision_drafts_v2 rd
  where rd.definition_id=p_definition_id;

  delete from public.workflow_application_photo_resources_v2 r
  where r.application_id in (
    select a.id
    from public.workflow_applications_v2 a
    where a.definition_id=p_definition_id
  );

  delete from public.workflow_applications_v2 a
  where a.definition_id=p_definition_id;

  delete from public.workflow_definition_versions_v2 v
  where v.definition_id=p_definition_id;

  delete from public.workflow_definitions_v2 wd
  where wd.id=p_definition_id;

  return true;
end;
$$;

revoke all on function public.delete_unexecuted_workflow_v1(uuid) from public;
grant execute on function public.delete_unexecuted_workflow_v1(uuid) to authenticated;

create or replace function public.archive_workflow_definition_v1(p_definition_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_definition public.workflow_definitions_v2;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if coalesce(auth.jwt()->>'aal','aal1') <> 'aal2' then
    raise exception 'aal2_required' using errcode='42501';
  end if;

  select wd.* into v_definition
  from public.workflow_definitions_v2 wd
  where wd.id=p_definition_id
  for update;

  if v_definition.id is null then
    raise exception 'workflow_definition_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_definition.organization_id) then
    raise exception 'workflow_definition_archive_forbidden' using errcode='42501';
  end if;

  if v_definition.status='archived' then
    return true;
  end if;

  if not exists(
    select 1
    from public.workflow_executions_v2 e
    join public.workflow_applications_v2 a on a.id=e.application_id
    where a.definition_id=p_definition_id
  ) then
    raise exception 'workflow_unexecuted_delete_instead' using errcode='55000';
  end if;

  delete from public.workflow_definition_revision_drafts_v2 rd
  where rd.definition_id=p_definition_id
    and rd.published_at is null;

  update public.workflow_applications_v2 a
  set status='archived',
      archived_at=coalesce(a.archived_at,now()),
      updated_at=now()
  where a.definition_id=p_definition_id
    and a.status='configured';

  update public.workflow_definitions_v2 wd
  set status='archived',
      archived_at=now(),
      updated_by=v_actor,
      updated_at=now()
  where wd.id=p_definition_id;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_definition.organization_id,v_actor,'workflow_definition_archived',
    'workflow_definition',p_definition_id::text,'success',
    jsonb_build_object('name',v_definition.name)
  );

  return true;
end;
$$;

revoke all on function public.archive_workflow_definition_v1(uuid) from public;
grant execute on function public.archive_workflow_definition_v1(uuid) to authenticated;

comment on function public.publish_workflow_ready_v1(jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid) is
  'Finaliza de forma atomica un flujo nuevo: publica definicion/version, configura destino y opcionalmente ejecuta. No persiste creaciones parciales.';
comment on function public.update_unexecuted_workflow_v1(uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid) is
  'Edita en sitio un flujo publicado que nunca se ha ejecutado; mantiene la misma version logica y reemplaza su destino de forma atomica.';
comment on function public.publish_workflow_revision_ready_v1(uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid) is
  'Finaliza una edicion de un flujo con historial: publica nueva version, configura su destino y opcionalmente ejecuta.';
comment on function public.delete_unexecuted_workflow_v1(uuid) is
  'Elimina fisicamente solo definiciones sin ninguna ejecucion historica.';
comment on function public.archive_workflow_definition_v1(uuid) is
  'Archiva definiciones que ya tienen historial de ejecuciones, preservando versiones, aplicaciones, tareas y evidencias.';
