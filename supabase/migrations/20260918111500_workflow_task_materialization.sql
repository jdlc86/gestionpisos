-- GestionPisos · Flujos de Trabajo · materialización genérica de tareas
-- Reutiliza tenant_tasks_v2 sin fabricar tenant_id para ámbitos no ligados a un inquilino.

alter table public.tenant_tasks_v2
  alter column tenant_id drop not null;

alter table public.tenant_tasks_v2
  drop constraint if exists tenant_tasks_v2_task_type_check;

alter table public.tenant_tasks_v2
  add constraint tenant_tasks_v2_task_type_check
  check (task_type in (
    'key_pickup','key_delivery','check_in','check_out','cleaning',
    'rent_payment','rent_claim','damage_claim','deposit','incident','generic','workflow'
  ));

alter table public.tenant_tasks_v2
  drop constraint if exists tenant_tasks_v2_subject_or_workflow_check;

alter table public.tenant_tasks_v2
  add constraint tenant_tasks_v2_subject_or_workflow_check
  check (
    (
      source_kind='workflow_execution'
      and source_id is not null
      and assigned_user_id is not null
      and task_type='workflow'
    )
    or
    (
      source_kind is distinct from 'workflow_execution'
      and task_type<>'workflow'
      and tenant_id is not null
    )
  );

create unique index if not exists tenant_tasks_v2_workflow_execution_uq
  on public.tenant_tasks_v2(source_id)
  where source_kind='workflow_execution' and source_id is not null;

create index if not exists tenant_tasks_v2_assigned_open_idx
  on public.tenant_tasks_v2(assigned_user_id,created_at desc)
  where assigned_user_id is not null
    and status not in ('completed','cancelled');

-- Las tareas dejan de ser escribibles directamente desde PostgREST.
revoke all on public.tenant_tasks_v2 from anon;
revoke all on public.tenant_task_actions_v2 from anon;
revoke all on public.tenant_task_history_v2 from anon;

revoke insert,update,delete,truncate,references,trigger
  on public.tenant_tasks_v2 from authenticated;
revoke insert,update,delete,truncate,references,trigger
  on public.tenant_task_actions_v2 from authenticated;
revoke insert,update,delete,truncate,references,trigger
  on public.tenant_task_history_v2 from authenticated;

grant select on public.tenant_tasks_v2 to authenticated;
grant select on public.tenant_task_actions_v2 to authenticated;
grant select on public.tenant_task_history_v2 to authenticated;
grant select on public.tenants_v2 to authenticated;

drop policy if exists tenant_tasks_v2_root_all on public.tenant_tasks_v2;
drop policy if exists tenant_tasks_v2_admin_org_all on public.tenant_tasks_v2;
drop policy if exists tenant_tasks_v2_root_read on public.tenant_tasks_v2;
drop policy if exists tenant_tasks_v2_admin_org_read on public.tenant_tasks_v2;
drop policy if exists tenant_tasks_v2_admin_read on public.tenant_tasks_v2;
drop policy if exists tenant_tasks_v2_assignee_read on public.tenant_tasks_v2;
drop policy if exists tenant_tasks_v2_tenant_read on public.tenant_tasks_v2;
drop policy if exists tenant_tasks_v2_property_operator_read on public.tenant_tasks_v2;

create policy tenant_tasks_v2_admin_read
on public.tenant_tasks_v2
for select to authenticated
using (public.workflow_can_read_definitions_v1(organization_id));

create policy tenant_tasks_v2_assignee_read
on public.tenant_tasks_v2
for select to authenticated
using (assigned_user_id=auth.uid());

create policy tenant_tasks_v2_tenant_read
on public.tenant_tasks_v2
for select to authenticated
using (
  tenant_id is not null
  and exists(
    select 1 from public.tenants_v2 tn
    where tn.id=tenant_tasks_v2.tenant_id
      and tn.user_id=auth.uid()
  )
);

create or replace function public.workflow_materialize_execution_task_internal_v1(
  p_execution_id uuid,
  p_actor_user_id uuid
)
returns public.tenant_tasks_v2
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_title text;
  v_description text;
  v_tenant_id uuid;
  v_actor uuid;
begin
  select * into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id
  for update;

  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id
  limit 1;

  if v_task.id is not null then
    return v_task;
  end if;

  if v_execution.status<>'pending' then
    raise exception 'workflow_execution_not_materializable' using errcode='55000';
  end if;

  v_actor:=coalesce(p_actor_user_id,v_execution.created_by);

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

  return v_task;
end;
$$;

revoke all on function public.workflow_materialize_execution_task_internal_v1(uuid,uuid)
  from public,anon,authenticated;

create or replace function public.materialize_workflow_execution_task_v1(
  p_execution_id uuid
)
returns public.tenant_tasks_v2
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_org uuid;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select organization_id
  into v_org
  from public.workflow_executions_v2
  where id=p_execution_id;

  if v_org is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_org) then
    raise exception 'workflow_task_materialization_not_authorized' using errcode='42501';
  end if;

  return public.workflow_materialize_execution_task_internal_v1(p_execution_id,v_actor);
end;
$$;

revoke all on function public.materialize_workflow_execution_task_v1(uuid) from public;
revoke execute on function public.materialize_workflow_execution_task_v1(uuid) from anon;
grant execute on function public.materialize_workflow_execution_task_v1(uuid) to authenticated;

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

-- Materializar ejecuciones pendientes creadas antes de este incremento.
do $$
declare
  r record;
begin
  for r in
    select e.id,e.created_by
    from public.workflow_executions_v2 e
    where e.status='pending'
      and not exists(
        select 1
        from public.tenant_tasks_v2 t
        where t.source_kind='workflow_execution'
          and t.source_id=e.id
      )
  loop
    perform public.workflow_materialize_execution_task_internal_v1(r.id,r.created_by);
  end loop;
end;
$$;

comment on column public.tenant_tasks_v2.tenant_id is
  'Obligatorio para tareas legacy; puede ser NULL únicamente en tareas source_kind=workflow_execution conforme al constraint de compatibilidad.';

comment on function public.materialize_workflow_execution_task_v1(uuid) is
  'Materializa de forma idempotente una ejecución pendiente como tenant_tasks_v2 sin fabricar tenant_id.';

comment on function public.execute_workflow_application_now_v1(uuid,text,uuid) is
  'Crea de forma idempotente una ejecución manual_now, congela la asignación y materializa una única tarea de workflow en la misma transacción.';
