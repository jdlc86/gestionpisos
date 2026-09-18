-- GestionPisos · Flujos de Trabajo · revisión humana operativa
-- Completa closeType=human_review sin crear un motor paralelo:
-- - tareas sin Foto: revisión ROOT/ADMIN mediante acciones agency;
-- - tareas con Foto: reutiliza la revisión real de photo_verification_runs_v2.

create or replace function public.workflow_seed_task_actions_internal_v1(
  p_task_id uuid
)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $workflow_review_seed$
declare
  v_task public.tenant_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_requires_decision boolean:=false;
  v_has_remaining_steps boolean:=false;
  v_has_photo boolean:=false;
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

  v_requires_decision:=coalesce((v_execution.spec_snapshot->'steps'->>'accept')::boolean,false);
  v_has_photo:=coalesce((v_execution.spec_snapshot->'steps'->>'photo')::boolean,false);
  v_has_remaining_steps:=
    v_has_photo
    or coalesce((v_execution.spec_snapshot->'steps'->>'checklist')::boolean,false)
    or coalesce((v_execution.spec_snapshot->'steps'->>'document')::boolean,false);
  v_close_type:=nullif(v_execution.spec_snapshot->>'closeType','');

  if v_requires_decision then
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
      v_accept_target:=null;
    end if;

    if v_accept_target is not null then
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
    end if;
  end if;

  -- La revisión sin Foto se expresa con acciones agency del mismo task.
  -- Si hay Foto, la revisión se hace en la infraestructura fotoverificación.
  if v_close_type='human_review' and not v_has_photo then
    insert into public.tenant_task_actions_v2(
      task_id,action_key,label,from_status,to_status,requires_note,sort_order,active,actor
    ) values (
      v_task.id,'review_approve','Aprobar revisión','waiting_review','completed',false,90,true,'agency'
    )
    on conflict(task_id,action_key,from_status)
    do update set
      label=excluded.label,
      to_status=excluded.to_status,
      requires_note=excluded.requires_note,
      sort_order=excluded.sort_order,
      active=true,
      actor='agency';

    insert into public.tenant_task_actions_v2(
      task_id,action_key,label,from_status,to_status,requires_note,sort_order,active,actor
    ) values (
      v_task.id,'review_reject','Rechazar revisión','waiting_review','rejected',true,100,true,'agency'
    )
    on conflict(task_id,action_key,from_status)
    do update set
      label=excluded.label,
      to_status=excluded.to_status,
      requires_note=excluded.requires_note,
      sort_order=excluded.sort_order,
      active=true,
      actor='agency';
  end if;
end;
$workflow_review_seed$;

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
as $workflow_review_action$
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

  if v_action.actor='assignee' then
    if v_task.assigned_user_id is null
      or v_actor is distinct from v_task.assigned_user_id
      or v_actor is distinct from v_execution.assigned_user_id then
      raise exception 'workflow_action_actor_forbidden' using errcode='42501';
    end if;
  elsif v_action.actor='agency' then
    if not public.workflow_can_manage_v1(v_execution.organization_id) then
      raise exception 'workflow_review_actor_forbidden' using errcode='42501';
    end if;
  else
    raise exception 'workflow_action_actor_contract_invalid' using errcode='55000';
  end if;

  if v_action.requires_note and nullif(btrim(p_note),'') is null then
    raise exception 'workflow_action_note_required' using errcode='22023';
  end if;

  v_close_type:=nullif(v_execution.spec_snapshot->>'closeType','');

  if p_action_key in ('accept','reject') then
    if v_task.status<>'pending' or v_action.actor<>'assignee' then
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
  elsif p_action_key in ('review_approve','review_reject') then
    if v_task.status<>'waiting_review'
      or v_action.actor<>'agency'
      or v_close_type<>'human_review' then
      raise exception 'workflow_review_action_not_supported' using errcode='0A000';
    end if;

    if exists(
      select 1
      from public.workflow_execution_photo_resources_v2 er
      where er.execution_id=v_execution.id
    ) then
      raise exception 'workflow_photo_review_requires_photo_review_flow' using errcode='0A000';
    end if;

    v_expected_target:=case
      when p_action_key='review_approve' then 'completed'
      else 'rejected'
    end;
  else
    raise exception 'workflow_action_not_supported' using errcode='0A000';
  end if;

  if v_action.from_status<>v_task.status
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
    case
      when p_action_key in ('review_approve','review_reject') then 'workflow_human_review_applied'
      else 'workflow_task_action_applied'
    end,
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
$workflow_review_action$;

revoke all on function public.apply_workflow_task_action_v1(uuid,text,text,text) from public;
revoke execute on function public.apply_workflow_task_action_v1(uuid,text,text,text) from anon;
grant execute on function public.apply_workflow_task_action_v1(uuid,text,text,text) to authenticated;

create or replace function public.apply_workflow_photo_review_v1(
  p_run_id uuid,
  p_actor_user_id uuid,
  p_decision text,
  p_rejection_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $workflow_photo_review$
declare
  v_run public.photo_verification_runs_v2;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_resource public.workflow_execution_photo_resources_v2;
  v_photo_count integer:=0;
  v_reviewed_count integer:=0;
  v_rejected_count integer:=0;
  v_target_status text;
  v_reasons text;
  v_action_key text;
  v_action_label text;
begin
  if p_actor_user_id is null then
    raise exception 'workflow_review_actor_required' using errcode='22023';
  end if;

  if p_decision not in ('approved','rejected') then
    raise exception 'workflow_review_decision_invalid' using errcode='22023';
  end if;

  if p_decision='rejected' and nullif(btrim(p_rejection_reason),'') is null then
    raise exception 'workflow_review_rejection_reason_required' using errcode='22023';
  end if;

  select * into v_run
  from public.photo_verification_runs_v2
  where id=p_run_id
  for update;

  if v_run.id is null
    or v_run.source_type<>'workflow_execution'
    or v_run.source_id is null then
    raise exception 'workflow_photo_review_run_not_found' using errcode='P0002';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_run.source_id
  for update;

  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id
  for update;

  if v_task.id is null then
    raise exception 'workflow_task_not_found' using errcode='P0002';
  end if;

  select * into v_resource
  from public.workflow_execution_photo_resources_v2
  where execution_id=v_execution.id
    and photo_run_id=v_run.id
  for update;

  if v_resource.id is null
    or v_run.organization_id<>v_execution.organization_id
    or v_task.organization_id<>v_execution.organization_id then
    raise exception 'workflow_photo_review_identity_mismatch' using errcode='55000';
  end if;

  if not exists(
    select 1
    from public.user_roles ur
    where ur.user_id=p_actor_user_id
      and ur.revoked_at is null
      and (
        ur.role='root'
        or (ur.role='admin' and ur.organization_id=v_execution.organization_id)
      )
  ) then
    raise exception 'workflow_review_actor_forbidden' using errcode='42501';
  end if;

  if nullif(v_execution.spec_snapshot->>'closeType','')<>'human_review' then
    raise exception 'workflow_human_review_not_configured' using errcode='0A000';
  end if;

  if v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_state_mismatch' using errcode='55000';
  end if;

  -- Reintento después del cierre: no duplica histórico ni auditoría.
  if v_execution.status in ('completed','rejected') then
    if v_run.status<>p_decision then
      raise exception 'workflow_photo_review_conflict' using errcode='55000';
    end if;

    return jsonb_build_object(
      'ok',true,
      'applied_new',false,
      'run_status',v_run.status,
      'task_status',v_task.status,
      'execution_status',v_execution.status,
      'all_reviewed',true
    );
  end if;

  if v_execution.status<>'waiting_review' then
    raise exception 'workflow_not_waiting_review' using errcode='55000';
  end if;

  if v_run.status in ('submitted','manual_review','ai_review') then
    perform public.apply_photo_verification_review_v2(
      v_run.id,
      p_actor_user_id,
      p_decision,
      case when p_decision='rejected' then p_rejection_reason else null end
    );
  elsif v_run.status=p_decision then
    null;
  else
    raise exception 'workflow_photo_review_conflict' using errcode='55000';
  end if;

  select
    count(*),
    count(*) filter(where pr.status in ('approved','rejected')),
    count(*) filter(where pr.status='rejected'),
    string_agg(nullif(btrim(pr.rejection_reason),''),' · ') filter(where pr.status='rejected')
  into v_photo_count,v_reviewed_count,v_rejected_count,v_reasons
  from public.workflow_execution_photo_resources_v2 er
  left join public.photo_verification_runs_v2 pr on pr.id=er.photo_run_id
  where er.execution_id=v_execution.id;

  if v_photo_count=0 then
    raise exception 'workflow_photo_review_resources_missing' using errcode='55000';
  end if;

  if v_reviewed_count<v_photo_count then
    return jsonb_build_object(
      'ok',true,
      'applied_new',true,
      'run_status',p_decision,
      'task_status',v_task.status,
      'execution_status',v_execution.status,
      'all_reviewed',false,
      'reviewed_photo_count',v_reviewed_count,
      'photo_count',v_photo_count
    );
  end if;

  v_target_status:=case when v_rejected_count>0 then 'rejected' else 'completed' end;
  v_action_key:=case when v_target_status='completed' then 'review_approve' else 'review_reject' end;
  v_action_label:=case
    when v_target_status='completed' then 'Revisión humana aprobada'
    else 'Revisión humana rechazada'
  end;

  update public.tenant_tasks_v2
  set status=v_target_status,
      updated_at=now()
  where id=v_task.id
  returning * into v_task;

  update public.workflow_executions_v2 as updated_execution
  set status=v_target_status,
      updated_at=now(),
      completed_at=case
        when v_target_status='completed'
          then coalesce(updated_execution.completed_at,now())
        else updated_execution.completed_at
      end
  where id=v_execution.id
  returning * into v_execution;

  insert into public.tenant_task_history_v2(
    task_id,action_key,action_label,from_status,to_status,note,actor_user_id
  ) values (
    v_task.id,
    v_action_key,
    v_action_label,
    'waiting_review',
    v_target_status,
    case
      when v_target_status='rejected'
        then left(coalesce(v_reasons,'Una o más evidencias fotográficas fueron rechazadas.'),1000)
      else null
    end,
    p_actor_user_id
  );

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,
    v_execution.organization_id,
    'workflow_review_applied',
    'waiting_review',
    v_target_status,
    p_actor_user_id,
    jsonb_build_object(
      'task_id',v_task.id,
      'review_source','photo_verification',
      'photo_count',v_photo_count,
      'reviewed_photo_count',v_reviewed_count,
      'rejected_photo_count',v_rejected_count,
      'trigger_run_id',p_run_id
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,
    p_actor_user_id,
    'workflow_human_review_applied',
    'workflow_execution',
    v_execution.id::text,
    'success',
    jsonb_build_object(
      'review_source','photo_verification',
      'target_status',v_target_status,
      'photo_count',v_photo_count,
      'rejected_photo_count',v_rejected_count,
      'trigger_run_id',p_run_id
    )
  );

  return jsonb_build_object(
    'ok',true,
    'applied_new',true,
    'run_status',p_decision,
    'task_status',v_task.status,
    'execution_status',v_execution.status,
    'all_reviewed',true,
    'reviewed_photo_count',v_reviewed_count,
    'photo_count',v_photo_count,
    'rejected_photo_count',v_rejected_count
  );
end;
$workflow_photo_review$;

revoke all on function public.apply_workflow_photo_review_v1(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.apply_workflow_photo_review_v1(uuid,uuid,text,text)
  to service_role;

-- Visibilidad actor-aware de acciones. En workflow, el asignado ve solo
-- acciones assignee y ROOT/ADMIN autorizados ven las acciones agency.
-- Las tareas legacy conservan su criterio anterior.
drop policy if exists tenant_task_actions_v2_read_scope
  on public.tenant_task_actions_v2;
drop policy if exists tenant_task_actions_v2_workflow_manager_read
  on public.tenant_task_actions_v2;

create policy tenant_task_actions_v2_read_scope
on public.tenant_task_actions_v2
for select
to authenticated
using (
  exists(
    select 1
    from public.tenant_tasks_v2 t
    where t.id=tenant_task_actions_v2.task_id
      and (
        (
          t.task_type='workflow'
          and t.source_kind='workflow_execution'
          and (
            (
              tenant_task_actions_v2.actor='assignee'
              and t.assigned_user_id=auth.uid()
            )
            or (
              tenant_task_actions_v2.actor='agency'
              and public.workflow_can_manage_v1(t.organization_id)
            )
            or (
              tenant_task_actions_v2.actor='tenant'
              and exists(
                select 1
                from public.tenants_v2 tn
                where tn.id=t.tenant_id
                  and tn.user_id=auth.uid()
              )
            )
          )
        )
        or (
          (t.task_type<>'workflow' or t.source_kind is distinct from 'workflow_execution')
          and (
            public.can_operate_property_v3(t.property_id,false)
            or t.assigned_user_id=auth.uid()
            or exists(
              select 1
              from public.tenants_v2 tn
              where tn.id=t.tenant_id
                and tn.user_id=auth.uid()
            )
          )
        )
      )
  )
);

-- Backfill seguro de acciones de revisión para tareas workflow ya materializadas.
do $workflow_review_backfill$
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
$workflow_review_backfill$;

comment on function public.apply_workflow_photo_review_v1(uuid,uuid,text,text) is
  'Reutiliza la revisión fotográfica existente y sincroniza el cierre human_review del workflow cuando todas sus evidencias han sido revisadas.';
