-- GestionPisos · Flujos de Trabajo · decisión Aceptar/Rechazar
-- Amplía el paso histórico steps.accept=true para representar una decisión explícita del asignado.
-- Mantiene compatibilidad con specs publicadas: la clave JSON sigue siendo "accept".

alter table public.workflow_executions_v2
  drop constraint if exists workflow_executions_v2_status_check;

alter table public.workflow_executions_v2
  add constraint workflow_executions_v2_status_check
  check (status in ('pending','active','waiting_review','completed','cancelled','failed','rejected'));

create or replace function public.workflow_seed_task_actions_internal_v1(
  p_task_id uuid
)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $workflow_decision_seed$
declare
  v_task public.tenant_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_requires_decision boolean:=false;
  v_has_remaining_steps boolean:=false;
  v_close_type text;
  v_accept_target text;
  v_accept_label text;
begin
  select * into v_task
  from public.tenant_tasks_v2
  where id=p_task_id;

  if v_task.id is null
    or v_task.task_type<>'workflow'
    or v_task.source_kind<>'workflow_execution'
    or v_task.source_id is null then
    return;
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_task.source_id;

  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  if v_task.organization_id<>v_execution.organization_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id
    or v_task.property_id is distinct from v_execution.property_id
    or v_task.room_id is distinct from v_execution.room_id then
    raise exception 'workflow_task_execution_identity_mismatch' using errcode='55000';
  end if;

  -- Compatibilidad: steps.accept=true significa "requerir decisión Aceptar/Rechazar".
  v_requires_decision:=coalesce((v_execution.spec_snapshot->'steps'->>'accept')::boolean,false);
  v_has_remaining_steps:=
    coalesce((v_execution.spec_snapshot->'steps'->>'photo')::boolean,false)
    or coalesce((v_execution.spec_snapshot->'steps'->>'checklist')::boolean,false)
    or coalesce((v_execution.spec_snapshot->'steps'->>'document')::boolean,false);
  v_close_type:=nullif(v_execution.spec_snapshot->>'closeType','');

  if not v_requires_decision then
    return;
  end if;

  if v_has_remaining_steps then
    v_accept_target:='active';
    v_accept_label:='Aceptar';
  elsif v_close_type='auto' then
    v_accept_target:='completed';
    v_accept_label:='Aceptar y completar';
  elsif v_close_type='human_review' then
    v_accept_target:='waiting_review';
    v_accept_label:='Aceptar y enviar a revisión';
  else
    -- Si no existe un destino seguro para Aceptar, no se publica una pareja incompleta.
    return;
  end if;

  insert into public.tenant_task_actions_v2(
    task_id,action_key,label,from_status,to_status,requires_note,sort_order,active,actor
  ) values (
    v_task.id,'accept',v_accept_label,'pending',v_accept_target,false,10,true,'assignee'
  )
  on conflict(task_id,action_key,from_status)
  do update set
    label=excluded.label,
    to_status=excluded.to_status,
    requires_note=excluded.requires_note,
    sort_order=excluded.sort_order,
    active=true,
    actor='assignee';

  insert into public.tenant_task_actions_v2(
    task_id,action_key,label,from_status,to_status,requires_note,sort_order,active,actor
  ) values (
    v_task.id,'reject','Rechazar','pending','rejected',true,20,true,'assignee'
  )
  on conflict(task_id,action_key,from_status)
  do update set
    label=excluded.label,
    to_status=excluded.to_status,
    requires_note=excluded.requires_note,
    sort_order=excluded.sort_order,
    active=true,
    actor='assignee';
end;
$workflow_decision_seed$;

revoke all on function public.workflow_seed_task_actions_internal_v1(uuid)
  from public,anon,authenticated;

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
set search_path=public,pg_temp
as $workflow_decision_apply$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_task public.tenant_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_action public.tenant_task_actions_v2;
  v_previous_event public.workflow_execution_events_v2;
  v_requires_decision boolean:=false;
  v_has_remaining_steps boolean:=false;
  v_close_type text;
  v_expected_target text;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_action_request_key_invalid' using errcode='22023';
  end if;

  if nullif(btrim(p_action_key),'') is null then
    raise exception 'workflow_action_key_invalid' using errcode='22023';
  end if;

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

  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  if v_task.organization_id<>v_execution.organization_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id
    or v_task.property_id is distinct from v_execution.property_id
    or v_task.room_id is distinct from v_execution.room_id then
    raise exception 'workflow_task_execution_identity_mismatch' using errcode='55000';
  end if;

  select * into v_previous_event
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='task_action_applied'
    and ev.details->>'request_key'=v_key
  order by ev.id
  limit 1;

  if v_previous_event.id is not null then
    if v_previous_event.details->>'action_key' is distinct from p_action_key
      or v_previous_event.details->>'task_id' is distinct from p_task_id::text then
      raise exception 'workflow_action_request_key_conflict' using errcode='55000';
    end if;

    return query
    select v_task.id,v_task.status,v_execution.id,v_execution.status,false;
    return;
  end if;

  if v_task.assigned_user_id is null
    or v_actor is distinct from v_task.assigned_user_id
    or v_actor is distinct from v_execution.assigned_user_id then
    raise exception 'workflow_action_actor_forbidden' using errcode='42501';
  end if;

  if v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_state_mismatch' using errcode='55000';
  end if;

  select a.* into v_action
  from public.tenant_task_actions_v2 a
  where a.task_id=v_task.id
    and a.action_key=p_action_key
    and a.from_status=v_task.status
    and a.active=true;

  if v_action.id is null then
    raise exception 'workflow_action_not_allowed' using errcode='22023';
  end if;

  if v_action.actor<>'assignee' then
    raise exception 'workflow_action_actor_contract_invalid' using errcode='55000';
  end if;

  if v_action.requires_note and nullif(btrim(p_note),'') is null then
    raise exception 'workflow_action_note_required' using errcode='22023';
  end if;

  if p_action_key not in ('accept','reject') or v_task.status<>'pending' then
    raise exception 'workflow_action_not_supported' using errcode='0A000';
  end if;

  v_requires_decision:=coalesce((v_execution.spec_snapshot->'steps'->>'accept')::boolean,false);
  if not v_requires_decision then
    raise exception 'workflow_accept_step_not_configured' using errcode='55000';
  end if;

  if p_action_key='reject' then
    v_expected_target:='rejected';
  else
    v_has_remaining_steps:=
      coalesce((v_execution.spec_snapshot->'steps'->>'photo')::boolean,false)
      or coalesce((v_execution.spec_snapshot->'steps'->>'checklist')::boolean,false)
      or coalesce((v_execution.spec_snapshot->'steps'->>'document')::boolean,false);
    v_close_type:=nullif(v_execution.spec_snapshot->>'closeType','');

    if v_has_remaining_steps then
      v_expected_target:='active';
    elsif v_close_type='auto' then
      v_expected_target:='completed';
    elsif v_close_type='human_review' then
      v_expected_target:='waiting_review';
    else
      raise exception 'workflow_action_close_rule_not_supported' using errcode='0A000';
    end if;
  end if;

  if v_action.from_status<>'pending'
    or v_action.to_status<>v_expected_target then
    raise exception 'workflow_action_transition_contract_mismatch' using errcode='55000';
  end if;

  update public.tenant_tasks_v2
  set status=v_expected_target,
      updated_at=now()
  where id=v_task.id
  returning * into v_task;

  update public.workflow_executions_v2 as updated_execution
  set status=v_expected_target,
      updated_at=now(),
      started_at=case
        when v_expected_target in ('active','waiting_review','completed')
          then coalesce(updated_execution.started_at,now())
        else updated_execution.started_at
      end,
      completed_at=case
        when v_expected_target='completed'
          then coalesce(updated_execution.completed_at,now())
        else updated_execution.completed_at
      end
  where id=v_execution.id
  returning * into v_execution;

  if p_action_key='reject' then
    update public.workflow_execution_photo_resources_v2 as photo_resource
    set status='cancelled',
        completed_at=coalesce(photo_resource.completed_at,now())
    where photo_resource.execution_id=v_execution.id
      and photo_resource.status in ('pending','capturing');
  end if;

  insert into public.tenant_task_history_v2(
    task_id,action_key,action_label,from_status,to_status,note,actor_user_id
  ) values (
    v_task.id,
    v_action.action_key,
    v_action.label,
    v_action.from_status,
    v_action.to_status,
    nullif(btrim(p_note),''),
    v_actor
  );

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,
    v_execution.organization_id,
    'task_action_applied',
    v_action.from_status,
    v_expected_target,
    v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'action_key',v_action.action_key,
      'request_key',v_key,
      'action_label',v_action.label
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,
    v_actor,
    'workflow_task_action_applied',
    'workflow_execution',
    v_execution.id::text,
    'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'action_key',v_action.action_key,
      'from_status',v_action.from_status,
      'to_status',v_expected_target,
      'request_key',v_key
    )
  );

  return query
  select v_task.id,v_task.status,v_execution.id,v_execution.status,true;
end;
$workflow_decision_apply$;

revoke all on function public.apply_workflow_task_action_v1(uuid,text,text,text) from public;
revoke execute on function public.apply_workflow_task_action_v1(uuid,text,text,text) from anon;
grant execute on function public.apply_workflow_task_action_v1(uuid,text,text,text) to authenticated;

-- Backfill seguro: agrega la pareja Aceptar/Rechazar a tareas materializadas
-- cuyo snapshot ya requería el antiguo paso "accept".
do $workflow_decision_backfill$
declare
  r record;
begin
  for r in
    select t.id
    from public.tenant_tasks_v2 t
    where t.task_type='workflow'
      and t.source_kind='workflow_execution'
  loop
    perform public.workflow_seed_task_actions_internal_v1(r.id);
  end loop;
end;
$workflow_decision_backfill$;

comment on function public.apply_workflow_task_action_v1(uuid,text,text,text) is
  'Aplica de forma idempotente y atómica la decisión Aceptar/Rechazar sobre tarea + ejecución; Rechazar exige motivo.';
