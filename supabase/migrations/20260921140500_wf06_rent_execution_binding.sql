-- GestionPisos · WF-06 · enlace de ejecuciones a obligaciones y reclamaciones
-- Extiende el ejecutor transversal sin alterar los caminos WF-00..WF-05.

create or replace function private.workflow_wf06_seed_payment_actions_v1(
  p_execution_id uuid
)
returns void
language plpgsql
security definer
set search_path=''
as $wf06_seed_payment$
declare
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
begin
  select * into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id;

  if v_execution.id is null
    or v_execution.spec_snapshot->>'flowType'<>'rent_payment'
    or v_execution.spec_snapshot->>'closeType'<>'domain_adapter'
    or v_execution.payment_obligation_id is null then
    return;
  end if;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id;

  if v_task.id is null then
    raise exception 'workflow_wf06_task_missing' using errcode='55000';
  end if;

  insert into public.tenant_task_actions_v2(
    task_id,action_key,label,from_status,to_status,
    requires_note,sort_order,active,actor
  ) values
    (v_task.id,'request_payment','Solicitar pago','pending','active',false,10,true,'assignee'),
    (v_task.id,'postpone','Aplazar','pending','pending',true,20,true,'assignee'),
    (v_task.id,'register_payment','Registrar pago','pending','completed',false,30,true,'assignee'),
    (v_task.id,'claim','Reclamar alquiler','pending','completed',true,40,true,'assignee'),
    (v_task.id,'request_payment','Reenviar solicitud','active','active',false,10,true,'assignee'),
    (v_task.id,'postpone','Aplazar','active','active',true,20,true,'assignee'),
    (v_task.id,'register_payment','Registrar pago','active','completed',false,30,true,'assignee'),
    (v_task.id,'claim','Reclamar alquiler','active','completed',true,40,true,'assignee')
  on conflict(task_id,action_key,from_status)
  do update set
    label=excluded.label,
    to_status=excluded.to_status,
    requires_note=excluded.requires_note,
    sort_order=excluded.sort_order,
    active=true,
    actor=excluded.actor;
end;
$wf06_seed_payment$;

revoke all on function private.workflow_wf06_seed_payment_actions_v1(uuid)
  from public,anon,authenticated,service_role;

create or replace function private.workflow_wf06_seed_claim_actions_v1(
  p_execution_id uuid
)
returns void
language plpgsql
security definer
set search_path=''
as $wf06_seed_claim$
declare
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
begin
  select * into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id;

  if v_execution.id is null
    or v_execution.spec_snapshot->>'flowType'<>'rent_claim'
    or v_execution.spec_snapshot->>'eventType'<>'rent_claim.created'
    or v_execution.spec_snapshot->>'closeType'<>'domain_adapter'
    or v_execution.rent_claim_id is null then
    return;
  end if;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id;

  if v_task.id is null then
    raise exception 'workflow_wf06_task_missing' using errcode='55000';
  end if;

  insert into public.tenant_task_actions_v2(
    task_id,action_key,label,from_status,to_status,
    requires_note,sort_order,active,actor
  ) values
    (v_task.id,'notify','Notificar reclamación','pending','active',false,10,true,'assignee'),
    (v_task.id,'accept','Aceptar reclamación','active','active',false,20,true,'tenant'),
    (v_task.id,'dispute','Disputar reclamación','active','active',true,30,true,'tenant'),
    (v_task.id,'request_info','Solicitar información','active','waiting_info',true,40,true,'assignee'),
    (v_task.id,'resolve','Resolver','active','completed',true,60,false,'assignee'),
    (v_task.id,'provide_info','Aportar información','waiting_info','waiting_info',true,20,true,'tenant'),
    (v_task.id,'continue','Continuar reclamación','waiting_info','active',false,40,true,'assignee')
  on conflict(task_id,action_key,from_status)
  do update set
    label=excluded.label,
    to_status=excluded.to_status,
    requires_note=excluded.requires_note,
    sort_order=excluded.sort_order,
    active=true,
    actor=excluded.actor;
end;
$wf06_seed_claim$;

revoke all on function private.workflow_wf06_seed_claim_actions_v1(uuid)
  from public,anon,authenticated,service_role;

-- El resolver genérico no considera personal interno elegible en scope=occupancy.
-- WF-06 sí necesita esa combinación, pero exclusivamente para rent_payment.
alter function private.workflow_resolve_execution_assignee_v1(uuid,uuid)
  rename to workflow_resolve_execution_assignee_pre_wf06_v1;
revoke all on function private.workflow_resolve_execution_assignee_pre_wf06_v1(uuid,uuid)
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
as $wf06_resolve_assignee$
declare
  v_org uuid;
  v_property uuid;
  v_scope text;
  v_spec jsonb;
  v_flow text;
  v_assignment text;
  v_role text;
  v_user uuid;
begin
  select a.organization_id,a.property_id,a.scope_type,wv.spec
  into v_org,v_property,v_scope,v_spec
  from public.workflow_applications_v2 a
  join public.workflow_definition_versions_v2 wv
    on wv.id=a.definition_version_id
   and wv.definition_id=a.definition_id
   and wv.organization_id=a.organization_id
  where a.id=p_application_id;

  v_flow:=coalesce(v_spec->>'flowType','');
  v_assignment:=coalesce(v_spec->>'assignmentType','');

  if v_flow='rent_payment'
    and v_spec->>'closeType'='domain_adapter' then
    if v_scope<>'occupancy' then
      raise exception 'workflow_wf06_payment_scope_required' using errcode='22023';
    end if;
    if p_requested_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved' using errcode='22023';
    end if;

    if v_assignment='property_responsible' then
      v_user:=private.workflow_resolve_execution_assignee_pre_wf06_v1(
        p_application_id,null
      );
    elsif v_assignment='fixed_person' then
      begin
        v_user:=(v_spec->>'assignmentUserId')::uuid;
      exception when others then
        raise exception 'workflow_fixed_person_invalid' using errcode='22023';
      end;
      if not exists(
        select 1
        from public.user_roles ur
        where ur.user_id=v_user
          and ur.organization_id=v_org
          and ur.role in ('admin','employee')
          and ur.revoked_at is null
      ) or not private.wf06_internal_access_v1(
        v_org,v_property,v_user,true
      ) then
        raise exception 'workflow_wf06_assignee_not_eligible' using errcode='42501';
      end if;
    elsif v_assignment='role' then
      v_role:=coalesce(v_spec->>'assignmentRole','');
      if v_role not in ('admin','employee') then
        raise exception 'workflow_assignment_role_invalid' using errcode='22023';
      end if;
      select ur.user_id
      into v_user
      from public.user_roles ur
      where ur.organization_id=v_org
        and ur.role::text=v_role
        and ur.revoked_at is null
        and private.wf06_internal_access_v1(v_org,v_property,ur.user_id,true)
      order by (
        select count(*)
        from public.workflow_executions_v2 e
        where e.application_id=p_application_id
          and e.assigned_user_id=ur.user_id
      ),(
        select max(e.created_at)
        from public.workflow_executions_v2 e
        where e.application_id=p_application_id
          and e.assigned_user_id=ur.user_id
      ) nulls first,ur.user_id
      limit 1;
      if v_user is null then
        raise exception 'workflow_assignment_role_unavailable' using errcode='55000';
      end if;
    else
      raise exception 'workflow_wf06_assignment_invalid' using errcode='22023';
    end if;

    if v_user is null or not private.wf06_internal_access_v1(
      v_org,v_property,v_user,true
    ) then
      raise exception 'workflow_wf06_assignee_not_eligible' using errcode='42501';
    end if;
    return v_user;
  end if;

  if v_flow='rent_claim'
    and v_spec->>'eventType'='rent_claim.created'
    and v_spec->>'closeType'='domain_adapter' then
    v_user:=private.workflow_resolve_execution_assignee_pre_wf06_v1(
      p_application_id,p_requested_user_id
    );
    if v_user is null or not private.wf06_internal_access_v1(
      v_org,v_property,v_user,true
    ) then
      raise exception 'workflow_wf06_assignee_not_eligible' using errcode='42501';
    end if;
    return v_user;
  end if;

  return private.workflow_resolve_execution_assignee_pre_wf06_v1(
    p_application_id,p_requested_user_id
  );
end;
$wf06_resolve_assignee$;

revoke all on function private.workflow_resolve_execution_assignee_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

alter function private.workflow_execute_application_internal_v1(
  uuid,text,uuid,text,uuid
) rename to workflow_execute_application_pre_wf06_internal_v1;
revoke all on function private.workflow_execute_application_pre_wf06_internal_v1(
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
as $wf06_execute$
declare
  v_spec jsonb;
  v_scope text;
  v_property uuid;
  v_room uuid;
  v_app_occupancy uuid;
  v_result record;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_occupancy public.occupancies_v2;
  v_tenant public.tenants_v2;
  v_obligation public.payment_obligations_v2;
  v_claim public.claims_v2;
  v_event public.workflow_event_outbox_v2;
  v_previous_event uuid;
  v_previous_claim uuid;
  v_amount bigint;
  v_due_days integer;
  v_due_date date;
  v_timezone text;
  v_actor uuid;
begin
  select a.scope_type,a.property_id,a.room_id,a.occupancy_id,wv.spec
  into v_scope,v_property,v_room,v_app_occupancy,v_spec
  from public.workflow_applications_v2 a
  join public.workflow_definition_versions_v2 wv
    on wv.id=a.definition_version_id
   and wv.definition_id=a.definition_id
   and wv.organization_id=a.organization_id
  where a.id=p_application_id;

  if v_spec->>'flowType'='rent_payment'
    and v_spec->>'closeType'='domain_adapter' then
    if p_trigger_kind not in ('manual_now','scheduled_once','recurring')
      or v_scope<>'occupancy'
      or v_app_occupancy is null then
      raise exception 'workflow_wf06_payment_trigger_invalid' using errcode='22023';
    end if;

    select * into v_result
    from private.workflow_execute_application_pre_wf06_internal_v1(
      p_application_id,p_idempotency_key,p_assigned_user_id,
      p_trigger_kind,p_actor_user_id
    );

    select * into v_execution
    from public.workflow_executions_v2
    where id=v_result.execution_id
    for update;

    if v_execution.payment_obligation_id is null then
      select * into v_occupancy
      from public.occupancies_v2
      where id=v_execution.occupancy_id
        and organization_id=v_execution.organization_id
        and property_id=v_execution.property_id
        and status='active'
        and starts_on is not null
        and starts_on<=current_date
        and (ends_on is null or ends_on>=current_date)
      for share;
      if v_occupancy.id is null or v_occupancy.user_id is null then
        raise exception 'workflow_wf06_occupancy_not_current' using errcode='55000';
      end if;

      select * into v_tenant
      from public.tenants_v2
      where id=v_occupancy.tenant_id
        and organization_id=v_execution.organization_id
        and user_id=v_occupancy.user_id
        and status='active'
        and archived_at is null;
      if v_tenant.id is null then
        raise exception 'workflow_wf06_tenant_not_current' using errcode='55000';
      end if;

      v_amount:=(v_execution.spec_snapshot->>'paymentAmountCents')::bigint;
      v_due_days:=(v_execution.spec_snapshot->>'paymentDueDays')::integer;
      v_timezone:=coalesce(
        nullif(v_execution.spec_snapshot->>'scheduledTimezone',''),
        'Europe/Madrid'
      );
      v_due_date:=((v_execution.created_at at time zone v_timezone)::date + v_due_days);

      insert into public.payment_obligations_v2(
        organization_id,property_id,room_id,occupancy_id,tenant_user_id,
        concept,amount_cents,currency,due_date,status,created_by,created_at,updated_at
      ) values (
        v_execution.organization_id,v_execution.property_id,v_occupancy.room_id,
        v_occupancy.id,v_occupancy.user_id,
        v_execution.spec_snapshot->>'paymentConcept',v_amount,
        v_execution.spec_snapshot->>'paymentCurrency',v_due_date,
        'pending',coalesce(p_actor_user_id,v_execution.created_by),
        clock_timestamp(),clock_timestamp()
      )
      returning * into v_obligation;

      update public.workflow_executions_v2
      set payment_obligation_id=v_obligation.id,
          updated_at=clock_timestamp()
      where id=v_execution.id
      returning * into v_execution;

      select * into v_task
      from public.tenant_tasks_v2
      where source_kind='workflow_execution'
        and source_id=v_execution.id
      for update;
      if v_task.id is null
        or v_task.tenant_id is distinct from v_occupancy.tenant_id
        or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
        raise exception 'workflow_wf06_task_identity_mismatch' using errcode='55000';
      end if;

      update public.tenant_tasks_v2
      set title='Pago · '||v_obligation.concept,
          description=concat(
            v_obligation.concept,' · ',
            trim(to_char(v_obligation.amount_cents/100.0,'FM9999999990D00')),
            ' ',v_obligation.currency,
            ' · vence ',to_char(v_obligation.due_date,'DD/MM/YYYY')
          ),
          due_at=(v_obligation.due_date + time '23:59:59') at time zone v_timezone,
          updated_at=clock_timestamp()
      where id=v_task.id
      returning * into v_task;

      perform private.workflow_wf06_seed_payment_actions_v1(v_execution.id);

      insert into public.workflow_execution_events_v2(
        execution_id,organization_id,event_type,from_status,to_status,
        actor_user_id,details
      ) values (
        v_execution.id,v_execution.organization_id,'wf06_payment_bound',
        v_execution.status,v_execution.status,
        coalesce(p_actor_user_id,v_execution.created_by),
        jsonb_build_object(
          'payment_obligation_id',v_obligation.id,
          'occupancy_id',v_occupancy.id,
          'tenant_id',v_occupancy.tenant_id,
          'due_date',v_obligation.due_date,
          'amount_cents',v_obligation.amount_cents,
          'currency',v_obligation.currency
        )
      );

      insert into public.audit_log_v2(
        organization_id,actor_user_id,action,entity_type,entity_id,result,details
      ) values (
        v_execution.organization_id,
        coalesce(p_actor_user_id,v_execution.created_by),
        'workflow_wf06_payment_bound','workflow_execution',
        v_execution.id::text,'success',
        jsonb_build_object(
          'payment_obligation_id',v_obligation.id,
          'occupancy_id',v_occupancy.id,
          'tenant_user_id',v_occupancy.user_id
        )
      );
    else
      select * into v_obligation
      from public.payment_obligations_v2
      where id=v_execution.payment_obligation_id;
      if v_obligation.id is null
        or v_obligation.organization_id is distinct from v_execution.organization_id
        or v_obligation.property_id is distinct from v_execution.property_id
        or v_obligation.occupancy_id is distinct from v_execution.occupancy_id then
        raise exception 'workflow_wf06_payment_source_conflict' using errcode='55000';
      end if;
      perform private.workflow_wf06_seed_payment_actions_v1(v_execution.id);
    end if;

    return query select
      v_result.execution_id::uuid,v_result.status::text,
      v_result.assigned_user_id::uuid,v_result.created_at::timestamptz,
      v_result.created_new::boolean;
    return;
  end if;

  if p_trigger_kind='event' then
    select * into v_event
    from public.workflow_event_outbox_v2
    where id=substring(
      p_idempotency_key from
      '^event:([0-9a-fA-F-]{36})$'
    )::uuid;

    if v_event.id is not null
      and v_event.source_kind='rent_claim'
      and v_event.event_type='rent_claim.created' then

      if v_spec->>'flowType'<>'rent_claim'
        or v_spec->>'eventType'<>'rent_claim.created'
        or v_spec->>'closeType'<>'domain_adapter'
        or v_scope not in ('property','room')
        or v_property is distinct from v_event.property_id
        or (v_scope='room' and v_room is distinct from v_event.room_id) then
        raise exception 'workflow_event_destination_mismatch' using errcode='42501';
      end if;

      select * into v_claim
      from public.claims_v2
      where id=v_event.source_id;
      if v_claim.id is null
        or v_claim.claim_type<>'payment'
        or v_claim.organization_id is distinct from v_event.organization_id
        or v_claim.property_id is distinct from v_event.property_id
        or v_claim.occupancy_id is distinct from v_event.occupancy_id
        or v_claim.status<>'draft' then
        raise exception 'workflow_wf06_claim_subject_mismatch' using errcode='55000';
      end if;

      select * into v_obligation
      from public.payment_obligations_v2
      where id=v_claim.obligation_id;
      if v_obligation.id is null
        or v_obligation.organization_id is distinct from v_claim.organization_id
        or v_obligation.property_id is distinct from v_claim.property_id
        or v_obligation.occupancy_id is distinct from v_claim.occupancy_id
        or v_obligation.tenant_user_id is distinct from v_claim.tenant_user_id
        or v_obligation.status<>'overdue' then
        raise exception 'workflow_wf06_claim_obligation_mismatch' using errcode='55000';
      end if;

      select * into v_result
      from private.workflow_execute_application_wf02_internal_v1(
        p_application_id,p_idempotency_key,p_assigned_user_id,
        p_trigger_kind,p_actor_user_id
      );

      select e.source_event_id,e.rent_claim_id
      into v_previous_event,v_previous_claim
      from public.workflow_executions_v2 e
      where e.id=v_result.execution_id
      for update;

      if (v_previous_event is not null and v_previous_event<>v_event.id)
        or (v_previous_claim is not null and v_previous_claim<>v_claim.id) then
        raise exception 'workflow_wf06_claim_source_conflict' using errcode='55000';
      end if;

      update public.workflow_executions_v2
      set source_event_id=coalesce(source_event_id,v_event.id),
          rent_claim_id=coalesce(rent_claim_id,v_claim.id),
          payment_obligation_id=coalesce(payment_obligation_id,v_obligation.id),
          updated_at=clock_timestamp()
      where id=v_result.execution_id
      returning * into v_execution;

      select * into v_occupancy
      from public.occupancies_v2
      where id=v_claim.occupancy_id
        and organization_id=v_claim.organization_id;

      select * into v_task
      from public.tenant_tasks_v2
      where source_kind='workflow_execution'
        and source_id=v_execution.id
      for update;

      if v_task.id is null
        or v_occupancy.id is null
        or v_occupancy.user_id is distinct from v_claim.tenant_user_id
        or v_task.organization_id is distinct from v_claim.organization_id
        or v_task.property_id is distinct from v_claim.property_id
        or (v_scope='room' and v_task.room_id is distinct from v_event.room_id)
        or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
        raise exception 'workflow_wf06_claim_task_identity_mismatch' using errcode='55000';
      end if;

      update public.tenant_tasks_v2
      set tenant_id=v_occupancy.tenant_id,
          title='Reclamación · '||v_obligation.concept,
          description=v_claim.body,
          due_at=null,
          updated_at=clock_timestamp()
      where id=v_task.id
      returning * into v_task;

      perform private.workflow_wf06_seed_claim_actions_v1(v_execution.id);

      if v_previous_event is null then
        insert into public.workflow_execution_events_v2(
          execution_id,organization_id,event_type,from_status,to_status,
          actor_user_id,details
        ) values (
          v_execution.id,v_execution.organization_id,'wf06_claim_bound',
          v_execution.status,v_execution.status,p_actor_user_id,
          jsonb_build_object(
            'source_event_id',v_event.id,
            'rent_claim_id',v_claim.id,
            'payment_obligation_id',v_obligation.id,
            'occupancy_id',v_claim.occupancy_id
          )
        );
        insert into public.audit_log_v2(
          organization_id,actor_user_id,action,entity_type,entity_id,result,details
        ) values (
          v_execution.organization_id,p_actor_user_id,
          'workflow_wf06_claim_bound','workflow_execution',
          v_execution.id::text,'success',
          jsonb_build_object(
            'rent_claim_id',v_claim.id,
            'payment_obligation_id',v_obligation.id,
            'source_event_id',v_event.id
          )
        );
      end if;

      return query select
        v_result.execution_id::uuid,v_result.status::text,
        v_result.assigned_user_id::uuid,v_result.created_at::timestamptz,
        v_result.created_new::boolean;
      return;
    end if;
  end if;

  return query
  select *
  from private.workflow_execute_application_pre_wf06_internal_v1(
    p_application_id,p_idempotency_key,p_assigned_user_id,
    p_trigger_kind,p_actor_user_id
  );
end;
$wf06_execute$;

revoke all on function private.workflow_execute_application_internal_v1(
  uuid,text,uuid,text,uuid
) from public,anon,authenticated,service_role;

comment on function private.workflow_execute_application_internal_v1(
  uuid,text,uuid,text,uuid
) is
  'Ejecutor transversal + WF-06: rent_payment crea una obligación por ejecución; rent_claim.created enlaza el expediente a la ejecución/tarea común.';
