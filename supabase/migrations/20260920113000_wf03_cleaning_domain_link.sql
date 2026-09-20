-- GestionPisos · WF-03 · primer adaptador de dominio Limpieza
-- Una sola tarjeta operativa vive en tenant_tasks_v2. cleaning_tasks_v2 conserva
-- exclusivamente el expediente especializado de limpieza enlazado a la ejecución.

alter table public.cleaning_tasks_v2
  add column if not exists workflow_execution_id uuid
    references public.workflow_executions_v2(id) on delete restrict;

create unique index if not exists cleaning_tasks_workflow_execution_uidx
  on public.cleaning_tasks_v2(workflow_execution_id)
  where workflow_execution_id is not null;

create or replace function private.workflow_ensure_cleaning_domain_task_v1(
  p_execution_id uuid,
  p_actor_user_id uuid
)
returns public.cleaning_tasks_v2
language plpgsql
security definer
set search_path=''
as $workflow_cleaning_domain$
declare
  v_execution public.workflow_executions_v2;
  v_cleaning public.cleaning_tasks_v2;
  v_tenant_id uuid;
begin
  select *
  into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id
  for update;

  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  if coalesce(v_execution.spec_snapshot->>'flowType','')<>'cleaning' then
    return null;
  end if;

  if v_execution.property_id is null then
    raise exception 'workflow_cleaning_property_required' using errcode='55000';
  end if;

  select *
  into v_cleaning
  from public.cleaning_tasks_v2
  where workflow_execution_id=v_execution.id
  limit 1;

  if v_cleaning.id is not null then
    return v_cleaning;
  end if;

  -- tenant_id es identidad de dominio opcional. La asignación operativa sigue
  -- siendo assigned_user_id y puede pertenecer a personal no inquilino.
  if v_execution.occupancy_id is not null then
    select o.tenant_id
    into v_tenant_id
    from public.occupancies_v2 o
    where o.id=v_execution.occupancy_id
      and o.organization_id=v_execution.organization_id
      and o.property_id=v_execution.property_id;
  end if;

  if v_tenant_id is null then
    select o.tenant_id
    into v_tenant_id
    from public.occupancies_v2 o
    join public.tenants_v2 t
      on t.id=o.tenant_id
     and t.organization_id=o.organization_id
    where o.organization_id=v_execution.organization_id
      and o.property_id=v_execution.property_id
      and o.user_id=v_execution.assigned_user_id
      and o.status='active'
      and o.starts_on<=v_execution.created_at::date
      and (o.ends_on is null or o.ends_on>=v_execution.created_at::date)
      and t.status='active'
      and t.archived_at is null
    order by o.starts_on desc,o.id
    limit 1;
  end if;

  insert into public.cleaning_tasks_v2(
    organization_id,
    property_id,
    room_id,
    plan_id,
    assigned_user_id,
    task_date,
    status,
    verification_mode,
    tenant_id,
    workflow_execution_id
  ) values (
    v_execution.organization_id,
    v_execution.property_id,
    v_execution.room_id,
    null,
    v_execution.assigned_user_id,
    v_execution.created_at::date,
    'pending',
    'manual',
    v_tenant_id,
    v_execution.id
  )
  on conflict (workflow_execution_id)
    where workflow_execution_id is not null
  do nothing
  returning * into v_cleaning;

  if v_cleaning.id is null then
    select *
    into v_cleaning
    from public.cleaning_tasks_v2
    where workflow_execution_id=v_execution.id
    limit 1;
  else
    insert into public.audit_log_v2(
      organization_id,actor_user_id,action,entity_type,entity_id,result,details
    ) values (
      v_execution.organization_id,
      coalesce(p_actor_user_id,v_execution.created_by),
      'workflow_cleaning_domain_task_linked',
      'cleaning_task',
      v_cleaning.id::text,
      'success',
      jsonb_build_object(
        'workflow_execution_id',v_execution.id,
        'assigned_user_id',v_execution.assigned_user_id,
        'property_id',v_execution.property_id,
        'room_id',v_execution.room_id,
        'tenant_id',v_tenant_id
      )
    );

    insert into public.workflow_execution_events_v2(
      execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
    ) values (
      v_execution.id,
      v_execution.organization_id,
      'domain_adapter_linked',
      v_execution.status,
      v_execution.status,
      coalesce(p_actor_user_id,v_execution.created_by),
      jsonb_build_object(
        'adapter','cleaning',
        'cleaning_task_id',v_cleaning.id
      )
    );
  end if;

  return v_cleaning;
end;
$workflow_cleaning_domain$;

revoke all on function private.workflow_ensure_cleaning_domain_task_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

create or replace function public.workflow_materialize_execution_task_internal_v1(
  p_execution_id uuid,
  p_actor_user_id uuid
)
returns public.tenant_tasks_v2
language plpgsql
security definer
set search_path=public,pg_temp
as $workflow_materialize_task$
declare
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_title text;
  v_description text;
  v_tenant_id uuid;
  v_actor uuid;
begin
  select *
  into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id
  for update;

  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  v_actor:=coalesce(p_actor_user_id,v_execution.created_by);

  select *
  into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id
  limit 1;

  if v_task.id is not null then
    perform private.workflow_ensure_cleaning_domain_task_v1(v_execution.id,v_actor);
    return v_task;
  end if;

  if v_execution.status<>'pending' then
    raise exception 'workflow_execution_not_materializable' using errcode='55000';
  end if;

  select wd.name
  into v_title
  from public.workflow_definitions_v2 wd
  where wd.id=v_execution.definition_id;

  v_title:=coalesce(nullif(btrim(v_title),''),'Tarea de flujo');
  v_description:=nullif(btrim(coalesce(v_execution.spec_snapshot->>'flowDescription','')),'');

  if v_execution.scope_type='occupancy' and v_execution.occupancy_id is not null then
    select o.tenant_id
    into v_tenant_id
    from public.occupancies_v2 o
    where o.id=v_execution.occupancy_id
      and o.organization_id=v_execution.organization_id;
  end if;

  insert into public.tenant_tasks_v2(
    organization_id,
    tenant_id,
    property_id,
    room_id,
    task_type,
    origin,
    title,
    description,
    status,
    due_at,
    assigned_user_id,
    source_kind,
    source_id,
    created_by
  ) values (
    v_execution.organization_id,
    v_tenant_id,
    v_execution.property_id,
    v_execution.room_id,
    'workflow',
    'automatic',
    v_title,
    v_description,
    'pending',
    null,
    v_execution.assigned_user_id,
    'workflow_execution',
    v_execution.id,
    v_actor
  )
  returning * into v_task;

  insert into public.tenant_task_history_v2(
    task_id,action_key,action_label,from_status,to_status,note,actor_user_id
  ) values (
    v_task.id,
    'create',
    'Generada por ejecución de flujo',
    null,
    'pending',
    null,
    v_actor
  );

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,
    v_execution.organization_id,
    'task_materialized',
    v_execution.status,
    v_execution.status,
    v_actor,
    jsonb_build_object('task_id',v_task.id)
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,
    v_actor,
    'workflow_task_materialized',
    'tenant_task',
    v_task.id::text,
    'success',
    jsonb_build_object(
      'workflow_execution_id',v_execution.id,
      'definition_id',v_execution.definition_id,
      'application_id',v_execution.application_id,
      'assigned_user_id',v_execution.assigned_user_id,
      'scope_type',v_execution.scope_type,
      'property_id',v_execution.property_id,
      'room_id',v_execution.room_id,
      'occupancy_id',v_execution.occupancy_id
    )
  );

  perform private.workflow_ensure_cleaning_domain_task_v1(v_execution.id,v_actor);

  return v_task;
end;
$workflow_materialize_task$;

revoke all on function public.workflow_materialize_execution_task_internal_v1(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.workflow_materialize_execution_task_internal_v1(uuid,uuid)
  to service_role;

comment on column public.cleaning_tasks_v2.workflow_execution_id is
  'Ejecución transversal que originó este expediente especializado. No representa una segunda tarjeta operativa.';
comment on function private.workflow_ensure_cleaning_domain_task_v1(uuid,uuid) is
  'Crea idempotentemente el expediente cleaning_tasks_v2 para una ejecución flowType=cleaning; tenant_tasks_v2 sigue siendo la única tarjeta operativa.';
