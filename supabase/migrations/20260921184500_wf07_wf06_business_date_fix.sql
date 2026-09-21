-- GestionPisos · WF-07 · deuda WF-06 de fecha de negocio
--
-- WF-06 calcula due_date usando scheduledTimezone (Europe/Madrid por defecto)
-- pero sus acciones comparaban contra current_date de la sesión PostgreSQL.
-- Cerca de medianoche local eso podía impedir reclamar una obligación ya
-- vencida o validar mal un aplazamiento. Unificamos ambas comparaciones con
-- la misma fecha de negocio de la ejecución.

create or replace function private.wf06_business_date_v1(
  p_timezone text,
  p_at timestamptz default clock_timestamp()
)
returns date
language sql
stable
security definer
set search_path=''
as $wf06_business_date$
  select (p_at at time zone coalesce(nullif(btrim(p_timezone),''),'Europe/Madrid'))::date
$wf06_business_date$;

revoke all on function private.wf06_business_date_v1(text,timestamptz)
  from public,anon,authenticated,service_role;

create or replace function private.apply_wf06_payment_action_v1(
  p_task_id uuid,
  p_action_key text,
  p_request_key text,
  p_note text default null,
  p_effective_date date default null
)
returns table(
  task_id uuid,
  task_status text,
  execution_id uuid,
  execution_status text,
  applied_new boolean
)
language plpgsql
security definer
set search_path=''
as $wf06_payment_action$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_note text:=nullif(btrim(p_note),'');
  v_task public.tenant_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_obligation public.payment_obligations_v2;
  v_action public.tenant_task_actions_v2;
  v_tenant public.tenants_v2;
  v_previous public.workflow_execution_events_v2;
  v_from_status text;
  v_old_due date;
  v_claim public.claims_v2;
  v_claim_event uuid;
  v_claim_app uuid;
  v_timezone text;
  v_business_date date;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_action_request_key_invalid' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      v_actor::text||':wf06-payment:'||p_task_id::text||':'||v_key,0
    )
  );

  select * into v_task
  from public.tenant_tasks_v2
  where id=p_task_id
  for update;
  if v_task.id is null then
    raise exception 'workflow_task_not_found' using errcode='P0002';
  end if;
  if v_task.task_type<>'workflow'
    or v_task.source_kind<>'workflow_execution'
    or v_task.source_id is null then
    raise exception 'workflow_task_required' using errcode='22023';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_task.source_id
  for update;
  if v_execution.id is null
    or v_execution.spec_snapshot->>'flowType'<>'rent_payment'
    or v_execution.spec_snapshot->>'closeType'<>'domain_adapter'
    or v_execution.scope_type<>'occupancy'
    or v_execution.occupancy_id is null
    or v_execution.payment_obligation_id is null then
    raise exception 'workflow_wf06_payment_domain_required' using errcode='22023';
  end if;

  if not private.wf06_execution_internal_actor_current_v1(
    v_execution.id,v_actor
  ) then
    raise exception 'workflow_wf06_assignee_not_eligible' using errcode='42501';
  end if;
  perform private.wf06_require_privileged_aal2_v1(
    v_execution.organization_id,v_actor
  );

  select * into v_obligation
  from public.payment_obligations_v2
  where id=v_execution.payment_obligation_id
  for update;
  if v_obligation.id is null
    or v_obligation.organization_id is distinct from v_execution.organization_id
    or v_obligation.property_id is distinct from v_execution.property_id
    or v_obligation.occupancy_id is distinct from v_execution.occupancy_id then
    raise exception 'workflow_wf06_payment_subject_not_current' using errcode='55000';
  end if;

  select * into v_tenant
  from public.tenants_v2
  where organization_id=v_obligation.organization_id
    and user_id=v_obligation.tenant_user_id
    and status='active'
    and archived_at is null;
  if v_tenant.id is null
    or v_task.tenant_id is distinct from v_tenant.id
    or v_task.organization_id is distinct from v_execution.organization_id
    or v_task.property_id is distinct from v_execution.property_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
    raise exception 'workflow_wf06_payment_task_identity_mismatch' using errcode='55000';
  end if;

  select * into v_previous
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='wf06_payment_action'
    and ev.details->>'request_key'=v_key
  limit 1;
  if v_previous.id is not null then
    if v_previous.details->>'action_key' is distinct from p_action_key
      or v_previous.details->>'task_id' is distinct from p_task_id::text then
      raise exception 'workflow_action_request_key_conflict' using errcode='55000';
    end if;
    return query
    select v_task.id,v_task.status,v_execution.id,v_execution.status,false;
    return;
  end if;

  if v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_state_mismatch' using errcode='55000';
  end if;

  select * into v_action
  from public.tenant_task_actions_v2 a
  where a.task_id=v_task.id
    and a.action_key=p_action_key
    and a.from_status=v_task.status
    and a.active=true
    and a.actor='assignee';
  if v_action.id is null then
    raise exception 'workflow_action_not_allowed' using errcode='22023';
  end if;
  if v_action.requires_note and v_note is null then
    raise exception 'workflow_action_note_required' using errcode='22023';
  end if;

  if v_obligation.status not in ('pending','overdue') then
    raise exception 'workflow_wf06_payment_state_mismatch' using errcode='55000';
  end if;

  v_from_status:=v_task.status;
  v_old_due:=v_obligation.due_date;
  v_timezone:=coalesce(
    nullif(v_execution.spec_snapshot->>'scheduledTimezone',''),
    'Europe/Madrid'
  );
  v_business_date:=private.wf06_business_date_v1(v_timezone);

  if p_action_key='request_payment' then
    if v_action.to_status<>'active' then
      raise exception 'workflow_wf06_transition_mismatch' using errcode='55000';
    end if;

    update public.tenant_tasks_v2
    set status='active',updated_at=clock_timestamp()
    where id=v_task.id
    returning * into v_task;
    update public.workflow_executions_v2
    set status='active',
        started_at=coalesce(started_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_execution.id
    returning * into v_execution;

    insert into public.notifications_v2(
      organization_id,recipient_user_id,event_type,title,body,status,
      channel_in_app,channel_email,source_kind,source_id,event_key
    ) values (
      v_obligation.organization_id,v_obligation.tenant_user_id,
      'rent_payment_requested','Pago solicitado',
      concat(
        v_obligation.concept,' · ',
        trim(to_char(v_obligation.amount_cents/100.0,'FM9999999990D00')),
        ' ',v_obligation.currency,' · vence ',
        to_char(v_obligation.due_date,'DD/MM/YYYY')
      ),
      'pending',true,false,'payment_obligation',v_obligation.id,
      'requested:'||v_key
    )
    on conflict (source_kind,source_id,event_key,recipient_user_id)
    where source_kind is not null and source_id is not null and event_key is not null
    do nothing;

  elsif p_action_key='postpone' then
    if v_action.to_status<>v_task.status then
      raise exception 'workflow_wf06_transition_mismatch' using errcode='55000';
    end if;
    if p_effective_date is null
      or p_effective_date<=greatest(v_obligation.due_date,v_business_date) then
      raise exception 'workflow_wf06_postpone_date_invalid' using errcode='22023';
    end if;

    update public.payment_obligations_v2
    set due_date=p_effective_date,
        status=case when status='overdue' then 'pending' else status end,
        updated_at=clock_timestamp()
    where id=v_obligation.id
    returning * into v_obligation;

    update public.tenant_tasks_v2
    set due_at=(v_obligation.due_date + time '23:59:59') at time zone v_timezone,
        updated_at=clock_timestamp()
    where id=v_task.id
    returning * into v_task;

    insert into public.notifications_v2(
      organization_id,recipient_user_id,event_type,title,body,status,
      channel_in_app,channel_email,source_kind,source_id,event_key
    ) values (
      v_obligation.organization_id,v_obligation.tenant_user_id,
      'rent_payment_postponed','Pago aplazado',
      concat(
        'Nuevo vencimiento: ',to_char(v_obligation.due_date,'DD/MM/YYYY'),
        '. ',v_note
      ),
      'pending',true,false,'payment_obligation',v_obligation.id,
      'postponed:'||v_key
    )
    on conflict (source_kind,source_id,event_key,recipient_user_id)
    where source_kind is not null and source_id is not null and event_key is not null
    do nothing;

  elsif p_action_key='register_payment' then
    if v_action.to_status<>'completed' then
      raise exception 'workflow_wf06_transition_mismatch' using errcode='55000';
    end if;

    update public.payment_obligations_v2
    set status='paid',paid_at=clock_timestamp(),updated_at=clock_timestamp()
    where id=v_obligation.id
    returning * into v_obligation;

    update public.tenant_tasks_v2
    set status='completed',updated_at=clock_timestamp()
    where id=v_task.id
    returning * into v_task;
    update public.workflow_executions_v2
    set status='completed',
        completed_at=coalesce(completed_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_execution.id
    returning * into v_execution;

    insert into public.notifications_v2(
      organization_id,recipient_user_id,event_type,title,body,status,
      channel_in_app,channel_email,source_kind,source_id,event_key
    ) values (
      v_obligation.organization_id,v_obligation.tenant_user_id,
      'rent_payment_registered','Pago registrado',
      'La gestoría ha registrado el pago de '||v_obligation.concept||'.',
      'pending',true,false,'payment_obligation',v_obligation.id,'paid'
    )
    on conflict (source_kind,source_id,event_key,recipient_user_id)
    where source_kind is not null and source_id is not null and event_key is not null
    do nothing;

  elsif p_action_key='claim' then
    if v_action.to_status<>'completed' then
      raise exception 'workflow_wf06_transition_mismatch' using errcode='55000';
    end if;

    select a.id into v_claim_app
    from public.workflow_applications_v2 a
    join public.workflow_definition_versions_v2 wv
      on wv.id=a.definition_version_id
     and wv.definition_id=a.definition_id
     and wv.organization_id=a.organization_id
    join public.workflow_definitions_v2 d
      on d.id=a.definition_id
     and d.organization_id=a.organization_id
    where a.organization_id=v_obligation.organization_id
      and a.status='configured'
      and d.status='published'
      and a.property_id=v_obligation.property_id
      and wv.spec->>'flowType'='rent_claim'
      and wv.spec->>'triggerType'='event'
      and wv.spec->>'eventType'='rent_claim.created'
      and wv.spec->>'closeType'='domain_adapter'
      and (
        a.scope_type='property'
        or (
          a.scope_type='room'
          and a.room_id is not distinct from v_obligation.room_id
        )
      )
    order by case when a.scope_type='room' then 0 else 1 end,a.id
    limit 1;

    if v_claim_app is null then
      raise exception 'workflow_wf06_claim_flow_unavailable' using errcode='55000';
    end if;
    if v_obligation.due_date>v_business_date then
      raise exception 'workflow_wf06_claim_not_due' using errcode='55000';
    end if;

    -- La reclamación no cierra el pago si hoy ni siquiera existe un ejecutor
    -- válido para el flujo de gestión. Cambios posteriores quedan reintentables
    -- por el outbox común.
    perform private.workflow_resolve_execution_assignee_v1(v_claim_app,null);

    update public.payment_obligations_v2
    set status='overdue',updated_at=clock_timestamp()
    where id=v_obligation.id
    returning * into v_obligation;

    insert into public.claims_v2(
      organization_id,property_id,tenant_user_id,obligation_id,occupancy_id,
      claim_type,title,body,status,created_by,created_at,updated_at
    ) values (
      v_obligation.organization_id,v_obligation.property_id,
      v_obligation.tenant_user_id,v_obligation.id,v_obligation.occupancy_id,
      'payment','Reclamación · '||v_obligation.concept,v_note,'draft',
      v_actor,clock_timestamp(),clock_timestamp()
    )
    returning * into v_claim;

    v_claim_event:=private.workflow_enqueue_event_v1(
      v_claim.organization_id,'rent_claim.created','rent_claim',v_claim.id,
      'created',v_claim.property_id,v_obligation.room_id,v_claim.occupancy_id,
      jsonb_build_object(
        'payment_obligation_id',v_obligation.id,
        'amount_cents',v_obligation.amount_cents,
        'currency',v_obligation.currency
      ),
      v_actor,clock_timestamp()
    );

    update public.tenant_tasks_v2
    set status='completed',updated_at=clock_timestamp()
    where id=v_task.id
    returning * into v_task;
    update public.workflow_executions_v2
    set status='completed',
        completed_at=coalesce(completed_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_execution.id
    returning * into v_execution;

  else
    raise exception 'workflow_action_not_allowed' using errcode='22023';
  end if;

  insert into public.tenant_task_history_v2(
    task_id,action_key,action_label,from_status,to_status,note,actor_user_id
  ) values (
    v_task.id,v_action.action_key,v_action.label,v_from_status,
    v_task.status,v_note,v_actor
  );

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,
    actor_user_id,details
  ) values (
    v_execution.id,v_execution.organization_id,'wf06_payment_action',
    v_from_status,v_execution.status,v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'action_key',p_action_key,
      'request_key',v_key,
      'payment_obligation_id',v_obligation.id,
      'old_due_date',v_old_due,
      'new_due_date',v_obligation.due_date,
      'rent_claim_id',v_claim.id,
      'rent_claim_event_id',v_claim_event
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,v_actor,'workflow_wf06_payment_action',
    'workflow_execution',v_execution.id::text,'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'payment_obligation_id',v_obligation.id,
      'action_key',p_action_key,
      'request_key',v_key,
      'from_status',v_from_status,
      'to_status',v_execution.status,
      'rent_claim_id',v_claim.id
    )
  );

  return query
  select v_task.id,v_task.status,v_execution.id,v_execution.status,true;
end;
$wf06_payment_action$;

revoke all on function private.apply_wf06_payment_action_v1(
  uuid,text,text,text,date
) from public,anon,authenticated,service_role;

comment on function private.wf06_business_date_v1(text,timestamptz) is
  'WF-06: fecha de negocio calculada en la zona horaria de la ejecución; evita comparar vencimientos locales contra current_date UTC.';
