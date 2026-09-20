-- GestionPisos · WF-03 · cierre de auditoría de Limpieza sobre el motor transversal
-- tenant_tasks_v2 sigue siendo la única tarjeta operativa.
-- La auditoría de limpieza decide waiting_review / completed / rejected sin crear tareas paralelas.

create or replace function private.workflow_finalize_cleaning_audit_v1(
  p_audit_id uuid,
  p_actor_user_id uuid default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $workflow_finalize_cleaning_audit$
declare
  v_audit public.cleaning_audits_v2;
  v_cleaning public.cleaning_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_rejected_count integer:=0;
  v_domain_target text;
  v_workflow_target text;
  v_from_workflow text;
  v_label text;
begin
  select *
  into v_audit
  from public.cleaning_audits_v2
  where id=p_audit_id
  for update;

  if v_audit.id is null then
    raise exception 'cleaning_audit_not_found' using errcode='P0002';
  end if;

  if v_audit.selected_for_review then
    if v_audit.status not in ('closed','expired') then
      raise exception 'cleaning_audit_not_final' using errcode='55000';
    end if;
  elsif v_audit.status<>'not_selected' then
    raise exception 'cleaning_audit_not_final' using errcode='55000';
  end if;

  select *
  into v_cleaning
  from public.cleaning_tasks_v2
  where id=v_audit.cleaning_task_id
  for update;

  if v_cleaning.id is null then
    raise exception 'cleaning_task_not_found' using errcode='P0002';
  end if;

  -- Expedientes legacy sin vínculo transversal conservan su ciclo actual.
  if v_cleaning.workflow_execution_id is null then
    return jsonb_build_object(
      'ok',true,
      'workflow_linked',false,
      'applied_new',false,
      'cleaning_status',v_cleaning.status
    );
  end if;

  select *
  into v_execution
  from public.workflow_executions_v2
  where id=v_cleaning.workflow_execution_id
  for update;

  if v_execution.id is null
    or coalesce(v_execution.spec_snapshot->>'flowType','')<>'cleaning'
    or v_execution.organization_id<>v_cleaning.organization_id
    or v_execution.property_id is distinct from v_cleaning.property_id
    or v_execution.assigned_user_id is distinct from v_cleaning.assigned_user_id then
    raise exception 'workflow_cleaning_audit_identity_mismatch' using errcode='55000';
  end if;

  select *
  into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id
  for update;

  if v_task.id is null
    or v_task.organization_id<>v_execution.organization_id
    or v_task.property_id is distinct from v_execution.property_id
    or v_task.room_id is distinct from v_execution.room_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
    raise exception 'workflow_cleaning_task_state_mismatch' using errcode='55000';
  end if;

  select count(*)::integer
  into v_rejected_count
  from public.cleaning_audit_items_v2 i
  where i.audit_id=v_audit.id
    and i.result='rejected';

  v_domain_target:=case when v_rejected_count>0 then 'rejected' else 'approved' end;
  v_workflow_target:=case when v_rejected_count>0 then 'rejected' else 'completed' end;

  if v_cleaning.status=v_domain_target
    and v_execution.status=v_workflow_target
    and v_task.status=v_workflow_target then
    return jsonb_build_object(
      'ok',true,
      'workflow_linked',true,
      'applied_new',false,
      'cleaning_status',v_cleaning.status,
      'task_status',v_task.status,
      'execution_status',v_execution.status,
      'rejected_photo_count',v_rejected_count
    );
  end if;

  v_from_workflow:=v_execution.status;

  if v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_state_mismatch' using errcode='55000';
  end if;

  if v_audit.selected_for_review then
    if v_execution.status<>'waiting_review'
      or v_cleaning.status<>'submitted' then
      raise exception 'workflow_cleaning_review_state_mismatch' using errcode='55000';
    end if;
  else
    if v_execution.status<>'active'
      or v_cleaning.status<>'submitted' then
      raise exception 'workflow_cleaning_auto_close_state_mismatch' using errcode='55000';
    end if;
  end if;

  update public.cleaning_tasks_v2
  set status=v_domain_target,
      reviewed_at=case
        when v_audit.selected_for_review then coalesce(reviewed_at,now())
        else reviewed_at
      end,
      reviewed_by=case
        when v_audit.selected_for_review
          and v_audit.status='closed'
          and p_actor_user_id is not null
          then coalesce(reviewed_by,p_actor_user_id)
        else reviewed_by
      end,
      updated_at=now()
  where id=v_cleaning.id
  returning * into v_cleaning;

  update public.tenant_tasks_v2
  set status=v_workflow_target,
      updated_at=now()
  where id=v_task.id
  returning * into v_task;

  update public.workflow_executions_v2 as e
  set status=v_workflow_target,
      updated_at=now(),
      completed_at=case
        when v_workflow_target='completed' then coalesce(e.completed_at,now())
        else e.completed_at
      end
  where id=v_execution.id
  returning * into v_execution;

  v_label:=case
    when v_workflow_target='rejected' then 'Auditoría de limpieza rechazada'
    when v_audit.selected_for_review and v_audit.status='expired' then 'Auditoría de limpieza cerrada por plazo'
    when v_audit.selected_for_review then 'Auditoría de limpieza aprobada'
    else 'Limpieza completada sin auditoría humana'
  end;

  insert into public.tenant_task_history_v2(
    task_id,action_key,action_label,from_status,to_status,note,actor_user_id
  ) values (
    v_task.id,
    case
      when v_audit.selected_for_review and v_audit.status='expired' then 'cleaning_review_expired'
      when v_audit.selected_for_review then 'cleaning_review_closed'
      else 'cleaning_auto_closed'
    end,
    v_label,
    v_from_workflow,
    v_workflow_target,
    nullif(btrim(p_reason),''),
    p_actor_user_id
  );

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,
    v_execution.organization_id,
    'domain_adapter_review_closed',
    v_from_workflow,
    v_workflow_target,
    p_actor_user_id,
    jsonb_build_object(
      'adapter','cleaning',
      'cleaning_task_id',v_cleaning.id,
      'cleaning_audit_id',v_audit.id,
      'audit_status',v_audit.status,
      'selected_for_review',v_audit.selected_for_review,
      'rejected_photo_count',v_rejected_count,
      'domain_to_status',v_domain_target,
      'reason',nullif(btrim(p_reason),'')
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,
    p_actor_user_id,
    'workflow_cleaning_audit_closed',
    'workflow_execution',
    v_execution.id::text,
    'success',
    jsonb_build_object(
      'cleaning_task_id',v_cleaning.id,
      'cleaning_audit_id',v_audit.id,
      'audit_status',v_audit.status,
      'selected_for_review',v_audit.selected_for_review,
      'workflow_target',v_workflow_target,
      'domain_target',v_domain_target,
      'rejected_photo_count',v_rejected_count
    )
  );

  return jsonb_build_object(
    'ok',true,
    'workflow_linked',true,
    'applied_new',true,
    'cleaning_status',v_cleaning.status,
    'task_status',v_task.status,
    'execution_status',v_execution.status,
    'rejected_photo_count',v_rejected_count
  );
end;
$workflow_finalize_cleaning_audit$;

revoke all on function private.workflow_finalize_cleaning_audit_v1(uuid,uuid,text)
  from public,anon,authenticated,service_role;

create or replace function private.workflow_sync_cleaning_audit_selection_v1(
  p_cleaning_task_id uuid,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $workflow_sync_cleaning_audit_selection$
declare
  v_cleaning public.cleaning_tasks_v2;
  v_audit public.cleaning_audits_v2;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
begin
  select *
  into v_cleaning
  from public.cleaning_tasks_v2
  where id=p_cleaning_task_id
  for update;

  if v_cleaning.id is null then
    raise exception 'cleaning_task_not_found' using errcode='P0002';
  end if;

  if v_cleaning.workflow_execution_id is null then
    return jsonb_build_object('ok',true,'workflow_linked',false,'applied_new',false);
  end if;

  select *
  into v_audit
  from public.cleaning_audits_v2
  where cleaning_task_id=v_cleaning.id
  for update;

  if v_audit.id is null then
    raise exception 'cleaning_audit_not_found' using errcode='P0002';
  end if;

  select *
  into v_execution
  from public.workflow_executions_v2
  where id=v_cleaning.workflow_execution_id
  for update;

  select *
  into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id
  for update;

  if v_execution.id is null
    or v_task.id is null
    or coalesce(v_execution.spec_snapshot->>'flowType','')<>'cleaning'
    or v_execution.organization_id<>v_cleaning.organization_id
    or v_task.organization_id<>v_execution.organization_id
    or v_execution.assigned_user_id is distinct from v_cleaning.assigned_user_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
    raise exception 'workflow_cleaning_audit_identity_mismatch' using errcode='55000';
  end if;

  if v_audit.selected_for_review then
    if v_audit.status<>'open' then
      if v_audit.status in ('closed','expired') then
        return private.workflow_finalize_cleaning_audit_v1(
          v_audit.id,
          p_actor_user_id,
          'audit_already_final'
        );
      end if;
      raise exception 'cleaning_audit_state_invalid' using errcode='55000';
    end if;

    if v_execution.status='waiting_review'
      and v_task.status='waiting_review'
      and v_cleaning.status='submitted' then
      return jsonb_build_object(
        'ok',true,
        'workflow_linked',true,
        'applied_new',false,
        'cleaning_status',v_cleaning.status,
        'task_status',v_task.status,
        'execution_status',v_execution.status
      );
    end if;

    if v_execution.status<>'active'
      or v_task.status<>'active'
      or v_cleaning.status<>'submitted' then
      raise exception 'workflow_cleaning_review_state_mismatch' using errcode='55000';
    end if;

    update public.tenant_tasks_v2
    set status='waiting_review',
        updated_at=now()
    where id=v_task.id;

    update public.workflow_executions_v2
    set status='waiting_review',
        updated_at=now(),
        started_at=coalesce(started_at,now())
    where id=v_execution.id;

    insert into public.tenant_task_history_v2(
      task_id,action_key,action_label,from_status,to_status,note,actor_user_id
    ) values (
      v_task.id,
      'cleaning_review_selected',
      'Seleccionada para auditoría de limpieza',
      'active',
      'waiting_review',
      null,
      p_actor_user_id
    );

    insert into public.workflow_execution_events_v2(
      execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
    ) values (
      v_execution.id,
      v_execution.organization_id,
      'domain_adapter_review_selected',
      'active',
      'waiting_review',
      p_actor_user_id,
      jsonb_build_object(
        'adapter','cleaning',
        'cleaning_task_id',v_cleaning.id,
        'cleaning_audit_id',v_audit.id,
        'review_deadline',v_audit.review_deadline
      )
    );

    return jsonb_build_object(
      'ok',true,
      'workflow_linked',true,
      'applied_new',true,
      'cleaning_status',v_cleaning.status,
      'task_status','waiting_review',
      'execution_status','waiting_review'
    );
  end if;

  if v_audit.status<>'not_selected' then
    raise exception 'cleaning_audit_state_invalid' using errcode='55000';
  end if;

  return private.workflow_finalize_cleaning_audit_v1(
    v_audit.id,
    p_actor_user_id,
    'not_selected'
  );
end;
$workflow_sync_cleaning_audit_selection$;

revoke all on function private.workflow_sync_cleaning_audit_selection_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

-- Redefine selection: the draw still happens only after all frozen photos are complete,
-- but the result now projects immediately to the transversal workflow.
create or replace function private.select_cleaning_audit_v2(
  p_cleaning_task_id uuid,
  p_photo_run_id uuid,
  p_random_value double precision default random(),
  p_now timestamptz default now()
)
returns public.cleaning_audits_v2
language plpgsql
security definer
set search_path=public,private,pg_temp
as $workflow_cleaning_audit$
declare
  v_task public.cleaning_tasks_v2;
  v_run public.photo_verification_runs_v2;
  v_policy public.cleaning_audit_policies_v2;
  v_selected boolean;
  v_audit public.cleaning_audits_v2;
  v_has_requests boolean:=false;
begin
  if p_random_value < 0 or p_random_value >= 1 then
    raise exception 'random_value_out_of_range' using errcode='22023';
  end if;

  select * into v_audit
  from public.cleaning_audits_v2
  where cleaning_task_id=p_cleaning_task_id;

  if found then
    perform private.workflow_sync_cleaning_audit_selection_v1(
      p_cleaning_task_id,
      (
        select actor_user_id
        from public.photo_verification_runs_v2
        where id=p_photo_run_id
      )
    );
    return v_audit;
  end if;

  select * into v_task
  from public.cleaning_tasks_v2
  where id=p_cleaning_task_id
  for update;

  if not found then
    raise exception 'cleaning_task_not_found' using errcode='P0002';
  end if;

  select * into v_run
  from public.photo_verification_runs_v2
  where id=p_photo_run_id;

  if not found then
    raise exception 'photo_run_not_found' using errcode='P0002';
  end if;

  if v_run.cleaning_task_id is distinct from v_task.id
    or v_run.organization_id<>v_task.organization_id
    or v_run.property_id<>v_task.property_id then
    raise exception 'cleaning_photo_scope_mismatch' using errcode='23514';
  end if;

  if v_run.status not in ('submitted','manual_review','ai_review','approved','rejected') then
    raise exception 'photo_run_not_submitted' using errcode='55000';
  end if;

  select exists(
    select 1
    from public.cleaning_photo_requests_v2 r
    where r.cleaning_task_id=v_task.id
      and r.request_kind='cleaning'
  )
  into v_has_requests;

  if v_has_requests and exists(
    select 1
    from public.cleaning_photo_requests_v2 r
    where r.cleaning_task_id=v_task.id
      and r.request_kind='cleaning'
      and r.completed_run_id is null
  ) then
    return null;
  end if;

  select * into v_policy
  from public.cleaning_audit_policies_v2
  where organization_id=v_task.organization_id;

  if not found then
    v_policy.organization_id:=v_task.organization_id;
    v_policy.enabled:=true;
    v_policy.human_review_probability:=0.2000;
    v_policy.review_window_minutes:=1440;
  end if;

  v_selected:=v_policy.enabled
    and p_random_value<v_policy.human_review_probability;

  insert into public.cleaning_audits_v2(
    organization_id,property_id,cleaning_task_id,photo_run_id,
    selected_for_review,selection_probability,selected_at,review_deadline,status
  ) values (
    v_task.organization_id,v_task.property_id,v_task.id,v_run.id,
    v_selected,v_policy.human_review_probability,
    case when v_selected then p_now else null end,
    case when v_selected then p_now+make_interval(mins=>v_policy.review_window_minutes) else null end,
    case when v_selected then 'open' else 'not_selected' end
  )
  on conflict (cleaning_task_id) do nothing
  returning * into v_audit;

  if v_audit.id is null then
    select * into v_audit
    from public.cleaning_audits_v2
    where cleaning_task_id=p_cleaning_task_id;

    perform private.workflow_sync_cleaning_audit_selection_v1(
      p_cleaning_task_id,
      v_run.actor_user_id
    );
    return v_audit;
  end if;

  if v_selected then
    if v_has_requests then
      insert into public.cleaning_audit_items_v2(audit_id,photo_item_id)
      select v_audit.id,i.id
      from public.cleaning_photo_requests_v2 r
      join public.photo_verification_items_v2 i
        on i.run_id=r.completed_run_id
      where r.cleaning_task_id=v_task.id
        and r.request_kind='cleaning'
        and r.completed_run_id is not null
      on conflict (audit_id,photo_item_id) do nothing;
    else
      insert into public.cleaning_audit_items_v2(audit_id,photo_item_id)
      select v_audit.id,i.id
      from public.photo_verification_items_v2 i
      where i.run_id=v_run.id
      on conflict (audit_id,photo_item_id) do nothing;
    end if;

    if not exists(
      select 1
      from public.cleaning_audit_items_v2
      where audit_id=v_audit.id
    ) then
      raise exception 'photo_run_has_no_items' using errcode='55000';
    end if;
  else
    update public.cleaning_audits_v2
    set report_status='ready',
        closed_at=p_now
    where id=v_audit.id
    returning * into v_audit;
  end if;

  perform private.workflow_sync_cleaning_audit_selection_v1(
    p_cleaning_task_id,
    v_run.actor_user_id
  );

  return v_audit;
end;
$workflow_cleaning_audit$;

revoke all on function private.select_cleaning_audit_v2(uuid,uuid,double precision,timestamptz)
  from public,anon,authenticated,service_role;

create or replace function public.apply_workflow_cleaning_photo_review_v1(
  p_run_id uuid,
  p_actor_user_id uuid,
  p_decision text,
  p_rejection_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $workflow_cleaning_photo_review$
declare
  v_run public.photo_verification_runs_v2;
  v_cleaning public.cleaning_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_audit public.cleaning_audits_v2;
  v_photo_item public.photo_verification_items_v2;
  v_audit_item public.cleaning_audit_items_v2;
  v_final jsonb;
begin
  if p_actor_user_id is null then
    raise exception 'workflow_review_actor_required' using errcode='22023';
  end if;

  if p_decision not in ('approved','rejected') then
    raise exception 'workflow_review_decision_invalid' using errcode='22023';
  end if;

  if p_decision='rejected'
    and nullif(btrim(p_rejection_reason),'') is null then
    raise exception 'workflow_review_rejection_reason_required' using errcode='22023';
  end if;

  select *
  into v_run
  from public.photo_verification_runs_v2
  where id=p_run_id
  for update;

  if v_run.id is null
    or v_run.purpose<>'cleaning'
    or v_run.cleaning_task_id is null
    or v_run.source_type<>'cleaning_task'
    or v_run.source_id is distinct from v_run.cleaning_task_id then
    raise exception 'workflow_cleaning_review_run_not_found' using errcode='P0002';
  end if;

  select *
  into v_cleaning
  from public.cleaning_tasks_v2
  where id=v_run.cleaning_task_id
  for update;

  if v_cleaning.id is null
    or v_cleaning.workflow_execution_id is null then
    raise exception 'workflow_cleaning_review_not_linked' using errcode='0A000';
  end if;

  select *
  into v_execution
  from public.workflow_executions_v2
  where id=v_cleaning.workflow_execution_id
  for update;

  select *
  into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id
  for update;

  if v_execution.id is null
    or v_task.id is null
    or v_execution.organization_id<>v_cleaning.organization_id
    or v_run.organization_id<>v_cleaning.organization_id
    or v_run.property_id<>v_cleaning.property_id
    or v_task.organization_id<>v_execution.organization_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id
    or v_cleaning.assigned_user_id is distinct from v_execution.assigned_user_id then
    raise exception 'workflow_cleaning_audit_identity_mismatch' using errcode='55000';
  end if;

  if not exists(
    select 1
    from public.user_roles ur
    where ur.user_id=p_actor_user_id
      and ur.revoked_at is null
      and (
        ur.role='root'
        or (
          ur.role='admin'
          and ur.organization_id=v_execution.organization_id
        )
      )
  ) then
    raise exception 'workflow_review_actor_forbidden' using errcode='42501';
  end if;

  select *
  into v_audit
  from public.cleaning_audits_v2
  where cleaning_task_id=v_cleaning.id
  for update;

  if v_audit.id is null
    or not v_audit.selected_for_review then
    raise exception 'workflow_cleaning_audit_not_reviewable' using errcode='55000';
  end if;

  select *
  into v_photo_item
  from public.photo_verification_items_v2
  where run_id=v_run.id
  order by id
  limit 1;

  if v_photo_item.id is null
    or exists(
      select 1
      from public.photo_verification_items_v2 i
      where i.run_id=v_run.id
        and i.id<>v_photo_item.id
    ) then
    raise exception 'workflow_cleaning_review_item_invalid' using errcode='55000';
  end if;

  select *
  into v_audit_item
  from public.cleaning_audit_items_v2
  where audit_id=v_audit.id
    and photo_item_id=v_photo_item.id
  for update;

  if v_audit_item.id is null then
    raise exception 'workflow_cleaning_review_item_missing' using errcode='55000';
  end if;

  if v_execution.status in ('completed','rejected') then
    if v_task.status is distinct from v_execution.status
      or v_audit_item.result<>p_decision
      or v_run.status<>p_decision then
      raise exception 'workflow_cleaning_review_conflict' using errcode='55000';
    end if;

    return jsonb_build_object(
      'ok',true,
      'applied_new',false,
      'run_status',v_run.status,
      'audit_status',v_audit.status,
      'cleaning_status',v_cleaning.status,
      'task_status',v_task.status,
      'execution_status',v_execution.status
    );
  end if;

  if v_execution.status<>'waiting_review'
    or v_task.status<>'waiting_review'
    or v_cleaning.status<>'submitted'
    or v_audit.status<>'open'
    or v_audit.review_deadline<=now() then
    raise exception 'workflow_cleaning_review_state_conflict' using errcode='55000';
  end if;

  if v_audit_item.result<>'pending' then
    if v_audit_item.result=p_decision
      and v_run.status=p_decision then
      return jsonb_build_object(
        'ok',true,
        'applied_new',false,
        'run_status',v_run.status,
        'audit_status',v_audit.status,
        'cleaning_status',v_cleaning.status,
        'task_status',v_task.status,
        'execution_status',v_execution.status
      );
    end if;

    raise exception 'workflow_cleaning_review_conflict' using errcode='55000';
  end if;

  perform public.apply_photo_verification_review_v2(
    v_run.id,
    p_actor_user_id,
    p_decision,
    case when p_decision='rejected' then p_rejection_reason else null end
  );

  perform private.apply_cleaning_audit_item_review_v2(
    v_audit.id,
    v_photo_item.id,
    p_actor_user_id,
    p_decision,
    case when p_decision='rejected' then p_rejection_reason else null end,
    now()
  );

  select *
  into v_audit
  from public.cleaning_audits_v2
  where id=v_audit.id;

  if v_audit.status='closed' then
    v_final:=private.workflow_finalize_cleaning_audit_v1(
      v_audit.id,
      p_actor_user_id,
      'human_review'
    );
  end if;

  select *
  into v_cleaning
  from public.cleaning_tasks_v2
  where id=v_cleaning.id;

  select *
  into v_execution
  from public.workflow_executions_v2
  where id=v_execution.id;

  select *
  into v_task
  from public.tenant_tasks_v2
  where id=v_task.id;

  return jsonb_build_object(
    'ok',true,
    'applied_new',true,
    'run_status',p_decision,
    'audit_status',v_audit.status,
    'cleaning_status',v_cleaning.status,
    'task_status',v_task.status,
    'execution_status',v_execution.status,
    'all_reviewed',v_audit.status='closed'
  );
end;
$workflow_cleaning_photo_review$;

revoke all on function public.apply_workflow_cleaning_photo_review_v1(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.apply_workflow_cleaning_photo_review_v1(uuid,uuid,text,text)
  to service_role;

create or replace function private.close_expired_cleaning_audits_v2(
  p_now timestamptz default now()
)
returns table(audit_id uuid, expired_items integer)
language plpgsql
security definer
set search_path=''
as $workflow_cleaning_audit_expiry$
declare
  v_audit_id uuid;
  v_expired integer;
begin
  for v_audit_id in
    select a.id
    from public.cleaning_audits_v2 a
    where a.selected_for_review
      and a.status='open'
      and a.review_deadline<=p_now
    order by a.review_deadline,a.id
    for update skip locked
  loop
    update public.cleaning_audit_items_v2
    set result='review_expired'
    where audit_id=v_audit_id
      and result='pending';

    get diagnostics v_expired=row_count;

    update public.cleaning_audits_v2
    set status='expired',
        closed_at=coalesce(closed_at,p_now),
        report_status=case
          when report_status='pending' then 'ready'
          else report_status
        end
    where id=v_audit_id;

    perform private.workflow_finalize_cleaning_audit_v1(
      v_audit_id,
      null,
      'review_window_expired'
    );

    audit_id:=v_audit_id;
    expired_items:=v_expired;
    return next;
  end loop;
end;
$workflow_cleaning_audit_expiry$;

revoke all on function private.close_expired_cleaning_audits_v2(timestamptz)
  from public,anon,authenticated,service_role;

-- Un expediente no seleccionado también es un expediente final: su informe
-- agregado debe salir por el mismo canal y con la misma idempotencia.
create or replace function private.queue_ready_cleaning_audit_reports_v2(
  p_now timestamptz default now()
)
returns table(audit_id uuid, notification_id uuid)
language plpgsql
security definer
set search_path=public,private,pg_temp
as $workflow_cleaning_audit_report$
begin
  return query
  with ready as (
    select
      a.id,
      a.organization_id,
      a.property_id,
      t.assigned_user_id as recipient_user_id,
      count(i.id) filter (where i.result='approved')::int as approved_count,
      count(i.id) filter (where i.result='rejected')::int as rejected_count,
      count(i.id) filter (where i.result='review_expired')::int as expired_count
    from public.cleaning_audits_v2 a
    join public.cleaning_tasks_v2 t on t.id=a.cleaning_task_id
    left join public.cleaning_audit_items_v2 i on i.audit_id=a.id
    where a.report_status='ready'
      and a.status in ('not_selected','closed','expired')
      and t.assigned_user_id is not null
    group by a.id,a.organization_id,a.property_id,t.assigned_user_id
    for update of a skip locked
  ),
  ins as (
    insert into public.notifications_v2(
      organization_id,recipient_user_id,event_type,title,body,
      channel_in_app,channel_email,status
    )
    select
      r.organization_id,
      r.recipient_user_id,
      'cleaning_audit_report:'||r.id::text,
      'Informe de limpieza',
      case
        when r.rejected_count > 0 then
          'Revisión finalizada. '||r.rejected_count||' foto(s) requieren atención.'
        when r.approved_count > 0 and r.expired_count = 0 then
          'Revisión finalizada. La limpieza revisada ha sido aprobada.'
        when r.expired_count > 0 then
          'Revisión finalizada. No fue necesario revisar todas las fotos dentro del plazo.'
        else
          'La limpieza ha quedado registrada correctamente.'
      end,
      true,false,'pending'
    from ready r
    on conflict do nothing
    returning id,event_type
  ),
  marked as (
    update public.cleaning_audits_v2 a
    set report_status='sent',
        report_sent_at=p_now
    from ready r
    where a.id=r.id
      and (
        exists(
          select 1
          from ins x
          where x.event_type='cleaning_audit_report:'||a.id::text
        )
        or exists(
          select 1
          from public.notifications_v2 n
          where n.event_type='cleaning_audit_report:'||a.id::text
        )
      )
    returning a.id
  )
  select m.id,n.id
  from marked m
  join public.notifications_v2 n
    on n.event_type='cleaning_audit_report:'||m.id::text;
end;
$workflow_cleaning_audit_report$;

revoke all on function private.queue_ready_cleaning_audit_reports_v2(timestamptz)
  from public,anon,authenticated,service_role;

comment on function private.workflow_sync_cleaning_audit_selection_v1(uuid,uuid) is
  'Proyecta el sorteo de auditoría de Limpieza al workflow: waiting_review si se selecciona; cierre automático si no.';
comment on function private.workflow_finalize_cleaning_audit_v1(uuid,uuid,text) is
  'Cierra idempotentemente cleaning task + workflow execution + tenant task cuando la auditoría ya es final.';
comment on function public.apply_workflow_cleaning_photo_review_v1(uuid,uuid,text,text) is
  'Aplica una decisión por foto de una auditoría de Limpieza workflow y sincroniza el cierre cuando se revisa el último item.';
