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
      -- Una ocupación legacy todavía sin tenant puede vincularse más tarde:
      -- se mantiene reintentable y no se clasifica como lifecycle terminal.
      if v_occupancy.tenant_id is null then
        raise exception 'workflow_event_subject_unlinked' using errcode='55000';
      end if;

      if (v_flow_type='checkin'
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


-- Un evento de Entrada puede quedar obsoleto si la ocupación se da de Baja
-- antes de que el dispatcher lo consuma. Ese mismatch de lifecycle es terminal:
-- reintentarlo nunca podrá revivir esa ocupación histórica y podría bloquear
-- los lotes más antiguos. Los demás fallos continúan siendo reintentables.
create or replace function private.process_pending_workflow_events_v1(
  p_limit integer default 50
)
returns integer
language plpgsql
security definer
set search_path=''
as $workflow_process_events_wf04$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),500);
  v_event public.workflow_event_outbox_v2;
  v_app record;
  v_execution_id uuid;
  v_execution_status text;
  v_execution_assignee uuid;
  v_execution_created_at timestamptz;
  v_created_new boolean;
  v_retryable_errors integer;
  v_terminal_errors integer;
  v_prior_status text;
  v_prior_error_key text;
  v_processed integer:=0;
  v_key text;
  v_error_code text;
  v_error_key text;
  v_terminal boolean;
begin
  for v_event in
    select e.*
    from public.workflow_event_outbox_v2 e
    where e.status='pending'
    order by e.occurred_at,e.id
    limit v_limit
    for update skip locked
  loop
    v_retryable_errors:=0;
    v_terminal_errors:=0;

    for v_app in
      select
        a.id as application_id,
        a.created_by,
        a.scope_type,
        a.property_id,
        a.room_id,
        a.occupancy_id
      from public.workflow_applications_v2 a
      join public.workflow_definition_versions_v2 wv
        on wv.id=a.definition_version_id
       and wv.definition_id=a.definition_id
       and wv.organization_id=a.organization_id
      join public.workflow_definitions_v2 d
        on d.id=a.definition_id
       and d.organization_id=a.organization_id
      where a.organization_id=v_event.organization_id
        and a.status='configured'
        and d.status='published'
        and a.created_at<=v_event.occurred_at
        and wv.published_at<=v_event.occurred_at
        and wv.spec->>'triggerType'='event'
        and wv.spec->>'eventType'=v_event.event_type
        and (
          a.scope_type='organization'
          or (
            a.scope_type='property'
            and a.property_id=v_event.property_id
          )
          or (
            a.scope_type='room'
            and a.property_id=v_event.property_id
            and a.room_id=v_event.room_id
          )
          or (
            a.scope_type='occupancy'
            and a.occupancy_id=v_event.occupancy_id
          )
        )
      order by a.id
    loop
      select d.status,d.error_key
      into v_prior_status,v_prior_error_key
      from public.workflow_event_dispatches_v2 d
      where d.event_id=v_event.id
        and d.application_id=v_app.application_id;

      if v_prior_status='executed' then
        continue;
      end if;

      -- Ya se clasificó como terminal en una pasada anterior mientras otra
      -- aplicación del mismo evento seguía siendo reintentable.
      if v_prior_status='failed'
        and v_prior_error_key='workflow_domain_lifecycle_mismatch' then
        v_terminal_errors:=v_terminal_errors+1;
        continue;
      end if;

      v_key:='event:'||v_event.id::text;

      begin
        select x.execution_id,x.status,x.assigned_user_id,x.created_at,x.created_new
        into v_execution_id,v_execution_status,v_execution_assignee,
             v_execution_created_at,v_created_new
        from private.workflow_execute_application_internal_v1(
          v_app.application_id,
          v_key,
          null,
          'event',
          v_app.created_by
        ) x
        limit 1;

        insert into public.workflow_event_dispatches_v2(
          event_id,application_id,execution_id,status
        ) values (
          v_event.id,v_app.application_id,v_execution_id,'executed'
        )
        on conflict(event_id,application_id) do update
        set execution_id=excluded.execution_id,
            status='executed',
            error_code=null,
            error_key=null;

        insert into public.audit_log_v2(
          organization_id,actor_user_id,action,entity_type,entity_id,result,details
        ) values (
          v_event.organization_id,v_app.created_by,
          'workflow_event_dispatched','workflow_event',v_event.id::text,'success',
          jsonb_build_object(
            'event_type',v_event.event_type,
            'source_kind',v_event.source_kind,
            'source_id',v_event.source_id,
            'application_id',v_app.application_id,
            'execution_id',v_execution_id
          )
        );
      exception when others then
        v_error_code:=sqlstate;
        v_error_key:=left(sqlerrm,120);
        v_terminal:=v_error_code='55000'
          and v_error_key='workflow_domain_lifecycle_mismatch';

        if v_terminal then
          v_terminal_errors:=v_terminal_errors+1;
        else
          v_retryable_errors:=v_retryable_errors+1;
        end if;

        insert into public.workflow_event_dispatches_v2(
          event_id,application_id,status,error_code,error_key
        ) values (
          v_event.id,v_app.application_id,'failed',v_error_code,v_error_key
        )
        on conflict(event_id,application_id) do update
        set execution_id=null,
            status='failed',
            error_code=excluded.error_code,
            error_key=excluded.error_key;

        if v_prior_status is distinct from 'failed' then
          insert into public.audit_log_v2(
            organization_id,actor_user_id,action,entity_type,entity_id,result,details
          ) values (
            v_event.organization_id,v_app.created_by,
            case when v_terminal
              then 'workflow_event_dispatch_skipped'
              else 'workflow_event_dispatch_failed' end,
            'workflow_event',v_event.id::text,
            case when v_terminal then 'skipped' else 'failure' end,
            jsonb_build_object(
              'event_type',v_event.event_type,
              'source_kind',v_event.source_kind,
              'source_id',v_event.source_id,
              'application_id',v_app.application_id,
              'sqlstate',v_error_code,
              'error_key',v_error_key
            )
          );
        end if;
      end;
    end loop;

    update public.workflow_event_outbox_v2
    set status=case
          when v_retryable_errors>0 then 'pending'
          when v_terminal_errors>0 then 'processed_with_errors'
          else 'processed'
        end,
        processed_at=case
          when v_retryable_errors>0 then null
          else now()
        end
    where id=v_event.id;

    v_processed:=v_processed+1;
  end loop;

  return v_processed;
end;
$workflow_process_events_wf04$;

revoke all on function private.process_pending_workflow_events_v1(integer)
  from public,anon,authenticated,service_role;

comment on function private.process_pending_workflow_events_v1(integer) is
  'Despacha eventos WF-02. WF-04 trata workflow_domain_lifecycle_mismatch como fallo terminal procesado con errores; los fallos recuperables permanecen pending para reintento.';
