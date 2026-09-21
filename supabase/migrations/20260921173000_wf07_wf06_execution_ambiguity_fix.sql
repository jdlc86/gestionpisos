-- GestionPisos · WF-07 · corrección aditiva de ambigüedad en ejecutor WF-06
-- WF-06 ya está aplicado en producción. No se modifica su migración histórica:
-- se reemplaza la función que WF-07 renombró a *_pre_wf07_internal_v1.
-- La única corrección semántica es calificar columnas de ocupación/inquilino
-- que colisionan con el parámetro OUT "status" de RETURNS TABLE.

create or replace function private.workflow_execute_application_pre_wf07_internal_v1(
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
    from public.workflow_executions_v2 e
    where e.id=v_result.execution_id
    for update;

    if v_execution.payment_obligation_id is null then
      select o.* into v_occupancy
      from public.occupancies_v2 o
      where o.id=v_execution.occupancy_id
        and o.organization_id=v_execution.organization_id
        and o.property_id=v_execution.property_id
        and o.status='active'
        and o.starts_on is not null
        and o.starts_on<=current_date
        and (o.ends_on is null or o.ends_on>=current_date)
      for share;
      if v_occupancy.id is null or v_occupancy.user_id is null then
        raise exception 'workflow_wf06_occupancy_not_current' using errcode='55000';
      end if;

      select t.* into v_tenant
      from public.tenants_v2 t
      where t.id=v_occupancy.tenant_id
        and t.organization_id=v_execution.organization_id
        and t.user_id=v_occupancy.user_id
        and t.status='active'
        and t.archived_at is null;
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

      update public.workflow_executions_v2 e
      set payment_obligation_id=v_obligation.id,
          updated_at=clock_timestamp()
      where e.id=v_execution.id
      returning * into v_execution;

      select t.* into v_task
      from public.tenant_tasks_v2 t
      where t.source_kind='workflow_execution'
        and t.source_id=v_execution.id
      for update;
      if v_task.id is null
        or v_task.tenant_id is distinct from v_occupancy.tenant_id
        or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
        raise exception 'workflow_wf06_task_identity_mismatch' using errcode='55000';
      end if;

      update public.tenant_tasks_v2 t
      set title='Pago · '||v_obligation.concept,
          description=concat(
            v_obligation.concept,' · ',
            trim(to_char(v_obligation.amount_cents/100.0,'FM9999999990D00')),
            ' ',v_obligation.currency,
            ' · vence ',to_char(v_obligation.due_date,'DD/MM/YYYY')
          ),
          due_at=(v_obligation.due_date + time '23:59:59') at time zone v_timezone,
          updated_at=clock_timestamp()
      where t.id=v_task.id
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
      select o.* into v_obligation
      from public.payment_obligations_v2 o
      where o.id=v_execution.payment_obligation_id;
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
    select o.* into v_event
    from public.workflow_event_outbox_v2 o
    where o.id=substring(
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

      select c.* into v_claim
      from public.claims_v2 c
      where c.id=v_event.source_id;
      if v_claim.id is null
        or v_claim.claim_type<>'payment'
        or v_claim.organization_id is distinct from v_event.organization_id
        or v_claim.property_id is distinct from v_event.property_id
        or v_claim.occupancy_id is distinct from v_event.occupancy_id
        or v_claim.status<>'draft' then
        raise exception 'workflow_wf06_claim_subject_mismatch' using errcode='55000';
      end if;

      select o.* into v_obligation
      from public.payment_obligations_v2 o
      where o.id=v_claim.obligation_id;
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

      update public.workflow_executions_v2 e
      set source_event_id=coalesce(e.source_event_id,v_event.id),
          rent_claim_id=coalesce(e.rent_claim_id,v_claim.id),
          payment_obligation_id=coalesce(e.payment_obligation_id,v_obligation.id),
          updated_at=clock_timestamp()
      where e.id=v_result.execution_id
      returning * into v_execution;

      select o.* into v_occupancy
      from public.occupancies_v2 o
      where o.id=v_claim.occupancy_id
        and o.organization_id=v_claim.organization_id;

      select t.* into v_task
      from public.tenant_tasks_v2 t
      where t.source_kind='workflow_execution'
        and t.source_id=v_execution.id
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

      update public.tenant_tasks_v2 t
      set tenant_id=v_occupancy.tenant_id,
          title='Reclamación · '||v_obligation.concept,
          description=v_claim.body,
          due_at=null,
          updated_at=clock_timestamp()
      where t.id=v_task.id
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

revoke all on function private.workflow_execute_application_pre_wf07_internal_v1(
  uuid,text,uuid,text,uuid
) from public,anon,authenticated,service_role;

comment on function private.workflow_execute_application_pre_wf07_internal_v1(
  uuid,text,uuid,text,uuid
) is
  'WF-06 encapsulado por WF-07; corrección aditiva de referencias ambiguas status/columnas sin alterar la semántica del dominio.';
