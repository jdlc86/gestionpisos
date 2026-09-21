-- GestionPisos · WF-06 · acciones de Pago y Reclamación
-- Las mutaciones financieras sensibles pasan por RPC server-side e idempotente.

create unique index if not exists workflow_execution_events_v2_wf06_payment_request_uq
  on public.workflow_execution_events_v2(
    execution_id,((details->>'request_key'))
  )
  where event_type='wf06_payment_action' and details ? 'request_key';

create unique index if not exists workflow_execution_events_v2_wf06_claim_request_uq
  on public.workflow_execution_events_v2(
    execution_id,((details->>'request_key'))
  )
  where event_type='wf06_claim_action' and details ? 'request_key';

create or replace function private.wf06_execution_internal_actor_current_v1(
  p_execution_id uuid,
  p_actor uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $wf06_actor$
declare
  v_execution public.workflow_executions_v2;
  v_role text;
begin
  if p_actor is null or p_execution_id is null then
    return false;
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id;

  if v_execution.id is null
    or v_execution.assigned_user_id is distinct from p_actor
    or not private.wf06_internal_access_v1(
      v_execution.organization_id,v_execution.property_id,p_actor,true
    ) then
    return false;
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
      where a.organization_id=v_execution.organization_id
        and a.property_id=v_execution.property_id
        and a.employee_user_id=p_actor
        and a.assignment_type='responsible'
        and a.can_write=true
        and a.revoked_at is null
        and a.valid_from<=now()
        and (a.valid_until is null or a.valid_until>now())
    );
  end if;

  if v_execution.assignment_type='fixed_person' then
    return v_execution.spec_snapshot->>'assignmentUserId'=p_actor::text;
  end if;

  if v_execution.assignment_type='role' then
    v_role:=coalesce(v_execution.spec_snapshot->>'assignmentRole','');
    if v_role not in ('admin','employee') then
      return false;
    end if;
    return exists(
      select 1
      from public.user_roles ur
      where ur.user_id=p_actor
        and ur.organization_id=v_execution.organization_id
        and ur.role::text=v_role
        and ur.revoked_at is null
    );
  end if;

  return false;
end;
$wf06_actor$;

revoke all on function private.wf06_execution_internal_actor_current_v1(
  uuid,uuid
) from public,anon,authenticated,service_role;

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
      or p_effective_date<=greatest(v_obligation.due_date,current_date) then
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

create or replace function public.apply_wf06_payment_action_v1(
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
language sql
security definer
set search_path=''
as $wf06_payment_public$
  select *
  from private.apply_wf06_payment_action_v1(
    p_task_id,p_action_key,p_request_key,p_note,p_effective_date
  );
$wf06_payment_public$;

revoke all on function public.apply_wf06_payment_action_v1(
  uuid,text,text,text,date
) from public,anon;
grant execute on function public.apply_wf06_payment_action_v1(
  uuid,text,text,text,date
) to authenticated,service_role;

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
  v_last_request timestamptz;
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

    select max(ev.created_at)
    into v_last_request
    from public.workflow_execution_events_v2 ev
    where ev.execution_id=v_execution.id
      and ev.event_type='wf06_claim_action'
      and ev.details->>'action_key'='request_info';

    if v_last_request is null
      or not exists(
        select 1
        from public.workflow_execution_events_v2 ev
        where ev.execution_id=v_execution.id
          and ev.event_type='wf06_claim_action'
          and ev.details->>'action_key'='provide_info'
          and ev.created_at>v_last_request
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

-- Mantiene el RPC transversal. WF-06 se enruta antes de exigir actor=assignee,
-- porque Reclamación incluye acciones exactas del inquilino.
create or replace function public.apply_workflow_task_action_v1(
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
as $wf06_public_action$
declare
  v_execution_id uuid;
  v_organization_id uuid;
  v_spec jsonb;
begin
  select source_id,organization_id
  into v_execution_id,v_organization_id
  from public.tenant_tasks_v2
  where id=p_task_id and source_kind='workflow_execution';

  if v_execution_id is not null then
    select spec_snapshot into v_spec
    from public.workflow_executions_v2
    where id=v_execution_id;

    if v_spec->>'flowType'='rent_payment'
      and v_spec->>'closeType'='domain_adapter' then
      return query
      select * from private.apply_wf06_payment_action_v1(
        p_task_id,p_action_key,p_request_key,p_note,null
      );
      return;
    end if;

    if v_spec->>'flowType'='rent_claim'
      and v_spec->>'eventType'='rent_claim.created'
      and v_spec->>'closeType'='domain_adapter' then
      return query
      select * from private.apply_wf06_claim_action_v1(
        p_task_id,p_action_key,p_request_key,p_note
      );
      return;
    end if;

    if v_spec->>'flowType'='maintenance'
      and v_spec->>'eventType'='incident.created'
      and v_spec->>'closeType'='domain_adapter' then
      return query
      select * from private.apply_wf05_domain_action_v1(
        p_task_id,p_action_key,p_request_key,p_note
      );
      return;
    end if;

    if v_spec->>'flowType' in ('checkin','checkout')
      and v_spec->>'closeType'='domain_adapter' then
      return query
      select * from private.apply_wf04_domain_action_v1(
        p_task_id,p_action_key,p_request_key,p_note
      );
      return;
    end if;

    if not (
      p_action_key in ('review_approve','review_reject')
      and public.workflow_can_manage_v1(v_organization_id)
    ) then
      perform private.workflow_require_current_actor_v1(v_execution_id);
    end if;
  end if;

  return query
  select * from private.apply_workflow_task_action_v1(
    p_task_id,p_action_key,p_request_key,p_note
  );
end;
$wf06_public_action$;

revoke all on function public.apply_workflow_task_action_v1(
  uuid,text,text,text
) from public,anon;
grant execute on function public.apply_workflow_task_action_v1(
  uuid,text,text,text
) to authenticated,service_role;

comment on function public.apply_wf06_payment_action_v1(
  uuid,text,text,text,date
) is
  'WF-06: solicitar, aplazar con fecha tipada, registrar pago o escalar a reclamación sobre la obligación exacta.';
comment on function private.apply_wf06_claim_action_v1(
  uuid,text,text,text
) is
  'WF-06: acciones mixtas gestoría/inquilino sobre la misma reclamación, tarea y ejecución, con idempotencia y auditoría.';
