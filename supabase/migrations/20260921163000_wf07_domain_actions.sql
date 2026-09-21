-- GestionPisos · WF-07 · acciones de Fianza + Daños

create unique index if not exists workflow_execution_events_v2_wf07_deposit_request_uq
  on public.workflow_execution_events_v2(
    execution_id,((details->>'request_key'))
  )
  where event_type='wf07_deposit_action' and details ? 'request_key';

create unique index if not exists workflow_execution_events_v2_wf07_damage_request_uq
  on public.workflow_execution_events_v2(
    execution_id,((details->>'request_key'))
  )
  where event_type='wf07_damage_action' and details ? 'request_key';

create or replace function private.wf07_execution_internal_actor_current_v1(
  p_execution_id uuid,
  p_actor uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $wf07_actor$
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
    or v_execution.spec_snapshot->>'flowType'
       not in ('deposit_receipt','deposit_review','damage_claim')
    or v_execution.spec_snapshot->>'closeType'<>'domain_adapter'
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
    return v_execution.spec_snapshot->>'assignmentUserId'=p_actor::text
      and exists(
        select 1
        from public.user_roles ur
        where ur.user_id=p_actor
          and ur.organization_id=v_execution.organization_id
          and ur.role in ('admin','employee')
          and ur.revoked_at is null
      );
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
$wf07_actor$;

revoke all on function private.wf07_execution_internal_actor_current_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

-- RLS de Tareas usa el mismo gate. WF-07 no concede acceso al tenant dado de baja.
alter function public.workflow_execution_actor_current_v1(uuid)
  rename to workflow_execution_actor_current_pre_wf07_v1;
revoke all on function public.workflow_execution_actor_current_pre_wf07_v1(uuid)
  from public,anon,service_role;
grant execute on function public.workflow_execution_actor_current_pre_wf07_v1(uuid)
  to authenticated;

create function public.workflow_execution_actor_current_v1(
  p_execution_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $wf07_actor_gate$
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

  if v_execution.id is not null
    and v_execution.spec_snapshot->>'flowType'
        in ('deposit_receipt','deposit_review','damage_claim')
    and v_execution.spec_snapshot->>'closeType'='domain_adapter' then
    return private.wf07_execution_internal_actor_current_v1(
      v_execution.id,v_actor
    );
  end if;

  return public.workflow_execution_actor_current_pre_wf07_v1(p_execution_id);
end;
$wf07_actor_gate$;

revoke all on function public.workflow_execution_actor_current_v1(uuid)
  from public,anon,service_role;
grant execute on function public.workflow_execution_actor_current_v1(uuid)
  to authenticated;

create or replace function private.wf07_execution_evidence_complete_v1(
  p_execution_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $wf07_evidence$
declare
  v_execution public.workflow_executions_v2;
  v_photo_required boolean;
  v_checklist_required boolean;
  v_document_required boolean;
  v_photo_complete boolean:=true;
  v_checklist_complete boolean:=true;
  v_document_complete boolean:=true;
begin
  select * into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id;

  if v_execution.id is null then
    return false;
  end if;

  v_photo_required:=coalesce(
    (v_execution.spec_snapshot#>>'{steps,photo}')::boolean,false
  );
  v_checklist_required:=coalesce(
    (v_execution.spec_snapshot#>>'{steps,checklist}')::boolean,false
  );
  v_document_required:=coalesce(
    (v_execution.spec_snapshot#>>'{steps,document}')::boolean,false
  );

  if not (v_photo_required or v_checklist_required or v_document_required) then
    return false;
  end if;

  if v_photo_required then
    select exists(
      select 1 from public.workflow_execution_photo_resources_v2 r
      where r.execution_id=v_execution.id
    ) and not exists(
      select 1 from public.workflow_execution_photo_resources_v2 r
      where r.execution_id=v_execution.id and r.status<>'submitted'
    ) into v_photo_complete;
  end if;

  if v_checklist_required then
    select
      jsonb_typeof(v_execution.checklist_state)='array'
      and jsonb_array_length(v_execution.checklist_state)>0
      and not exists(
        select 1
        from jsonb_array_elements(v_execution.checklist_state) item
        where coalesce((item->>'required')::boolean,true)
          and not coalesce((item->>'completed')::boolean,false)
      )
    into v_checklist_complete;
  end if;

  if v_document_required then
    select exists(
      select 1
      from public.workflow_execution_documents_v2 d
      where d.execution_id=v_execution.id
        and d.status='submitted'
    ) into v_document_complete;
  end if;

  return v_photo_complete and v_checklist_complete and v_document_complete;
end;
$wf07_evidence$;

revoke all on function private.wf07_execution_evidence_complete_v1(uuid)
  from public,anon,authenticated,service_role;

create or replace function private.apply_wf07_deposit_action_v1(
  p_task_id uuid,
  p_action_key text,
  p_request_key text,
  p_note text default null,
  p_amount_cents bigint default null
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
as $wf07_deposit_action$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_note text:=nullif(btrim(p_note),'');
  v_task public.tenant_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_deposit public.security_deposits_v2;
  v_action public.tenant_task_actions_v2;
  v_previous public.workflow_execution_events_v2;
  v_from_status text;
  v_claim public.claims_v2;
  v_claim_event uuid;
  v_damage_app uuid;
  v_unresolved bigint;
  v_settled_total bigint;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_action_request_key_invalid' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      v_actor::text||':wf07-deposit:'||p_task_id::text||':'||v_key,0
    )
  );

  select * into v_task
  from public.tenant_tasks_v2
  where id=p_task_id
  for update;

  if v_task.id is null
    or v_task.task_type<>'workflow'
    or v_task.source_kind<>'workflow_execution'
    or v_task.source_id is null then
    raise exception 'workflow_task_required' using errcode='22023';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_task.source_id
  for update;

  if v_execution.id is null
    or v_execution.spec_snapshot->>'flowType'
       not in ('deposit_receipt','deposit_review')
    or v_execution.spec_snapshot->>'closeType'<>'domain_adapter'
    or v_execution.security_deposit_id is null then
    raise exception 'workflow_wf07_deposit_domain_required' using errcode='22023';
  end if;

  if not private.wf07_execution_internal_actor_current_v1(
    v_execution.id,v_actor
  ) then
    raise exception 'workflow_wf07_assignee_not_eligible' using errcode='42501';
  end if;
  perform private.wf06_require_privileged_aal2_v1(
    v_execution.organization_id,v_actor
  );

  select * into v_deposit
  from public.security_deposits_v2
  where id=v_execution.security_deposit_id
  for update;

  if v_deposit.id is null
    or v_deposit.organization_id is distinct from v_execution.organization_id
    or v_deposit.property_id is distinct from v_execution.property_id
    or v_deposit.tenant_user_id is distinct from (
      select o.user_id
      from public.occupancies_v2 o
      where o.id=v_deposit.occupancy_id
    )
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
    raise exception 'workflow_wf07_deposit_subject_not_current'
      using errcode='55000';
  end if;

  select * into v_previous
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='wf07_deposit_action'
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

  v_from_status:=v_task.status;

  if v_execution.spec_snapshot->>'flowType'='deposit_receipt' then
    if p_action_key<>'register_receipt'
      or v_deposit.status<>'pending'
      or v_action.to_status<>'completed' then
      raise exception 'workflow_wf07_transition_mismatch' using errcode='55000';
    end if;

    update public.security_deposits_v2
    set status='received',
        received_at=coalesce(received_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_deposit.id
    returning * into v_deposit;

    update public.tenant_tasks_v2
    set status='completed',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='completed',
        completed_at=coalesce(completed_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

  elsif p_action_key='start_review' then
    if v_deposit.status<>'received'
      or v_action.to_status<>'active' then
      raise exception 'workflow_wf07_transition_mismatch' using errcode='55000';
    end if;

    update public.security_deposits_v2
    set status='under_review',
        review_started_at=coalesce(review_started_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_deposit.id returning * into v_deposit;
    update public.tenant_tasks_v2
    set status='active',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='active',
        started_at=coalesce(started_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

  elsif p_action_key='request_info' then
    if v_deposit.status<>'under_review'
      or v_action.to_status<>'waiting_info' then
      raise exception 'workflow_wf07_transition_mismatch' using errcode='55000';
    end if;

    update public.security_deposits_v2
    set status='waiting_info',updated_at=clock_timestamp()
    where id=v_deposit.id returning * into v_deposit;
    update public.tenant_tasks_v2
    set status='waiting_info',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='waiting_info',updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

  elsif p_action_key='continue' then
    if v_deposit.status<>'waiting_info'
      or v_action.to_status<>'active'
      or v_note is null then
      raise exception 'workflow_wf07_transition_mismatch' using errcode='55000';
    end if;

    update public.security_deposits_v2
    set status='under_review',updated_at=clock_timestamp()
    where id=v_deposit.id returning * into v_deposit;
    update public.tenant_tasks_v2
    set status='active',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='active',updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

  elsif p_action_key='open_damage_claim' then
    if v_deposit.status<>'under_review'
      or p_amount_cents is null
      or p_amount_cents<1
      or p_amount_cents>1000000000 then
      raise exception 'workflow_wf07_damage_amount_invalid' using errcode='22023';
    end if;

    select a.id into v_damage_app
    from public.workflow_applications_v2 a
    join public.workflow_definition_versions_v2 wv
      on wv.id=a.definition_version_id
     and wv.definition_id=a.definition_id
     and wv.organization_id=a.organization_id
    join public.workflow_definitions_v2 d
      on d.id=a.definition_id
     and d.organization_id=a.organization_id
    where a.organization_id=v_deposit.organization_id
      and a.status='configured'
      and d.status='published'
      and a.property_id=v_deposit.property_id
      and wv.spec->>'flowType'='damage_claim'
      and wv.spec->>'triggerType'='event'
      and wv.spec->>'eventType'='damage_claim.created'
      and wv.spec->>'closeType'='domain_adapter'
      and (
        a.scope_type='property'
        or (
          a.scope_type='room'
          and a.room_id is not distinct from v_deposit.room_id
        )
      )
    order by case when a.scope_type='room' then 0 else 1 end,a.id
    limit 1;

    if v_damage_app is null then
      raise exception 'workflow_wf07_damage_flow_unavailable' using errcode='55000';
    end if;
    perform private.workflow_resolve_execution_assignee_v1(v_damage_app,null);

    insert into public.claims_v2(
      organization_id,property_id,tenant_user_id,occupancy_id,
      security_deposit_id,claim_type,title,body,status,
      claimed_amount_cents,currency,created_by,created_at,updated_at
    ) values (
      v_deposit.organization_id,v_deposit.property_id,
      v_deposit.tenant_user_id,v_deposit.occupancy_id,
      v_deposit.id,'damage','Reclamación por daños',v_note,'draft',
      p_amount_cents,v_deposit.currency,v_actor,clock_timestamp(),clock_timestamp()
    )
    returning * into v_claim;

    v_claim_event:=private.workflow_enqueue_event_v1(
      v_claim.organization_id,'damage_claim.created','damage_claim',v_claim.id,
      'created',v_claim.property_id,v_deposit.room_id,v_claim.occupancy_id,
      jsonb_build_object(
        'security_deposit_id',v_deposit.id,
        'claimed_amount_cents',v_claim.claimed_amount_cents,
        'currency',v_claim.currency
      ),
      v_actor,clock_timestamp()
    );

  elsif p_action_key in ('refund','partial_hold','hold') then
    if v_deposit.status<>'under_review'
      or v_action.to_status<>'completed' then
      raise exception 'workflow_wf07_transition_mismatch' using errcode='55000';
    end if;

    if not private.wf07_execution_evidence_complete_v1(v_execution.id) then
      raise exception 'workflow_wf07_deposit_evidence_required'
        using errcode='55000';
    end if;

    select count(*) filter(where c.status<>'resolved'),
           coalesce(sum(c.settled_amount_cents) filter(where c.status='resolved'),0)
    into v_unresolved,v_settled_total
    from public.claims_v2 c
    where c.claim_type='damage'
      and c.security_deposit_id=v_deposit.id;

    if v_unresolved>0 then
      raise exception 'workflow_wf07_damage_claims_unresolved' using errcode='55000';
    end if;

    if p_action_key='refund' then
      if v_settled_total<>0 then
        raise exception 'workflow_wf07_refund_has_damage_settlement'
          using errcode='55000';
      end if;

      update public.security_deposits_v2
      set status='refunded',
          held_amount_cents=0,
          refunded_amount_cents=amount_cents,
          resolved_at=clock_timestamp(),
          updated_at=clock_timestamp()
      where id=v_deposit.id returning * into v_deposit;

    elsif p_action_key='partial_hold' then
      if p_amount_cents is null
        or p_amount_cents<=0
        or p_amount_cents>=v_deposit.amount_cents
        or p_amount_cents>v_settled_total then
        raise exception 'workflow_wf07_partial_hold_amount_invalid'
          using errcode='22023';
      end if;

      update public.security_deposits_v2
      set status='partially_held',
          held_amount_cents=p_amount_cents,
          refunded_amount_cents=amount_cents-p_amount_cents,
          resolved_at=clock_timestamp(),
          updated_at=clock_timestamp()
      where id=v_deposit.id returning * into v_deposit;

    else
      if v_settled_total<v_deposit.amount_cents then
        raise exception 'workflow_wf07_full_hold_not_justified'
          using errcode='55000';
      end if;

      update public.security_deposits_v2
      set status='held',
          held_amount_cents=amount_cents,
          refunded_amount_cents=0,
          resolved_at=clock_timestamp(),
          updated_at=clock_timestamp()
      where id=v_deposit.id returning * into v_deposit;
    end if;

    update public.tenant_tasks_v2
    set status='completed',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='completed',
        completed_at=coalesce(completed_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

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
    v_execution.id,v_execution.organization_id,'wf07_deposit_action',
    v_from_status,v_execution.status,v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'action_key',p_action_key,
      'request_key',v_key,
      'security_deposit_id',v_deposit.id,
      'amount_cents',p_amount_cents,
      'damage_claim_id',v_claim.id,
      'damage_claim_event_id',v_claim_event,
      'deposit_status',v_deposit.status,
      'held_amount_cents',v_deposit.held_amount_cents,
      'refunded_amount_cents',v_deposit.refunded_amount_cents
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,v_actor,'workflow_wf07_deposit_action',
    'workflow_execution',v_execution.id::text,'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'security_deposit_id',v_deposit.id,
      'action_key',p_action_key,
      'request_key',v_key,
      'deposit_status',v_deposit.status,
      'held_amount_cents',v_deposit.held_amount_cents,
      'refunded_amount_cents',v_deposit.refunded_amount_cents
    )
  );

  return query
  select v_task.id,v_task.status,v_execution.id,v_execution.status,true;
end;
$wf07_deposit_action$;

revoke all on function private.apply_wf07_deposit_action_v1(
  uuid,text,text,text,bigint
) from public,anon,authenticated,service_role;

create or replace function public.apply_wf07_deposit_action_v1(
  p_task_id uuid,
  p_action_key text,
  p_request_key text,
  p_note text default null,
  p_amount_cents bigint default null
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
as $wf07_deposit_public$
  select *
  from private.apply_wf07_deposit_action_v1(
    p_task_id,p_action_key,p_request_key,p_note,p_amount_cents
  );
$wf07_deposit_public$;

revoke all on function public.apply_wf07_deposit_action_v1(
  uuid,text,text,text,bigint
) from public,anon;
grant execute on function public.apply_wf07_deposit_action_v1(
  uuid,text,text,text,bigint
) to authenticated,service_role;

create or replace function private.apply_wf07_damage_action_v1(
  p_task_id uuid,
  p_action_key text,
  p_request_key text,
  p_note text default null,
  p_settled_amount_cents bigint default null
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
as $wf07_damage_action$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_note text:=nullif(btrim(p_note),'');
  v_task public.tenant_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_claim public.claims_v2;
  v_deposit public.security_deposits_v2;
  v_action public.tenant_task_actions_v2;
  v_previous public.workflow_execution_events_v2;
  v_from_status text;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_action_request_key_invalid' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      v_actor::text||':wf07-damage:'||p_task_id::text||':'||v_key,0
    )
  );

  select * into v_task
  from public.tenant_tasks_v2
  where id=p_task_id
  for update;

  if v_task.id is null
    or v_task.task_type<>'workflow'
    or v_task.source_kind<>'workflow_execution'
    or v_task.source_id is null then
    raise exception 'workflow_task_required' using errcode='22023';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_task.source_id
  for update;

  if v_execution.id is null
    or v_execution.spec_snapshot->>'flowType'<>'damage_claim'
    or v_execution.spec_snapshot->>'eventType'<>'damage_claim.created'
    or v_execution.spec_snapshot->>'closeType'<>'domain_adapter'
    or v_execution.damage_claim_id is null
    or v_execution.security_deposit_id is null then
    raise exception 'workflow_wf07_damage_domain_required' using errcode='22023';
  end if;

  if not private.wf07_execution_internal_actor_current_v1(
    v_execution.id,v_actor
  ) then
    raise exception 'workflow_wf07_assignee_not_eligible' using errcode='42501';
  end if;
  perform private.wf06_require_privileged_aal2_v1(
    v_execution.organization_id,v_actor
  );

  select * into v_claim
  from public.claims_v2
  where id=v_execution.damage_claim_id
  for update;
  select * into v_deposit
  from public.security_deposits_v2
  where id=v_execution.security_deposit_id
  for update;

  if v_claim.id is null
    or v_claim.claim_type<>'damage'
    or v_claim.security_deposit_id is distinct from v_deposit.id
    or v_claim.organization_id is distinct from v_execution.organization_id
    or v_claim.property_id is distinct from v_execution.property_id
    or v_claim.occupancy_id is distinct from v_deposit.occupancy_id
    or v_claim.tenant_user_id is distinct from v_deposit.tenant_user_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
    raise exception 'workflow_wf07_damage_subject_not_current' using errcode='55000';
  end if;

  select * into v_previous
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='wf07_damage_action'
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

  v_from_status:=v_task.status;

  if p_action_key='notify' then
    if v_claim.status<>'draft'
      or not private.wf07_execution_evidence_complete_v1(v_execution.id)
      or v_action.to_status<>'active' then
      raise exception 'workflow_wf07_damage_evidence_required' using errcode='55000';
    end if;

    update public.claims_v2
    set status='sent',sent_at=coalesce(sent_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_claim.id returning * into v_claim;
    update public.tenant_tasks_v2
    set status='active',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='active',
        started_at=coalesce(started_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

  elsif p_action_key in ('record_acceptance','record_dispute') then
    if v_claim.status<>'sent'
      or v_claim.tenant_decision is not null
      or v_action.to_status<>'active' then
      raise exception 'workflow_wf07_transition_mismatch' using errcode='55000';
    end if;

    update public.claims_v2
    set tenant_decision=case p_action_key
          when 'record_acceptance' then 'accepted' else 'disputed' end,
        updated_at=clock_timestamp()
    where id=v_claim.id returning * into v_claim;

    update public.tenant_task_actions_v2
    set active=false
    where task_id=v_task.id
      and from_status='active'
      and action_key in ('record_acceptance','record_dispute');
    update public.tenant_task_actions_v2
    set active=true
    where task_id=v_task.id
      and from_status='active'
      and action_key='resolve';

  elsif p_action_key='request_info' then
    if v_claim.status<>'sent'
      or v_action.to_status<>'waiting_info' then
      raise exception 'workflow_wf07_transition_mismatch' using errcode='55000';
    end if;

    update public.claims_v2
    set status='waiting_info',updated_at=clock_timestamp()
    where id=v_claim.id returning * into v_claim;
    update public.tenant_tasks_v2
    set status='waiting_info',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='waiting_info',updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

  elsif p_action_key='continue' then
    if v_claim.status<>'waiting_info'
      or v_note is null
      or v_action.to_status<>'active' then
      raise exception 'workflow_wf07_transition_mismatch' using errcode='55000';
    end if;

    update public.claims_v2
    set status='sent',updated_at=clock_timestamp()
    where id=v_claim.id returning * into v_claim;
    update public.tenant_tasks_v2
    set status='active',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='active',updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

  elsif p_action_key='resolve' then
    if v_claim.status<>'sent'
      or coalesce(v_claim.tenant_decision,'') not in ('accepted','disputed')
      or p_settled_amount_cents is null
      or p_settled_amount_cents<0
      or p_settled_amount_cents>v_claim.claimed_amount_cents
      or not private.wf07_execution_evidence_complete_v1(v_execution.id)
      or v_action.to_status<>'completed' then
      raise exception 'workflow_wf07_damage_resolution_invalid' using errcode='55000';
    end if;

    update public.claims_v2
    set status='resolved',
        settled_amount_cents=p_settled_amount_cents,
        resolved_at=clock_timestamp(),
        updated_at=clock_timestamp()
    where id=v_claim.id returning * into v_claim;
    update public.tenant_tasks_v2
    set status='completed',updated_at=clock_timestamp()
    where id=v_task.id returning * into v_task;
    update public.workflow_executions_v2
    set status='completed',
        completed_at=coalesce(completed_at,clock_timestamp()),
        updated_at=clock_timestamp()
    where id=v_execution.id returning * into v_execution;

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
    v_execution.id,v_execution.organization_id,'wf07_damage_action',
    v_from_status,v_execution.status,v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'action_key',p_action_key,
      'request_key',v_key,
      'damage_claim_id',v_claim.id,
      'security_deposit_id',v_deposit.id,
      'tenant_decision',v_claim.tenant_decision,
      'settled_amount_cents',v_claim.settled_amount_cents
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,v_actor,'workflow_wf07_damage_action',
    'workflow_execution',v_execution.id::text,'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'damage_claim_id',v_claim.id,
      'security_deposit_id',v_deposit.id,
      'action_key',p_action_key,
      'request_key',v_key,
      'tenant_decision',v_claim.tenant_decision,
      'settled_amount_cents',v_claim.settled_amount_cents
    )
  );

  return query
  select v_task.id,v_task.status,v_execution.id,v_execution.status,true;
end;
$wf07_damage_action$;

revoke all on function private.apply_wf07_damage_action_v1(
  uuid,text,text,text,bigint
) from public,anon,authenticated,service_role;

create or replace function public.apply_wf07_damage_action_v1(
  p_task_id uuid,
  p_action_key text,
  p_request_key text,
  p_note text default null,
  p_settled_amount_cents bigint default null
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
as $wf07_damage_public$
  select *
  from private.apply_wf07_damage_action_v1(
    p_task_id,p_action_key,p_request_key,p_note,p_settled_amount_cents
  );
$wf07_damage_public$;

revoke all on function public.apply_wf07_damage_action_v1(
  uuid,text,text,text,bigint
) from public,anon;
grant execute on function public.apply_wf07_damage_action_v1(
  uuid,text,text,text,bigint
) to authenticated,service_role;

-- Enruta WF-07 antes de la lógica transversal anterior.
alter function public.apply_workflow_task_action_v1(uuid,text,text,text)
  rename to apply_workflow_task_action_pre_wf07_v1;
revoke all on function public.apply_workflow_task_action_pre_wf07_v1(
  uuid,text,text,text
) from public,anon;
grant execute on function public.apply_workflow_task_action_pre_wf07_v1(
  uuid,text,text,text
) to authenticated,service_role;

create function public.apply_workflow_task_action_v1(
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
as $wf07_action_router$
declare
  v_execution_id uuid;
  v_spec jsonb;
begin
  select source_id into v_execution_id
  from public.tenant_tasks_v2
  where id=p_task_id and source_kind='workflow_execution';

  if v_execution_id is not null then
    select spec_snapshot into v_spec
    from public.workflow_executions_v2
    where id=v_execution_id;

    if v_spec->>'flowType' in ('deposit_receipt','deposit_review')
      and v_spec->>'closeType'='domain_adapter' then
      return query
      select * from private.apply_wf07_deposit_action_v1(
        p_task_id,p_action_key,p_request_key,p_note,null
      );
      return;
    end if;

    if v_spec->>'flowType'='damage_claim'
      and v_spec->>'eventType'='damage_claim.created'
      and v_spec->>'closeType'='domain_adapter' then
      return query
      select * from private.apply_wf07_damage_action_v1(
        p_task_id,p_action_key,p_request_key,p_note,null
      );
      return;
    end if;
  end if;

  return query
  select * from public.apply_workflow_task_action_pre_wf07_v1(
    p_task_id,p_action_key,p_request_key,p_note
  );
end;
$wf07_action_router$;

revoke all on function public.apply_workflow_task_action_v1(
  uuid,text,text,text
) from public,anon;
grant execute on function public.apply_workflow_task_action_v1(
  uuid,text,text,text
) to authenticated,service_role;

comment on function public.apply_wf07_deposit_action_v1(
  uuid,text,text,text,bigint
) is
  'WF-07: recepción/revisión de fianza, apertura de daños y devolución/retención con importe tipado.';
comment on function public.apply_wf07_damage_action_v1(
  uuid,text,text,text,bigint
) is
  'WF-07: gestión interna auditada de reclamación por daños con evidencia y liquidación.';
