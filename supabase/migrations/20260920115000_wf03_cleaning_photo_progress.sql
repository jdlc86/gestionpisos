-- GestionPisos · WF-03 · progreso fotográfico de Limpieza
-- El envío de cada run completa exactamente una solicitud congelada.
-- La auditoría solo se decide cuando todas las fotos solicitadas están completas.

-- El modelo legacy imponía un único run por cleaning_task_id, incompatible
-- con el checklist actual (un run por foto). La identidad idempotente vive en
-- cleaning_photo_requests_v2, no en el sobre de run.
drop index if exists public.photo_verification_runs_cleaning_task_uidx;

create index if not exists photo_verification_runs_cleaning_task_idx
  on public.photo_verification_runs_v2(cleaning_task_id)
  where cleaning_task_id is not null;

create or replace function private.workflow_capture_cleaning_photo_submission_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $workflow_cleaning_photo_submission$
declare
  v_task public.cleaning_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_generic_task public.tenant_tasks_v2;
  v_request public.cleaning_photo_requests_v2;
  v_item_id uuid;
  v_pattern_id uuid;
  v_all_complete boolean;
  v_from_status text;
  v_target_status text;
  v_submitted_at timestamptz:=coalesce(new.submitted_at,now());
begin
  if new.purpose<>'cleaning'
    or new.status<>'submitted'
    or old.status='submitted' then
    return new;
  end if;

  if new.cleaning_task_id is null then
    raise exception 'cleaning_task_link_missing' using errcode='55000';
  end if;

  select *
  into v_task
  from public.cleaning_tasks_v2
  where id=new.cleaning_task_id
  for update;

  if v_task.id is null then
    raise exception 'cleaning_task_not_found' using errcode='P0002';
  end if;

  if new.organization_id<>v_task.organization_id
    or new.property_id<>v_task.property_id
    or new.actor_user_id is distinct from v_task.assigned_user_id
    or new.source_type<>'cleaning_task'
    or new.source_id is distinct from v_task.id then
    raise exception 'cleaning_photo_identity_mismatch' using errcode='55000';
  end if;

  select i.id,i.pattern_id
  into v_item_id,v_pattern_id
  from public.photo_verification_items_v2 i
  where i.run_id=new.id
  order by i.id
  limit 1;

  if v_item_id is null then
    raise exception 'cleaning_photo_run_has_no_item' using errcode='55000';
  end if;

  if exists(
    select 1
    from public.photo_verification_items_v2 i
    where i.run_id=new.id
      and i.id<>v_item_id
  ) then
    raise exception 'cleaning_photo_run_item_count_invalid' using errcode='55000';
  end if;

  select *
  into v_request
  from public.cleaning_photo_requests_v2 r
  where r.cleaning_task_id=v_task.id
    and r.pattern_id=v_pattern_id
    and r.request_kind='cleaning'
  for update;

  if v_request.id is null then
    raise exception 'cleaning_photo_request_not_found' using errcode='55000';
  end if;

  if v_request.completed_run_id is not null
    and v_request.completed_run_id is distinct from new.id then
    raise exception 'cleaning_photo_request_already_completed' using errcode='55000';
  end if;

  if v_task.workflow_execution_id is not null then
    select *
    into v_execution
    from public.workflow_executions_v2
    where id=v_task.workflow_execution_id
    for update;

    if v_execution.id is null
      or v_execution.status<>'active'
      or v_execution.assigned_user_id is distinct from v_task.assigned_user_id
      or v_execution.organization_id<>v_task.organization_id
      or v_execution.property_id is distinct from v_task.property_id then
      raise exception 'workflow_cleaning_accept_required' using errcode='55000';
    end if;

    select *
    into v_generic_task
    from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=v_execution.id
    for update;

    if v_generic_task.id is null
      or v_generic_task.status<>'active'
      or v_generic_task.assigned_user_id is distinct from v_execution.assigned_user_id then
      raise exception 'workflow_cleaning_task_state_mismatch' using errcode='55000';
    end if;

    if v_task.status not in ('accepted','in_progress') then
      raise exception 'workflow_cleaning_domain_state_mismatch' using errcode='55000';
    end if;
  elsif v_task.status not in ('pending','accepted','in_progress') then
    raise exception 'cleaning_task_not_photo_actionable' using errcode='55000';
  end if;

  if v_request.completed_run_id is null then
    update public.cleaning_photo_requests_v2
    set completed_run_id=new.id,
        completed_at=v_submitted_at
    where id=v_request.id;
  end if;

  select not exists(
    select 1
    from public.cleaning_photo_requests_v2 r
    where r.cleaning_task_id=v_task.id
      and r.request_kind='cleaning'
      and r.completed_run_id is null
  )
  into v_all_complete;

  v_from_status:=v_task.status;
  v_target_status:=case
    when v_all_complete then 'submitted'
    else 'in_progress'
  end;

  if v_from_status is distinct from v_target_status then
    update public.cleaning_tasks_v2
    set status=v_target_status,
        submitted_at=case
          when v_target_status='submitted' then coalesce(submitted_at,v_submitted_at)
          else submitted_at
        end,
        updated_at=now()
    where id=v_task.id;

    if v_task.workflow_execution_id is not null then
      insert into public.workflow_execution_events_v2(
        execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
      ) values (
        v_execution.id,
        v_execution.organization_id,
        'domain_adapter_state_changed',
        v_execution.status,
        v_execution.status,
        new.actor_user_id,
        jsonb_build_object(
          'adapter','cleaning',
          'cleaning_task_id',v_task.id,
          'domain_from_status',v_from_status,
          'domain_to_status',v_target_status,
          'photo_run_id',new.id,
          'photo_request_id',v_request.id,
          'all_photos_complete',v_all_complete
        )
      );
    end if;

    insert into public.audit_log_v2(
      organization_id,actor_user_id,action,entity_type,entity_id,result,details
    ) values (
      v_task.organization_id,
      new.actor_user_id,
      'cleaning_photo_progressed',
      'cleaning_task',
      v_task.id::text,
      'success',
      jsonb_build_object(
        'workflow_execution_id',v_task.workflow_execution_id,
        'photo_run_id',new.id,
        'photo_request_id',v_request.id,
        'from_status',v_from_status,
        'to_status',v_target_status,
        'all_photos_complete',v_all_complete
      )
    );
  end if;

  return new;
end;
$workflow_cleaning_photo_submission$;

revoke all on function private.workflow_capture_cleaning_photo_submission_v1()
  from public,anon,authenticated,service_role;

drop trigger if exists workflow_cleaning_photo_submission_v1
  on public.photo_verification_runs_v2;

create trigger workflow_cleaning_photo_submission_v1
after update of status on public.photo_verification_runs_v2
for each row
execute function private.workflow_capture_cleaning_photo_submission_v1();

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

  -- Idempotencia: una limpieza solo sortea auditoría una vez.
  select * into v_audit
  from public.cleaning_audits_v2
  where cleaning_task_id=p_cleaning_task_id;

  if found then
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

  -- No sortear auditoría con una foto parcial. El Edge actual puede llamar a
  -- esta función tras cada run; devolver NULL mantiene compatibilidad.
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
      -- Compatibilidad con expedientes legacy sin checklist congelado.
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

  return v_audit;
end;
$workflow_cleaning_audit$;

revoke all on function private.select_cleaning_audit_v2(uuid,uuid,double precision,timestamptz)
  from public,anon,authenticated,service_role;

comment on function private.workflow_capture_cleaning_photo_submission_v1() is
  'Completa una solicitud fotográfica de limpieza al enviarse su run y proyecta accepted/in_progress/submitted sin cerrar todavía el workflow.';
comment on function private.select_cleaning_audit_v2(uuid,uuid,double precision,timestamptz) is
  'Sortea auditoría solo tras completar todas las fotos congeladas y agrega los items de todos sus runs.';
