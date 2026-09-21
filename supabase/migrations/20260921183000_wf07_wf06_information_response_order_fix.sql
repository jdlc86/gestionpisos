-- GestionPisos · WF-07 · deuda WF-06 descubierta por regresión integrada
--
-- apply_wf06_claim_action_v1() usaba created_at para decidir si provide_info
-- ocurrió después del último request_info. workflow_execution_events_v2 usa
-- created_at default now(), que es estable durante toda una transacción; por
-- tanto dos acciones válidas dentro de la misma transacción podían quedar con
-- el mismo timestamp y bloquear continue.
--
-- El id de workflow_execution_events_v2 es IDENTITY monotónico y expresa el
-- orden de inserción de forma determinista. La misma función RETURNS TABLE
-- expone task_id como variable PL/pgSQL; se califican también las dos
-- referencias de tenant_task_actions_v2 que el PostgreSQL estricto detecta
-- como ambiguas. No cambia la semántica de autorización ni estados WF-06.

create or replace function private.apply_wf06_claim_action_v1(
  p_task_id uuid,
  p_action_key text,
  p_request_key text,
  p_note text default null
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
as $wf06_claim_action$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_note text:=nullif(btrim(p_note),'');
  v_task public.tenant_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_claim public.claims_v2;
  v_obligation public.payment_obligations_v2;
  v_event public.workflow_event_outbox_v2;
  v_action public.tenant_task_actions_v2;
  v_previous public.workflow_execution_events_v2;
  v_tenant public.tenants_v2;
  v_from_status text;
  v_last_request_id bigint;
  v_recipient uuid;
  v_event_type text;
  v_title text;
  v_body text;
  v_event_key text;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_action_request_key_invalid' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      v_actor::text||':wf06-claim:'||p_task_id::text||':'||v_key,0
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
    or v_execution.spec_snapshot->>'flowType'<>'rent_claim'
    or v_execution.spec_snapshot->>'eventType'<>'rent_claim.created'
    or v_execution.spec_snapshot->>'closeType'<>'domain_adapter'
    or v_execution.source_event_id is null
    or v_execution.rent_claim_id is null
    or v_execution.payment_obligation_id is null then
    raise exception 'workflow_wf06_claim_domain_required' using errcode='22023';
  end if;

  select * into v_claim
  from public.claims_v2
  where id=v_execution.rent_claim_id
  for update;
  select * into v_obligation
  from public.payment_obligations_v2
  where id=v_execution.payment_obligation_id
  for update;
  select * into v_event
  from public.workflow_event_outbox_v2
  where id=v_execution.source_event_id;

  if v_claim.id is null
    or v_claim.claim_type<>'payment'
    or v_obligation.id is null
    or v_claim.obligation_id is distinct from v_obligation.id
    or v_claim.organization_id is distinct from v_execution.organization_id
    or v_claim.property_id is distinct from v_execution.property_id
    or v_claim.occupancy_id is distinct from v_obligation.occupancy_id
    or v_claim.tenant_user_id is distinct from v_obligation.tenant_user_id
    or v_event.id is null
    or v_event.event_type<>'rent_claim.created'
    or v_event.source_kind<>'rent_claim'
    or v_event.source_id is distinct from v_claim.id
    or v_event.organization_id is distinct from v_claim.organization_id
    or v_event.property_id is distinct from v_claim.property_id
    or v_event.occupancy_id is distinct from v_claim.occupancy_id then
    raise exception 'workflow_wf06_claim_subject_not_current' using errcode='55000';
  end if;

  select * into v_tenant
  from public.tenants_v2
  where organization_id=v_claim.organization_id
    and user_id=v_claim.tenant_user_id
    and status='active'
    and archived_at is null;
  if v_tenant.id is null
    or v_task.tenant_id is distinct from v_tenant.id
    or v_task.organization_id is distinct from v_execution.organization_id
    or v_task.property_id is distinct from v_execution.property_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
    raise exception 'workflow_wf06_claim_task_identity_mismatch' using errcode='55000';
  end if;

  select * into v_previous
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='wf06_claim_action'
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
    and a.active=true;
  if v_action.id is null then
    raise exception 'workflow_action_not_allowed' using errcode='22023';
  end if;
  if v_action.requires_note and v_note is null then
    raise exception 'workflow_action_note_required' using errcode='22023';
  end if;

  if v_action.actor='assignee' then
    if not private.wf06_execution_internal_actor_current_v1(
      v_execution.id,v_actor
    ) then
      raise exception 'workflow_wf06_assignee_not_eligible' using errcode='42501';
    end if;
    perform private.wf06_require_privileged_aal2_v1(
      v_execution.organization_id,v_actor
    );
  elsif v_action.actor='tenant' then
    if v_actor is distinct from v_claim.tenant_user_id
      or not exists(
        select 1
        from public.user_roles ur
        where ur.user_id=v_actor
          and ur.organization_id=v_claim.organization_id
          and ur.role='tenant'
          and ur.revoked_at is null
      )
      or not public.has_current_platform_access_v1() then
      raise exception 'workflow_wf06_tenant_not_eligible' using errcode='42501';
    end if;
  else
    raise exception 'workflow_action_actor_forbidden' using errcode='42501';
  end if;

  v_from_status:=v_task.status;

  if p_action_key='notify' then
    if v_claim.status<>'draft'
      or v_action.to_status<>'active' then
      raise exception 'workflow_wf06_transition_mismatch' using errcode='55000';
    end if;
    update public.claims_v2
    set status='sent',sent_at=coalesce(sent_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_claim.id
    returning * into v_claim;

    update public.tenant_tasks_v2
    set status='active',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='active',
        started_at=coalesce(started_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

    v_recipient:=v_claim.tenant_user_id;
    v_event_type:='rent_claim_notified';
    v_title:='Reclamación de alquiler';
    v_body:=v_claim.body;
    v_event_key:='notified';

  elsif p_action_key in ('accept','dispute') then
    if v_claim.status<>'sent'
      or v_claim.tenant_decision is not null
      or v_action.to_status<>'active' then
      raise exception 'workflow_wf06_transition_mismatch' using errcode='55000';
    end if;
    update public.claims_v2
    set tenant_decision=case p_action_key
          when 'accept' then 'accepted' else 'disputed' end,
        updated_at=clock_timestamp()
    where id=v_claim.id
    returning * into v_claim;

    update public.tenant_task_actions_v2 as a
    set active=false
    where a.task_id=v_task.id
      and a.from_status='active'
      and a.action_key in ('accept','dispute');

    update public.tenant_task_actions_v2 as a
    set active=true
    where a.task_id=v_task.id
      and a.from_status='active'
      and a.action_key='resolve';

    v_recipient:=v_execution.assigned_user_id;
    v_event_type:=case p_action_key
      when 'accept' then 'rent_claim_accepted'
      else 'rent_claim_disputed' end;
    v_title:=case p_action_key
      when 'accept' then 'Reclamación aceptada'
      else 'Reclamación disputada' end;
    v_body:=case p_action_key
      when 'accept' then 'El inquilino ha aceptado la reclamación.'
      else v_note end;
    v_event_key:=p_action_key||':'||v_key;

  elsif p_action_key='request_info' then
    if v_claim.status<>'sent'
      or v_action.to_status<>'waiting_info' then
      raise exception 'workflow_wf06_transition_mismatch' using errcode='55000';
    end if;
    update public.claims_v2
    set status='waiting_info',updated_at=clock_timestamp()
    where id=v_claim.id
    returning * into v_claim;
    update public.tenant_tasks_v2
    set status='waiting_info',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='waiting_info',updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

    v_recipient:=v_claim.tenant_user_id;
    v_event_type:='rent_claim_information_requested';
    v_title:='Información necesaria';
    v_body:=v_note;
    v_event_key:='information_requested:'||v_key;

  elsif p_action_key='provide_info' then
    if v_claim.status<>'waiting_info'
      or v_action.to_status<>'waiting_info' then
      raise exception 'workflow_wf06_transition_mismatch' using errcode='55000';
    end if;

    v_recipient:=v_execution.assigned_user_id;
    v_event_type:='rent_claim_information_received';
    v_title:='Información recibida';
    v_body:=v_note;
    v_event_key:='information_received:'||v_key;

  elsif p_action_key='continue' then
    if v_claim.status<>'waiting_info'
      or v_action.to_status<>'active' then
      raise exception 'workflow_wf06_transition_mismatch' using errcode='55000';
    end if;

    select max(ev.id)
    into v_last_request_id
    from public.workflow_execution_events_v2 ev
    where ev.execution_id=v_execution.id
      and ev.event_type='wf06_claim_action'
      and ev.details->>'action_key'='request_info';

    if v_last_request_id is null
      or not exists(
        select 1
        from public.workflow_execution_events_v2 ev
        where ev.execution_id=v_execution.id
          and ev.event_type='wf06_claim_action'
          and ev.details->>'action_key'='provide_info'
          and ev.id>v_last_request_id
      ) then
      raise exception 'workflow_wf06_information_response_required' using errcode='55000';
    end if;

    update public.claims_v2
    set status='sent',updated_at=clock_timestamp()
    where id=v_claim.id
    returning * into v_claim;
    update public.tenant_tasks_v2
    set status='active',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='active',updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

  elsif p_action_key='resolve' then
    if v_claim.status<>'sent'
      or coalesce(v_claim.tenant_decision,'') not in ('accepted','disputed')
      or v_action.to_status<>'completed' then
      raise exception 'workflow_wf06_transition_mismatch' using errcode='55000';
    end if;

    update public.claims_v2
    set status='resolved',resolved_at=clock_timestamp(),
        updated_at=clock_timestamp()
    where id=v_claim.id
    returning * into v_claim;
    update public.tenant_tasks_v2
    set status='completed',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='completed',
        completed_at=coalesce(completed_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

    v_recipient:=v_claim.tenant_user_id;
    v_event_type:='rent_claim_resolved';
    v_title:='Reclamación resuelta';
    v_body:=v_note;
    v_event_key:='resolved';

  else
    raise exception 'workflow_action_not_allowed' using errcode='22023';
  end if;

  if v_recipient is not null then
    insert into public.notifications_v2(
      organization_id,recipient_user_id,event_type,title,body,status,
      channel_in_app,channel_email,source_kind,source_id,event_key
    ) values (
      v_claim.organization_id,v_recipient,v_event_type,v_title,v_body,
      'pending',true,false,'rent_claim',v_claim.id,v_event_key
    )
    on conflict (source_kind,source_id,event_key,recipient_user_id)
    where source_kind is not null and source_id is not null and event_key is not null
    do nothing;
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
    v_execution.id,v_execution.organization_id,'wf06_claim_action',
    v_from_status,v_execution.status,v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'action_key',p_action_key,
      'request_key',v_key,
      'rent_claim_id',v_claim.id,
      'payment_obligation_id',v_obligation.id,
      'tenant_decision',v_claim.tenant_decision
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,v_actor,'workflow_wf06_claim_action',
    'workflow_execution',v_execution.id::text,'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'rent_claim_id',v_claim.id,
      'payment_obligation_id',v_obligation.id,
      'action_key',p_action_key,
      'request_key',v_key,
      'from_status',v_from_status,
      'to_status',v_execution.status,
      'actor_kind',v_action.actor
    )
  );

  return query
  select v_task.id,v_task.status,v_execution.id,v_execution.status,true;
end;
$wf06_claim_action$;

revoke all on function private.apply_wf06_claim_action_v1(
  uuid,text,text,text
) from public,anon,authenticated,service_role;
