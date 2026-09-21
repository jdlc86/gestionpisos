-- WF-05 · autoría, asignación y binding de eventos de incidencia al mismo
-- dispatcher WF-02. No se crea un listener ni runner alternativo.

alter function private.workflow_sanitize_authoring_spec_v3(jsonb)
  rename to workflow_sanitize_authoring_spec_pre_wf05_v3;
revoke all on function private.workflow_sanitize_authoring_spec_pre_wf05_v3(jsonb)
  from public,anon,authenticated,service_role;

create function private.workflow_sanitize_authoring_spec_v3(p_spec jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_spec jsonb;
  v_event_type text:=nullif(btrim(coalesce(p_spec->>'eventType','')),'');
begin
  if p_spec->>'triggerType'='event'
    and v_event_type in ('incident.created','incident.resolved') then
    v_spec:=private.workflow_sanitize_authoring_spec_pre_wf05_v3(
      p_spec || jsonb_build_object('eventType','occupancy.created')
    );
    return v_spec || jsonb_build_object('eventType',v_event_type);
  end if;
  return private.workflow_sanitize_authoring_spec_pre_wf05_v3(p_spec);
end;
$$;
revoke all on function private.workflow_sanitize_authoring_spec_v3(jsonb)
  from public,anon,authenticated,service_role;

alter function public.workflow_authoring_complete_v1(jsonb)
  rename to workflow_authoring_complete_pre_wf05_v1;
revoke all on function public.workflow_authoring_complete_pre_wf05_v1(jsonb)
  from public,anon,authenticated,service_role;

create function public.workflow_authoring_complete_v1(p_spec jsonb)
returns boolean
language plpgsql
immutable
security definer
set search_path=''
as $$
declare
  v_event text:=coalesce(p_spec->>'eventType','');
  v_base jsonb;
  v_common boolean;
begin
  if v_event not in ('incident.created','incident.resolved') then
    return public.workflow_authoring_complete_pre_wf05_v1(p_spec);
  end if;

  v_base:=p_spec || jsonb_build_object('eventType','occupancy.created');
  if not public.workflow_authoring_complete_pre_wf05_v1(v_base) then
    return false;
  end if;

  v_common:=p_spec->>'scopeType' in ('property','room')
    and p_spec->>'triggerType'='event'
    and p_spec->>'assignmentType' in
      ('property_responsible','fixed_person','role')
    and (
      p_spec->>'assignmentType'<>'role'
      or p_spec->>'assignmentRole' in ('admin','employee')
    );
  if not v_common then
    return false;
  end if;

  if v_event='incident.created' then
    return p_spec->>'flowType'='maintenance'
      and p_spec#>>'{steps,accept}'='true'
      and p_spec->>'closeType'='domain_adapter';
  end if;

  return p_spec->>'flowType'='inspection'
    and p_spec->>'closeType' in ('auto','human_review')
    and (
      coalesce((p_spec#>>'{steps,photo}')::boolean,false)
      or coalesce((p_spec#>>'{steps,checklist}')::boolean,false)
      or coalesce((p_spec#>>'{steps,document}')::boolean,false)
    );
end;
$$;
revoke all on function public.workflow_authoring_complete_v1(jsonb)
  from public,anon,service_role;
grant execute on function public.workflow_authoring_complete_v1(jsonb)
  to authenticated;

-- Resolver WF-05: los candidatos se filtran por escritura antes del desempate.
alter function private.workflow_resolve_execution_assignee_v1(uuid,uuid)
  rename to workflow_resolve_execution_assignee_pre_wf05_v1;
revoke all on function private.workflow_resolve_execution_assignee_pre_wf05_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

create function private.workflow_resolve_execution_assignee_v1(
  p_application_id uuid,
  p_requested_user_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_org uuid;
  v_property uuid;
  v_spec jsonb;
  v_assignment text;
  v_role text;
  v_user uuid;
  v_wf05 boolean:=false;
begin
  select a.organization_id,a.property_id,wv.spec
  into v_org,v_property,v_spec
  from public.workflow_applications_v2 a
  join public.workflow_definition_versions_v2 wv
    on wv.id=a.definition_version_id
   and wv.definition_id=a.definition_id
   and wv.organization_id=a.organization_id
  where a.id=p_application_id;

  v_wf05:=v_spec->>'triggerType'='event' and (
    (v_spec->>'flowType'='maintenance'
      and v_spec->>'eventType'='incident.created'
      and v_spec->>'closeType'='domain_adapter')
    or (v_spec->>'flowType'='inspection'
      and v_spec->>'eventType'='incident.resolved')
  );
  if not v_wf05 then
    return private.workflow_resolve_execution_assignee_pre_wf05_v1(
      p_application_id,p_requested_user_id
    );
  end if;

  v_assignment:=nullif(v_spec->>'assignmentType','');
  if v_assignment='role' then
    if p_requested_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved' using errcode='22023';
    end if;
    v_role:=nullif(v_spec->>'assignmentRole','');
    if v_role not in ('admin','employee') or v_role is null then
      raise exception 'workflow_assignment_role_invalid' using errcode='22023';
    end if;

    select ur.user_id into v_user
    from public.user_roles ur
    where ur.organization_id=v_org
      and ur.role::text=v_role
      and ur.revoked_at is null
      and private.incident_internal_access_v1(
        v_org,v_property,ur.user_id,true
      )
    order by (
      select count(*) from public.workflow_executions_v2 e
      where e.application_id=p_application_id
        and e.assigned_user_id=ur.user_id
    ),(
      select max(e.created_at) from public.workflow_executions_v2 e
      where e.application_id=p_application_id
        and e.assigned_user_id=ur.user_id
    ) nulls first,ur.user_id
    limit 1;

    if v_user is null then
      raise exception 'workflow_assignment_role_unavailable' using errcode='55000';
    end if;
    return v_user;
  end if;

  v_user:=private.workflow_resolve_execution_assignee_pre_wf05_v1(
    p_application_id,p_requested_user_id
  );
  if v_user is null or not private.incident_internal_access_v1(
    v_org,v_property,v_user,true
  ) then
    raise exception 'workflow_wf05_assignee_not_eligible' using errcode='42501';
  end if;
  return v_user;
end;
$$;
revoke all on function private.workflow_resolve_execution_assignee_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

-- Conserva el OID de la función para que las policies y wrappers existentes
-- reciban la revalidación WF-05 sin recrearse.
create or replace function public.workflow_execution_actor_current_v1(
  p_execution_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_execution public.workflow_executions_v2;
begin
  if v_actor is null or p_execution_id is null then
    return false;
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id;
  if v_execution.id is null
    or v_execution.assigned_user_id is distinct from v_actor then
    return false;
  end if;

  if v_execution.spec_snapshot->>'triggerType'='event' and (
    (v_execution.spec_snapshot->>'flowType'='maintenance'
      and v_execution.spec_snapshot->>'eventType'='incident.created'
      and v_execution.spec_snapshot->>'closeType'='domain_adapter')
    or (v_execution.spec_snapshot->>'flowType'='inspection'
      and v_execution.spec_snapshot->>'eventType'='incident.resolved')
  ) then
    -- WF-05 añade revalidación del expediente/destino, pero NO sustituye
    -- la regla de asignación congelada. Tras validar el dominio se continúa
    -- por property_responsible / fixed_person / role para evitar que un
    -- antiguo asignado conserve capacidad solo por tener write access.
    if not private.incident_internal_access_v1(
        v_execution.organization_id,v_execution.property_id,v_actor,true
      )
      or not exists(
        select 1
        from public.incidents_v2 i
        join public.workflow_event_outbox_v2 ev
          on ev.id=v_execution.source_event_id
         and ev.source_kind='incident'
         and ev.source_id=i.id
         and ev.organization_id=i.organization_id
         and ev.property_id=i.property_id
         and ev.room_id is not distinct from i.room_id
        where i.id=v_execution.incident_id
          and i.organization_id=v_execution.organization_id
          and i.property_id=v_execution.property_id
          and (
            v_execution.scope_type<>'room'
            or i.room_id is not distinct from v_execution.room_id
          )
          and (
            v_execution.spec_snapshot->>'flowType'<>'inspection'
            or i.status='resolved'
          )
      ) then
      return false;
    end if;
  end if;

  if v_execution.assignment_type='property_responsible' then
    return exists(
      select 1
      from public.property_staff_access_v3 a
      join public.user_roles ur
        on ur.user_id=a.employee_user_id
       and ur.organization_id=v_execution.organization_id
       and ur.role in ('admin','employee')
       and ur.revoked_at is null
      where a.property_id=v_execution.property_id
        and a.employee_user_id=v_actor
        and a.assignment_type='responsible'
        and a.can_write=true
        and a.revoked_at is null
        and (a.valid_until is null or a.valid_until>now())
    );
  end if;

  if v_execution.assignment_type='fixed_person' then
    return v_execution.spec_snapshot->>'assignmentUserId'=v_actor::text
      and private.workflow_assignee_eligible_v1(
        v_execution.organization_id,v_execution.scope_type,
        v_execution.property_id,v_execution.room_id,v_execution.occupancy_id,
        v_actor,null
      );
  end if;

  if v_execution.assignment_type='role' then
    if coalesce(v_execution.spec_snapshot->>'assignmentRole','')
      not in ('admin','employee','tenant') then
      return false;
    end if;
    return private.workflow_assignee_eligible_v1(
      v_execution.organization_id,v_execution.scope_type,
      v_execution.property_id,v_execution.room_id,v_execution.occupancy_id,
      v_actor,v_execution.spec_snapshot->>'assignmentRole'
    );
  end if;

  if v_execution.assignment_type='active_occupants_rotation' then
    return private.workflow_assignee_eligible_v1(
      v_execution.organization_id,v_execution.scope_type,
      v_execution.property_id,v_execution.room_id,v_execution.occupancy_id,
      v_actor,'tenant'
    );
  end if;

  if v_execution.assignment_type<>'manual' then
    return false;
  end if;

  if v_execution.scope_type='organization' then
    return exists(
      select 1 from public.user_roles ur
      where ur.user_id=v_actor
        and ur.organization_id=v_execution.organization_id
        and ur.role in ('admin','employee')
        and ur.revoked_at is null
    );
  end if;

  if v_execution.scope_type in ('property','room')
    and exists(
      select 1
      from public.property_staff_access_v3 a
      join public.user_roles ur
        on ur.user_id=a.employee_user_id
       and ur.organization_id=v_execution.organization_id
       and ur.role in ('admin','employee')
       and ur.revoked_at is null
      where a.property_id=v_execution.property_id
        and a.employee_user_id=v_actor
        and a.assignment_type in ('responsible','access')
        and a.revoked_at is null
        and (a.valid_until is null or a.valid_until>now())
    ) then
    return true;
  end if;

  if v_execution.scope_type in ('property','room') then
    return exists(
      select 1
      from public.occupancies_v2 o
      join public.tenants_v2 t
        on t.id=o.tenant_id
       and t.organization_id=o.organization_id
      where o.organization_id=v_execution.organization_id
        and o.property_id=v_execution.property_id
        and (v_execution.scope_type<>'room' or o.room_id=v_execution.room_id)
        and o.status='active'
        and o.starts_on is not null
        and o.starts_on<=current_date
        and (o.ends_on is null or o.ends_on>=current_date)
        and o.user_id=v_actor
        and t.user_id=v_actor
        and t.status='active'
        and t.archived_at is null
    );
  end if;

  if v_execution.scope_type='occupancy'
    and v_execution.occupancy_id is not null then
    return exists(
      select 1
      from public.occupancies_v2 o
      join public.tenants_v2 t
        on t.id=o.tenant_id
       and t.organization_id=o.organization_id
      where o.id=v_execution.occupancy_id
        and o.organization_id=v_execution.organization_id
        and o.property_id=v_execution.property_id
        and o.status='active'
        and o.starts_on is not null
        and o.starts_on<=current_date
        and (o.ends_on is null or o.ends_on>=current_date)
        and o.user_id=v_actor
        and t.user_id=v_actor
        and t.status='active'
        and t.archived_at is null
    );
  end if;
  return false;
end;
$$;

-- Un incidente solo puede tener un gestor maintenance canónico por destino
-- efectivo. Una aplicación property solapa cualquier room del mismo piso;
-- dos aplicaciones room solo solapan cuando apuntan a la misma habitación.
-- Las inspecciones incident.resolved conservan fan-out.
create function private.workflow_wf05_guard_management_overlap_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $wf05_management_overlap$
declare
  v_spec jsonb;
begin
  if new.status<>'configured' then
    return new;
  end if;

  select wv.spec
  into v_spec
  from public.workflow_definition_versions_v2 wv
  where wv.id=new.definition_version_id
    and wv.definition_id=new.definition_id
    and wv.organization_id=new.organization_id;

  if v_spec is null
    or v_spec->>'triggerType'<>'event'
    or v_spec->>'eventType'<>'incident.created'
    or v_spec->>'flowType'<>'maintenance'
    or v_spec->>'closeType'<>'domain_adapter' then
    return new;
  end if;

  if new.scope_type not in ('property','room') or new.property_id is null then
    raise exception 'workflow_wf05_management_scope_invalid' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'wf05-management:'||new.organization_id::text||':'||new.property_id::text,
      0
    )
  );

  if exists(
    select 1
    from public.workflow_applications_v2 a
    join public.workflow_definition_versions_v2 wv
      on wv.id=a.definition_version_id
     and wv.definition_id=a.definition_id
     and wv.organization_id=a.organization_id
    join public.workflow_definitions_v2 d
      on d.id=a.definition_id
     and d.organization_id=a.organization_id
    where a.id is distinct from new.id
      and a.organization_id=new.organization_id
      and a.status='configured'
      and d.status='published'
      and a.property_id=new.property_id
      and wv.spec->>'triggerType'='event'
      and wv.spec->>'eventType'='incident.created'
      and wv.spec->>'flowType'='maintenance'
      and wv.spec->>'closeType'='domain_adapter'
      and (
        new.scope_type='property'
        or a.scope_type='property'
        or (
          new.scope_type='room'
          and a.scope_type='room'
          and a.room_id is not distinct from new.room_id
        )
      )
  ) then
    raise exception 'workflow_wf05_management_application_conflict'
      using errcode='55000';
  end if;

  return new;
end;
$wf05_management_overlap$;

revoke all on function private.workflow_wf05_guard_management_overlap_v1()
  from public,anon,authenticated,service_role;

drop trigger if exists workflow_wf05_guard_management_overlap_v1
  on public.workflow_applications_v2;
create trigger workflow_wf05_guard_management_overlap_v1
before insert or update of
  status,definition_version_id,definition_id,organization_id,
  scope_type,property_id,room_id
on public.workflow_applications_v2
for each row
execute function private.workflow_wf05_guard_management_overlap_v1();

-- Wrapper del ejecutor: los eventos occupancy conservan exactamente WF-04;
-- solo incident.* usa la rama nueva y el mismo núcleo materializador WF-02.
alter function private.workflow_execute_application_internal_v1(
  uuid,text,uuid,text,uuid
) rename to workflow_execute_application_pre_wf05_internal_v1;
revoke all on function private.workflow_execute_application_pre_wf05_internal_v1(
  uuid,text,uuid,text,uuid
) from public,anon,authenticated,service_role;

create function private.workflow_execute_application_internal_v1(
  p_application_id uuid,
  p_idempotency_key text,
  p_assigned_user_id uuid,
  p_trigger_kind text,
  p_actor_user_id uuid
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
set search_path=''
as $$
declare
  v_event public.workflow_event_outbox_v2;
  v_incident public.incidents_v2;
  v_scope text;
  v_property uuid;
  v_room uuid;
  v_event_type text;
  v_flow text;
  v_close text;
  v_key_uuid text;
  v_result record;
  v_previous_event uuid;
  v_previous_incident uuid;
  v_task public.tenant_tasks_v2;
begin
  if p_trigger_kind<>'event' then
    return query select *
    from private.workflow_execute_application_pre_wf05_internal_v1(
      p_application_id,p_idempotency_key,p_assigned_user_id,
      p_trigger_kind,p_actor_user_id
    );
    return;
  end if;

  v_key_uuid:=substring(
    p_idempotency_key from
    '^event:([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$'
  );
  if v_key_uuid is null then
    raise exception 'workflow_event_key_invalid' using errcode='22023';
  end if;
  select * into v_event
  from public.workflow_event_outbox_v2
  where id=v_key_uuid::uuid;

  if v_event.id is null then
    raise exception 'workflow_event_not_found' using errcode='P0002';
  end if;
  if v_event.source_kind<>'incident' then
    return query select *
    from private.workflow_execute_application_pre_wf05_internal_v1(
      p_application_id,p_idempotency_key,p_assigned_user_id,
      p_trigger_kind,p_actor_user_id
    );
    return;
  end if;

  select a.scope_type,a.property_id,a.room_id,
         wv.spec->>'eventType',wv.spec->>'flowType',wv.spec->>'closeType'
  into v_scope,v_property,v_room,v_event_type,v_flow,v_close
  from public.workflow_applications_v2 a
  join public.workflow_definition_versions_v2 wv
    on wv.id=a.definition_version_id
   and wv.definition_id=a.definition_id
   and wv.organization_id=a.organization_id
  where a.id=p_application_id
    and a.organization_id=v_event.organization_id;

  if v_scope not in ('property','room')
    or v_event_type is distinct from v_event.event_type
    or v_property is distinct from v_event.property_id
    or (v_scope='room' and v_room is distinct from v_event.room_id)
    or not (
      (v_event.event_type='incident.created'
        and v_flow='maintenance' and v_close='domain_adapter')
      or (v_event.event_type='incident.resolved'
        and v_flow='inspection' and v_close in ('auto','human_review'))
    ) then
    raise exception 'workflow_event_destination_mismatch' using errcode='42501';
  end if;

  select * into v_incident
  from public.incidents_v2
  where id=v_event.source_id;
  if v_incident.id is null
    or v_event.source_id is distinct from v_incident.id
    or v_event.organization_id is distinct from v_incident.organization_id
    or v_event.property_id is distinct from v_incident.property_id
    or v_event.room_id is distinct from v_incident.room_id
    or v_event.occupancy_id is distinct from v_incident.opened_occupancy_id
    or (v_event.event_type='incident.created' and v_incident.status<>'reported')
    or (v_event.event_type='incident.resolved' and v_incident.status<>'resolved') then
    raise exception 'workflow_incident_subject_mismatch' using errcode='55000';
  end if;

  select * into v_result
  from private.workflow_execute_application_wf02_internal_v1(
    p_application_id,p_idempotency_key,p_assigned_user_id,
    p_trigger_kind,p_actor_user_id
  );
  if v_result.execution_id is null then
    raise exception 'workflow_execution_not_created' using errcode='55000';
  end if;

  select e.source_event_id,e.incident_id
  into v_previous_event,v_previous_incident
  from public.workflow_executions_v2 e
  where e.id=v_result.execution_id
  for update;
  if (v_previous_event is not null and v_previous_event<>v_event.id)
    or (v_previous_incident is not null and v_previous_incident<>v_incident.id) then
    raise exception 'workflow_incident_source_conflict' using errcode='55000';
  end if;

  update public.workflow_executions_v2
  set source_event_id=coalesce(source_event_id,v_event.id),
      incident_id=coalesce(incident_id,v_incident.id)
  where id=v_result.execution_id;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_result.execution_id
  for update;
  if v_task.id is null
    or v_task.organization_id is distinct from v_incident.organization_id
    or v_task.property_id is distinct from v_incident.property_id
    or (v_scope='room' and v_task.room_id is distinct from v_incident.room_id)
    or v_task.tenant_id is not null
    or v_task.assigned_user_id is distinct from v_result.assigned_user_id then
    raise exception 'workflow_incident_task_identity_mismatch' using errcode='55000';
  end if;

  if v_previous_event is null then
    insert into public.workflow_execution_events_v2(
      execution_id,organization_id,event_type,from_status,to_status,
      actor_user_id,details
    ) values (
      v_result.execution_id,v_incident.organization_id,'event_subject_bound',
      v_result.status,v_result.status,p_actor_user_id,
      jsonb_build_object(
        'source_event_id',v_event.id,
        'event_type',v_event.event_type,
        'incident_id',v_incident.id,
        'incident_kind',v_incident.incident_kind
      )
    );
    insert into public.audit_log_v2(
      organization_id,actor_user_id,action,entity_type,entity_id,result,details
    ) values (
      v_incident.organization_id,p_actor_user_id,
      'workflow_incident_subject_bound','workflow_execution',
      v_result.execution_id::text,'success',
      jsonb_build_object(
        'source_event_id',v_event.id,
        'incident_id',v_incident.id,
        'event_type',v_event.event_type
      )
    );
  end if;

  return query select
    v_result.execution_id::uuid,v_result.status::text,
    v_result.assigned_user_id::uuid,v_result.created_at::timestamptz,
    v_result.created_new::boolean;
end;
$$;
revoke all on function private.workflow_execute_application_internal_v1(
  uuid,text,uuid,text,uuid
) from public,anon,authenticated,service_role;

comment on function public.workflow_authoring_complete_v1(jsonb) is
  'Validador transversal + WF-04 + WF-05. incident.created exige maintenance/domain_adapter; incident.resolved exige inspection con evidencia común.';
comment on column public.workflow_executions_v2.incident_id is
  'WF-05 subject binding for both maintenance management and optional downstream inspection.';
