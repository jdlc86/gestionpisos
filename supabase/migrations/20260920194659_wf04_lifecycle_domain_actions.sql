-- WF-04: acciones de llaves y confirmación de Entrada/Salida sobre la tarjeta
-- transversal existente. Ninguna de estas funciones escribe Auth, roles,
-- tenants_v2 ni occupancies_v2.

create unique index workflow_execution_events_v2_wf04_request_uq
  on public.workflow_execution_events_v2(
    execution_id,((details->>'request_key'))
  )
  where event_type='wf04_domain_action' and details ? 'request_key';

create unique index workflow_execution_events_v2_wf04_action_uq
  on public.workflow_execution_events_v2(
    execution_id,((details->>'action_key'))
  )
  where event_type='wf04_domain_action' and details ? 'action_key';

create function private.workflow_wf04_staff_current_v1(
  p_organization_id uuid,
  p_property_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select p_user_id is not null and p_property_id is not null and (
    exists(
      select 1 from public.user_roles ur
      where ur.user_id=p_user_id
        and ur.organization_id=p_organization_id
        and ur.role='admin'
        and ur.revoked_at is null
    )
    or exists(
      select 1
      from public.user_roles ur
      join public.property_staff_access_v3 a
        on a.employee_user_id=ur.user_id
       and a.property_id=p_property_id
       and a.organization_id=p_organization_id
      where ur.user_id=p_user_id
        and ur.organization_id=p_organization_id
        and ur.role='employee'
        and ur.revoked_at is null
        and a.revoked_at is null
        and a.valid_from<=now()
        and (a.valid_until is null or a.valid_until>now())
        and a.can_write=true
    )
  );
$$;
revoke all on function private.workflow_wf04_staff_current_v1(uuid,uuid,uuid)
  from public,anon,authenticated,service_role;

create function private.workflow_wf04_seed_domain_actions_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_event public.workflow_event_outbox_v2;
  v_task public.tenant_tasks_v2;
  v_flow text:=new.spec_snapshot->>'flowType';
  v_key_action text;
  v_confirm_action text;
begin
  if new.source_event_id is null
    or old.source_event_id is not null
    or new.spec_snapshot->>'closeType'<>'domain_adapter'
    or v_flow not in ('checkin','checkout') then
    return new;
  end if;

  select * into v_event
  from public.workflow_event_outbox_v2
  where id=new.source_event_id;
  if v_event.id is null
    or v_event.occupancy_id is null
    or v_event.organization_id<>new.organization_id
    or v_event.property_id is distinct from new.property_id
    or (new.scope_type='room' and v_event.room_id is distinct from new.room_id)
    or v_event.event_type is distinct from (case v_flow
       when 'checkin' then 'occupancy.created'
       else 'occupancy.offboarded' end) then
    raise exception 'workflow_wf04_event_mismatch' using errcode='55000';
  end if;

  if not private.workflow_wf04_staff_current_v1(
    new.organization_id,new.property_id,new.assigned_user_id
  ) then
    raise exception 'workflow_wf04_assignee_not_eligible' using errcode='42501';
  end if;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution' and source_id=new.id;
  if v_task.id is null or v_task.status<>'pending'
    or v_task.assigned_user_id is distinct from new.assigned_user_id then
    raise exception 'workflow_wf04_task_mismatch' using errcode='55000';
  end if;

  v_key_action:=case v_flow
    when 'checkin' then 'key_pickup' else 'key_delivery' end;
  v_confirm_action:=case v_flow
    when 'checkin' then 'check_in' else 'check_out' end;

  insert into public.tenant_task_actions_v2(
    task_id,action_key,label,from_status,to_status,
    requires_note,sort_order,active,actor
  ) values
    (v_task.id,'accept','Aceptar','pending','active',false,10,true,'assignee'),
    (v_task.id,'reject','Rechazar','pending','rejected',true,20,true,'assignee'),
    (v_task.id,v_key_action,
      case v_flow when 'checkin' then 'Confirmar recogida de llaves'
        else 'Confirmar entrega de llaves' end,
      'active','active',false,30,true,'assignee'),
    (v_task.id,v_confirm_action,
      case v_flow when 'checkin' then 'Confirmar entrada'
        else 'Confirmar salida' end,
      'active','completed',false,40,false,'assignee')
  on conflict(task_id,action_key,from_status)
  do update set
    label=excluded.label,
    to_status=excluded.to_status,
    requires_note=excluded.requires_note,
    sort_order=excluded.sort_order,
    active=excluded.active,
    actor=excluded.actor;

  return new;
end;
$$;
revoke all on function private.workflow_wf04_seed_domain_actions_v1()
  from public,anon,authenticated,service_role;

create trigger workflow_wf04_seed_domain_actions_v1
after update of source_event_id on public.workflow_executions_v2
for each row
when (old.source_event_id is null and new.source_event_id is not null)
execute function private.workflow_wf04_seed_domain_actions_v1();

create function private.apply_wf04_domain_action_v1(
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
as $$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_task public.tenant_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_event public.workflow_event_outbox_v2;
  v_occupancy public.occupancies_v2;
  v_action public.tenant_task_actions_v2;
  v_previous public.workflow_execution_events_v2;
  v_flow text;
  v_key_action text;
  v_confirm_action text;
  v_target_execution_status text;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_wf04_request_key_invalid' using errcode='22023';
  end if;

  select * into v_task from public.tenant_tasks_v2
  where id=p_task_id for update;
  if v_task.id is null then
    raise exception 'workflow_task_not_found' using errcode='P0002';
  end if;
  if v_task.task_type<>'workflow'
    or v_task.source_kind<>'workflow_execution'
    or v_task.source_id is null then
    raise exception 'workflow_task_required' using errcode='22023';
  end if;

  select * into v_execution from public.workflow_executions_v2
  where id=v_task.source_id for update;
  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;
  v_flow:=v_execution.spec_snapshot->>'flowType';
  if v_execution.spec_snapshot->>'closeType'<>'domain_adapter'
    or v_flow not in ('checkin','checkout')
    or v_execution.source_event_id is null then
    raise exception 'workflow_wf04_domain_required' using errcode='22023';
  end if;

  perform private.workflow_require_current_actor_v1(v_execution.id);
  if not private.workflow_wf04_staff_current_v1(
    v_execution.organization_id,v_execution.property_id,v_actor
  ) then
    raise exception 'workflow_wf04_assignee_not_eligible' using errcode='42501';
  end if;

  select * into v_event from public.workflow_event_outbox_v2
  where id=v_execution.source_event_id;
  select * into v_occupancy from public.occupancies_v2
  where id=v_event.occupancy_id for update;
  if v_event.id is null
    or v_event.source_kind<>'occupancy'
    or v_event.source_id is distinct from v_occupancy.id
    or v_event.organization_id is distinct from v_execution.organization_id
    or v_event.property_id is distinct from v_execution.property_id
    or (v_execution.scope_type='room'
        and v_event.room_id is distinct from v_execution.room_id)
    or v_occupancy.organization_id is distinct from v_event.organization_id
    or v_occupancy.property_id is distinct from v_event.property_id
    or v_occupancy.room_id is distinct from v_event.room_id
    or v_occupancy.tenant_id is null
    or v_task.tenant_id is distinct from v_occupancy.tenant_id
    or v_task.organization_id is distinct from v_execution.organization_id
    or v_task.property_id is distinct from v_execution.property_id
    or v_task.room_id is distinct from v_execution.room_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id
    or (v_flow='checkin'
        and (v_event.event_type<>'occupancy.created'
             or v_occupancy.status<>'active'))
    or (v_flow='checkout'
        and (v_event.event_type<>'occupancy.offboarded'
             or v_occupancy.status<>'archived')) then
    raise exception 'workflow_wf04_subject_not_current' using errcode='55000';
  end if;

  v_key_action:=case v_flow
    when 'checkin' then 'key_pickup' else 'key_delivery' end;
  v_confirm_action:=case v_flow
    when 'checkin' then 'check_in' else 'check_out' end;
  if p_action_key not in ('accept','reject',v_key_action,v_confirm_action) then
    raise exception 'workflow_wf04_action_not_supported' using errcode='22023';
  end if;

  select * into v_previous
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='wf04_domain_action'
    and ev.details->>'request_key'=v_key
  limit 1;
  if v_previous.id is not null then
    if v_previous.details->>'action_key' is distinct from p_action_key
      or v_previous.details->>'task_id' is distinct from p_task_id::text then
      raise exception 'workflow_action_request_key_conflict' using errcode='55000';
    end if;
    return query select v_task.id,v_task.status,v_execution.id,v_execution.status,false;
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
  if v_action.requires_note and nullif(btrim(p_note),'') is null then
    raise exception 'workflow_action_note_required' using errcode='22023';
  end if;

  if p_action_key=v_confirm_action then
    if not exists(
      select 1 from public.workflow_execution_events_v2 ev
      where ev.execution_id=v_execution.id
        and ev.event_type='wf04_domain_action'
        and ev.details->>'action_key'=v_key_action
    ) then
      raise exception 'workflow_wf04_key_required' using errcode='55000';
    end if;
    if v_flow='checkin' and (
      v_occupancy.starts_on is null
      or v_occupancy.starts_on>current_date
      or (v_occupancy.ends_on is not null
          and v_occupancy.ends_on<current_date)
    ) then
      raise exception 'workflow_wf04_checkin_not_current' using errcode='55000';
    end if;
  end if;

  v_target_execution_status:=case p_action_key
    when 'reject' then 'failed'
    else v_action.to_status end;

  update public.tenant_tasks_v2
  set status=v_action.to_status,updated_at=now()
  where id=v_task.id returning * into v_task;
  update public.workflow_executions_v2
  set status=v_target_execution_status,
      updated_at=now(),
      started_at=case when p_action_key='accept'
        then coalesce(started_at,now()) else started_at end,
      completed_at=case when p_action_key=v_confirm_action
        then coalesce(completed_at,now()) else completed_at end
  where id=v_execution.id returning * into v_execution;

  if p_action_key=v_key_action then
    update public.tenant_task_actions_v2 a
    set active=false
    where a.task_id=v_task.id and a.action_key=v_key_action
      and a.from_status='active';
    update public.tenant_task_actions_v2 a
    set active=true
    where a.task_id=v_task.id and a.action_key=v_confirm_action
      and a.from_status='active';
  end if;

  insert into public.tenant_task_history_v2(
    task_id,action_key,action_label,from_status,to_status,note,actor_user_id
  ) values (
    v_task.id,v_action.action_key,v_action.label,v_action.from_status,
    v_action.to_status,nullif(btrim(p_note),''),v_actor
  );
  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,
    actor_user_id,details
  ) values (
    v_execution.id,v_execution.organization_id,'wf04_domain_action',
    case when p_action_key in ('accept','reject') then 'pending' else 'active' end,
    v_execution.status,v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'action_key',p_action_key,
      'request_key',v_key,
      'source_event_id',v_event.id,
      'occupancy_id',v_occupancy.id,
      'tenant_id',v_occupancy.tenant_id
    )
  );
  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,v_actor,'workflow_wf04_action_applied',
    'workflow_execution',v_execution.id::text,'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'action_key',p_action_key,
      'request_key',v_key,
      'source_event_id',v_event.id,
      'occupancy_id',v_occupancy.id,
      'task_status',v_task.status,
      'execution_status',v_execution.status
    )
  );

  return query select v_task.id,v_task.status,v_execution.id,v_execution.status,true;
end;
$$;
revoke all on function private.apply_wf04_domain_action_v1(uuid,text,text,text)
  from public,anon,authenticated,service_role;

-- Mantener la firma pública y el guard previo de otros workflows. Solo el
-- snapshot WF-04 opt-in usa el adaptador; los históricos continúan por la RPC
-- atómica genérica existente.
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
as $$
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
    if v_spec->>'flowType' in ('checkin','checkout')
      and v_spec->>'closeType'='domain_adapter' then
      return query select * from private.apply_wf04_domain_action_v1(
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

  return query select * from private.apply_workflow_task_action_v1(
    p_task_id,p_action_key,p_request_key,p_note
  );
end;
$$;
revoke all on function public.apply_workflow_task_action_v1(uuid,text,text,text)
  from public,anon;
grant execute on function public.apply_workflow_task_action_v1(uuid,text,text,text)
  to authenticated,service_role;
