-- GestionPisos · Photo review read authorization + partial retry idempotency
-- Follow-up to workflow human review. Keeps author reads intact while replacing
-- privileged photo-verification reads based on mutable JWT app_metadata with
-- active user_roles + AAL2.

create or replace function public.photo_verification_can_review_v1(
  p_organization_id_text text
)
returns boolean
language sql
stable
security definer
set search_path=public,pg_temp
as $photo_review_can_read$
  select auth.uid() is not null
    and coalesce(auth.jwt()->>'aal','aal1')='aal2'
    and exists(
      select 1
      from public.user_roles ur
      where ur.user_id=auth.uid()
        and ur.revoked_at is null
        and (
          ur.role='root'
          or (
            ur.role='admin'
            and ur.organization_id::text=p_organization_id_text
          )
        )
    );
$photo_review_can_read$;

revoke all on function public.photo_verification_can_review_v1(text)
  from public,anon;
grant execute on function public.photo_verification_can_review_v1(text)
  to authenticated,service_role;

-- RLS only participates after table privileges allow SELECT. Production already
-- has these grants; declaring them here makes the migration reproducible.
grant select on public.photo_verification_runs_v2 to authenticated;
grant select on public.photo_verification_items_v2 to authenticated;
grant select on storage.objects to authenticated;

drop policy if exists photo_runs_actor_read
  on public.photo_verification_runs_v2;

create policy photo_runs_actor_read
on public.photo_verification_runs_v2
for select
to authenticated
using (
  actor_user_id=auth.uid()
  or public.photo_verification_can_review_v1(organization_id::text)
);

drop policy if exists photo_items_actor_read
  on public.photo_verification_items_v2;

create policy photo_items_actor_read
on public.photo_verification_items_v2
for select
to authenticated
using (
  exists(
    select 1
    from public.photo_verification_runs_v2 r
    where r.id=photo_verification_items_v2.run_id
      and (
        r.actor_user_id=auth.uid()
        or public.photo_verification_can_review_v1(r.organization_id::text)
      )
  )
);

drop policy if exists photo_verification_storage_read
  on storage.objects;

create policy photo_verification_storage_read
on storage.objects
for select
to authenticated
using (
  bucket_id='photo-verification'
  and (
    owner_id=auth.uid()::text
    or public.photo_verification_can_review_v1(split_part(name,'/',1))
  )
);

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
  v_run_applied_new boolean:=false;
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
    v_run_applied_new:=true;
  elsif v_run.status=p_decision then
    v_run_applied_new:=false;
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
      'applied_new',v_run_applied_new,
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

comment on function public.photo_verification_can_review_v1(text) is
  'Authorizes privileged photo-verification reads from active ROOT/ADMIN user_roles and requires AAL2; avoids trusting app_metadata role claims.';
comment on function public.apply_workflow_photo_review_v1(uuid,uuid,text,text) is
  'Synchronizes workflow human review with photo verification and reports applied_new=false for a same-decision partial retry that changes no state.';
