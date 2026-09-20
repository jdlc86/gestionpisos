-- WF-04: conservar el sujeto de cada ejecución por evento sin cambiar el
-- scope de la aplicación (piso/habitación) ni crear una segunda tarjeta.

alter table public.workflow_executions_v2
  add column source_event_id uuid
    references public.workflow_event_outbox_v2(id) on delete restrict;

create unique index workflow_executions_v2_application_source_event_uq
  on public.workflow_executions_v2(application_id,source_event_id)
  where source_event_id is not null;

alter function private.workflow_execute_application_internal_v1(
  uuid,text,uuid,text,uuid
) rename to workflow_execute_application_wf02_internal_v1;
revoke all on function private.workflow_execute_application_wf02_internal_v1(
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
  v_occupancy public.occupancies_v2;
  v_scope_type text;
  v_property_id uuid;
  v_room_id uuid;
  v_event_type text;
  v_flow_type text;
  v_close_type text;
  v_key_uuid text;
  v_result record;
  v_previous_event_id uuid;
  v_task public.tenant_tasks_v2;
begin
  if p_trigger_kind='event' then
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

    select a.scope_type,a.property_id,a.room_id,
           wv.spec->>'eventType',wv.spec->>'flowType',wv.spec->>'closeType'
    into v_scope_type,v_property_id,v_room_id,
         v_event_type,v_flow_type,v_close_type
    from public.workflow_applications_v2 a
    join public.workflow_definition_versions_v2 wv
      on wv.id=a.definition_version_id
     and wv.definition_id=a.definition_id
     and wv.organization_id=a.organization_id
    where a.id=p_application_id
      and a.organization_id=v_event.organization_id;

    if v_scope_type is null
      or v_event_type is distinct from v_event.event_type
      or v_event.source_kind<>'occupancy'
      or v_event.source_id is distinct from v_event.occupancy_id
      or not (
        v_scope_type='organization'
        or (v_scope_type='property' and v_property_id=v_event.property_id)
        or (v_scope_type='room'
            and v_property_id=v_event.property_id
            and v_room_id=v_event.room_id)
      ) then
      raise exception 'workflow_event_destination_mismatch' using errcode='42501';
    end if;

    select * into v_occupancy
    from public.occupancies_v2
    where id=v_event.occupancy_id;
    if v_occupancy.id is null
      or v_occupancy.organization_id is distinct from v_event.organization_id
      or v_occupancy.property_id is distinct from v_event.property_id
      or v_occupancy.room_id is distinct from v_event.room_id then
      raise exception 'workflow_event_subject_mismatch' using errcode='55000';
    end if;

    if v_close_type='domain_adapter' and v_flow_type in ('checkin','checkout') then
      if v_occupancy.tenant_id is null
        or (v_flow_type='checkin'
            and (v_event.event_type<>'occupancy.created'
                 or v_occupancy.status<>'active'))
        or (v_flow_type='checkout'
            and (v_event.event_type<>'occupancy.offboarded'
                 or v_occupancy.status<>'archived')) then
        raise exception 'workflow_domain_lifecycle_mismatch' using errcode='55000';
      end if;
    end if;
  end if;

  select * into v_result
  from private.workflow_execute_application_wf02_internal_v1(
    p_application_id,p_idempotency_key,p_assigned_user_id,
    p_trigger_kind,p_actor_user_id
  );

  if v_result.execution_id is null then
    raise exception 'workflow_execution_not_created' using errcode='55000';
  end if;

  if v_event.id is not null then
    select e.source_event_id into v_previous_event_id
    from public.workflow_executions_v2 e
    where e.id=v_result.execution_id
    for update;
    if v_previous_event_id is not null
      and v_previous_event_id<>v_event.id then
      raise exception 'workflow_event_source_conflict' using errcode='55000';
    end if;

    update public.workflow_executions_v2
    set source_event_id=v_event.id
    where id=v_result.execution_id
      and source_event_id is null;

    select * into v_task
    from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=v_result.execution_id
    for update;
    if v_task.id is null
      or v_task.organization_id is distinct from v_event.organization_id
      or v_task.assigned_user_id is distinct from v_result.assigned_user_id
      or (v_occupancy.tenant_id is not null
          and v_task.tenant_id is not null
          and v_task.tenant_id<>v_occupancy.tenant_id) then
      raise exception 'workflow_event_task_identity_mismatch' using errcode='55000';
    end if;

    if v_occupancy.tenant_id is not null and v_task.tenant_id is null then
      update public.tenant_tasks_v2
      set tenant_id=v_occupancy.tenant_id
      where id=v_task.id;
    end if;

    if v_previous_event_id is null then
      insert into public.workflow_execution_events_v2(
        execution_id,organization_id,event_type,from_status,to_status,
        actor_user_id,details
      ) values (
        v_result.execution_id,v_event.organization_id,'event_subject_bound',
        v_result.status,v_result.status,p_actor_user_id,
        jsonb_build_object(
          'source_event_id',v_event.id,
          'event_type',v_event.event_type,
          'occupancy_id',v_occupancy.id,
          'tenant_id',v_occupancy.tenant_id
        )
      );

      insert into public.audit_log_v2(
        organization_id,actor_user_id,action,entity_type,entity_id,result,details
      ) values (
        v_event.organization_id,p_actor_user_id,
        'workflow_event_subject_bound','workflow_execution',
        v_result.execution_id::text,'success',
        jsonb_build_object(
          'source_event_id',v_event.id,
          'occupancy_id',v_occupancy.id,
          'tenant_id',v_occupancy.tenant_id
        )
      );
    end if;
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

comment on column public.workflow_executions_v2.source_event_id is
  'Evento de negocio exacto que activó la ejecución; para WF-04 permite resolver la ocupación sin convertir el ámbito de la aplicación en otra identidad.';
