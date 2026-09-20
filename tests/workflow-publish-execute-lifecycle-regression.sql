-- Flujos · regresion ciclo Publicar / Ejecutar / primera frontera historica.
-- PostgreSQL desechable. Todo se revierte al finalizar.

begin;

do $privileges$
begin
  if has_function_privilege('anon','public.publish_workflow_ready_v1(jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid)','EXECUTE') then
    raise exception 'anon can finalize new workflow';
  end if;
  if has_function_privilege('anon','public.update_unexecuted_workflow_v1(uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid)','EXECUTE') then
    raise exception 'anon can update unexecuted workflow';
  end if;
  if has_function_privilege('anon','public.publish_workflow_revision_ready_v1(uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid)','EXECUTE') then
    raise exception 'anon can finalize workflow revision';
  end if;
  if has_function_privilege('anon','public.delete_unexecuted_workflow_v1(uuid)','EXECUTE') then
    raise exception 'anon can delete workflow';
  end if;
  if has_function_privilege('anon','public.archive_workflow_definition_v1(uuid)','EXECUTE') then
    raise exception 'anon can archive workflow';
  end if;

  if not has_function_privilege('authenticated','public.publish_workflow_ready_v1(jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid)','EXECUTE')
    or not has_function_privilege('authenticated','public.update_unexecuted_workflow_v1(uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid)','EXECUTE')
    or not has_function_privilege('authenticated','public.publish_workflow_revision_ready_v1(uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid)','EXECUTE')
    or not has_function_privilege('authenticated','public.delete_unexecuted_workflow_v1(uuid)','EXECUTE')
    or not has_function_privilege('authenticated','public.archive_workflow_definition_v1(uuid)','EXECUTE') then
    raise exception 'authenticated missing workflow lifecycle RPC';
  end if;
end;
$privileges$;

select set_config(
  'gestionpisos.lifecycle_executor',
  '77777777-7777-4777-8777-777777777771',
  true
);

insert into auth.users(id)
values(current_setting('gestionpisos.lifecycle_executor')::uuid)
on conflict(id) do nothing;

insert into public.user_roles(user_id,organization_id,role)
select
  current_setting('gestionpisos.lifecycle_executor')::uuid,
  ur.organization_id,
  'employee'
from public.user_roles ur
where ur.user_id='22222222-2222-4222-8222-222222222222'::uuid
  and ur.role='root'
  and ur.revoked_at is null
limit 1
on conflict do nothing;

set local role authenticated;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','22222222-2222-4222-8222-222222222222',
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

-- PUBLICAR: definicion/version/destino completos, pero ninguna ejecucion ni tarea.
select set_config(
  'gestionpisos.lifecycle_unexecuted_definition',
  (
    select definition_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Lifecycle solo publicado',
        'flowType','custom',
        'flowDescription','Publicado sin tarea',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      null,null,null,'{}'::uuid[],false,
      'regression-publish-only-1',null,null
    )
    limit 1
  ),
  true
);

do $publish_only$
declare
  v_definition uuid:=current_setting('gestionpisos.lifecycle_unexecuted_definition')::uuid;
  v_versions integer;
  v_apps integer;
  v_execs integer;
  v_tasks integer;
begin
  select count(*) into v_versions
  from public.workflow_definition_versions_v2
  where definition_id=v_definition;

  select count(*) into v_apps
  from public.workflow_applications_v2
  where definition_id=v_definition and status='configured';

  select count(*) into v_execs
  from public.workflow_executions_v2 e
  join public.workflow_applications_v2 a on a.id=e.application_id
  where a.definition_id=v_definition;

  select count(*) into v_tasks
  from public.tenant_tasks_v2 t
  join public.workflow_executions_v2 e on e.id=t.source_id and t.source_kind='workflow_execution'
  join public.workflow_applications_v2 a on a.id=e.application_id
  where a.definition_id=v_definition;

  if v_versions<>1 or v_apps<>1 or v_execs<>0 or v_tasks<>0 then
    raise exception 'publish-only did not produce exactly definition/version/destination and zero work: versions %, apps %, execs %, tasks %',
      v_versions,v_apps,v_execs,v_tasks;
  end if;
end;
$publish_only$;

-- Reintentar Publicar con la misma request key no crea basura ni duplicados.
do $publish_retry$
declare
  v_definition uuid;
  v_application uuid;
  v_versions integer;
  v_apps integer;
begin
  select definition_id,application_id
  into v_definition,v_application
  from public.publish_workflow_ready_v1(
    jsonb_build_object(
      'authoringVersion',2,
      'flowName','Lifecycle solo publicado',
      'flowType','custom',
      'flowDescription','Publicado sin tarea',
      'scopeType','organization',
      'triggerType','manual',
      'recurrence','',
      'scheduledAt','',
      'customEvery','',
      'customUnit','',
      'assignmentType','manual',
      'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
      'checklistItems','[]'::jsonb,
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',false,'onClose',false)
    ),
    null,null,null,'{}'::uuid[],false,
    'regression-publish-only-1',null,null
  )
  limit 1;

  select count(*) into v_versions
  from public.workflow_definition_versions_v2
  where definition_id=v_definition;
  select count(*) into v_apps
  from public.workflow_applications_v2
  where definition_id=v_definition;

  if v_definition<>current_setting('gestionpisos.lifecycle_unexecuted_definition')::uuid
    or v_versions<>1 or v_apps<>1 then
    raise exception 'publish retry was not idempotent';
  end if;
end;
$publish_retry$;

-- EDITAR antes de ejecutar: misma entidad y misma version historica; solo cambia configuracion actual.
select set_config(
  'gestionpisos.lifecycle_unexecuted_revision',
  (
    select revision::text
    from public.workflow_definitions_v2
    where id=current_setting('gestionpisos.lifecycle_unexecuted_definition')::uuid
  ),
  true
);

select *
from public.update_unexecuted_workflow_v1(
  current_setting('gestionpisos.lifecycle_unexecuted_definition')::uuid,
  jsonb_build_object(
    'authoringVersion',2,
    'flowName','Lifecycle editado sin historial',
    'flowType','custom',
    'flowDescription','Misma entidad, sin v2',
    'scopeType','organization',
    'triggerType','manual',
    'recurrence','',
    'scheduledAt','',
    'customEvery','',
    'customUnit','',
    'assignmentType','manual',
    'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
    'checklistItems','[]'::jsonb,
    'closeType','auto',
    'notifications',jsonb_build_object('onCreate',false,'onClose',false)
  ),
  null,null,null,'{}'::uuid[],
  current_setting('gestionpisos.lifecycle_unexecuted_revision')::bigint,
  false,null,null
);

do $unexecuted_edit_in_place$
declare
  v_definition uuid:=current_setting('gestionpisos.lifecycle_unexecuted_definition')::uuid;
  v_versions integer;
  v_name text;
  v_version_name text;
  v_apps integer;
begin
  select count(*) into v_versions
  from public.workflow_definition_versions_v2
  where definition_id=v_definition;

  select name into v_name
  from public.workflow_definitions_v2
  where id=v_definition;

  select spec->>'flowName' into v_version_name
  from public.workflow_definition_versions_v2
  where definition_id=v_definition and version=1;

  select count(*) into v_apps
  from public.workflow_applications_v2
  where definition_id=v_definition and status='configured';

  if v_versions<>1
    or v_name<>'Lifecycle editado sin historial'
    or v_version_name<>'Lifecycle editado sin historial'
    or v_apps<>1 then
    raise exception 'unexecuted edit unexpectedly versioned or lost destination';
  end if;
end;
$unexecuted_edit_in_place$;

-- Sin historial se puede eliminar completamente.
select public.delete_unexecuted_workflow_v1(
  current_setting('gestionpisos.lifecycle_unexecuted_definition')::uuid
);

do $unexecuted_deleted$
begin
  if exists(
    select 1 from public.workflow_definitions_v2
    where id=current_setting('gestionpisos.lifecycle_unexecuted_definition')::uuid
  ) then
    raise exception 'unexecuted workflow was not deleted';
  end if;
end;
$unexecuted_deleted$;

-- EJECUTAR desde Listo: publica y crea exactamente una ejecucion + una tarea.
select set_config(
  'gestionpisos.lifecycle_executed_definition',
  (
    select definition_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Lifecycle ejecutado',
        'flowType','custom',
        'flowDescription','Primera ejecucion fija la frontera historica',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      null,null,null,'{}'::uuid[],true,
      'regression-publish-execute-1',
      'regression-execute-1',
      current_setting('gestionpisos.lifecycle_executor')::uuid
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.lifecycle_execution',
  (
    select execution_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Lifecycle ejecutado',
        'flowType','custom',
        'flowDescription','Primera ejecucion fija la frontera historica',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      null,null,null,'{}'::uuid[],true,
      'regression-publish-execute-1',
      'regression-execute-1',
      current_setting('gestionpisos.lifecycle_executor')::uuid
    )
    limit 1
  ),
  true
);

do $first_execution_boundary$
declare
  v_definition uuid:=current_setting('gestionpisos.lifecycle_executed_definition')::uuid;
  v_execs integer;
  v_tasks integer;
  v_versions integer;
begin
  select count(*) into v_execs
  from public.workflow_executions_v2 e
  join public.workflow_applications_v2 a on a.id=e.application_id
  where a.definition_id=v_definition;

  select count(*) into v_tasks
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('gestionpisos.lifecycle_execution')::uuid;

  select count(*) into v_versions
  from public.workflow_definition_versions_v2
  where definition_id=v_definition;

  if v_execs<>1 or v_tasks<>1 or v_versions<>1 then
    raise exception 'first execute did not materialize exactly one execution/task';
  end if;

  begin
    perform public.delete_unexecuted_workflow_v1(v_definition);
    raise exception 'executed workflow was deletable';
  exception when object_not_in_prerequisite_state then
    null;
  end;
end;
$first_execution_boundary$;

-- EDITAR despues de la primera ejecucion: ahora si se crea una nueva version.
select set_config(
  'gestionpisos.lifecycle_revision_draft_revision',
  (
    select revision::text
    from public.start_workflow_definition_revision_v1(
      current_setting('gestionpisos.lifecycle_executed_definition')::uuid
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.lifecycle_revision_draft_revision',
  (
    select revision::text
    from public.save_workflow_definition_revision_draft_v1(
      current_setting('gestionpisos.lifecycle_executed_definition')::uuid,
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Lifecycle ejecutado v2',
        'flowType','custom',
        'flowDescription','Nueva version por existir historial',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      current_setting('gestionpisos.lifecycle_revision_draft_revision')::bigint
    )
    limit 1
  ),
  true
);

select *
from public.publish_workflow_revision_ready_v1(
  current_setting('gestionpisos.lifecycle_executed_definition')::uuid,
  current_setting('gestionpisos.lifecycle_revision_draft_revision')::bigint,
  null,null,null,'{}'::uuid[],false,null,null
);

do $executed_edit_versions$
declare
  v_definition uuid:=current_setting('gestionpisos.lifecycle_executed_definition')::uuid;
  v_versions integer;
  v_v1_name text;
  v_v2_name text;
  v_execution_version integer;
  v_current_apps integer;
begin
  select count(*),
         min(spec->>'flowName') filter(where version=1),
         min(spec->>'flowName') filter(where version=2)
  into v_versions,v_v1_name,v_v2_name
  from public.workflow_definition_versions_v2
  where definition_id=v_definition;

  select v.version
  into v_execution_version
  from public.workflow_executions_v2 e
  join public.workflow_definition_versions_v2 v on v.id=e.definition_version_id
  where e.id=current_setting('gestionpisos.lifecycle_execution')::uuid;

  select count(*) into v_current_apps
  from public.workflow_applications_v2
  where definition_id=v_definition
    and status='configured';

  if v_versions<>2
    or v_v1_name<>'Lifecycle ejecutado'
    or v_v2_name<>'Lifecycle ejecutado v2'
    or v_execution_version<>1
    or v_current_apps<>1 then
    raise exception 'historical edit did not append v2 while preserving v1 execution';
  end if;
end;
$executed_edit_versions$;

-- Un flujo con historial se archiva y conserva ejecucion/tarea/versiones.
select public.archive_workflow_definition_v1(
  current_setting('gestionpisos.lifecycle_executed_definition')::uuid
);

do $archive_preserves_history$
declare
  v_definition uuid:=current_setting('gestionpisos.lifecycle_executed_definition')::uuid;
begin
  if not exists(
    select 1 from public.workflow_definitions_v2
    where id=v_definition and status='archived' and archived_at is not null
  ) then
    raise exception 'executed workflow was not archived';
  end if;

  if (select count(*) from public.workflow_definition_versions_v2 where definition_id=v_definition)<>2 then
    raise exception 'archive removed workflow versions';
  end if;

  if not exists(
    select 1 from public.workflow_executions_v2
    where id=current_setting('gestionpisos.lifecycle_execution')::uuid
  ) then
    raise exception 'archive removed execution history';
  end if;

  if not exists(
    select 1 from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('gestionpisos.lifecycle_execution')::uuid
  ) then
    raise exception 'archive removed materialized task';
  end if;
end;
$archive_preserves_history$;

rollback;
