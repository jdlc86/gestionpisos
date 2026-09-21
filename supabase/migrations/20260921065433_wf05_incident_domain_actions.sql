-- WF-05 · transiciones del expediente de incidencia sobre la tarjeta y la
-- ejecución transversales. No se introduce un segundo motor de tareas.

alter table public.workflow_executions_v2
  drop constraint workflow_executions_v2_status_check;
alter table public.workflow_executions_v2
  add constraint workflow_executions_v2_status_check
  check (status in (
    'pending','active','waiting_info','waiting_review',
    'completed','cancelled','failed','rejected'
  ));

create unique index workflow_execution_events_v2_wf05_request_uq
  on public.workflow_execution_events_v2(
    execution_id,((details->>'request_key'))
  )
  where event_type='wf05_domain_action' and details ? 'request_key';

create function private.workflow_wf05_require_privileged_aal2_v1(
  p_organization_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if exists(
    select 1 from public.user_roles ur
    where ur.user_id=p_user_id
      and ur.revoked_at is null
      and (
        ur.role='root'
        or (ur.role='admin' and ur.organization_id=p_organization_id)
      )
  ) and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
    raise exception 'workflow_wf05_mfa_required' using errcode='42501';
  end if;
end;
$$;
revoke all on function private.workflow_wf05_require_privileged_aal2_v1(
  uuid,uuid
) from public,anon,authenticated,service_role;

create function private.workflow_wf05_seed_domain_actions_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_incident public.incidents_v2;
  v_event public.workflow_event_outbox_v2;
  v_task public.tenant_tasks_v2;
begin
  if new.source_event_id is null
    or old.source_event_id is not null
    or new.spec_snapshot->>'flowType'<>'maintenance'
    or new.spec_snapshot->>'eventType'<>'incident.created'
    or new.spec_snapshot->>'closeType'<>'domain_adapter' then
    return new;
  end if;

  select * into v_event
  from public.workflow_event_outbox_v2
  where id=new.source_event_id;
  select * into v_incident
  from public.incidents_v2
  where id=new.incident_id;
  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution' and source_id=new.id;

  if v_event.id is null
    or v_event.event_type<>'incident.created'
    or v_event.source_kind<>'incident'
    or v_event.source_id is distinct from v_incident.id
    or v_incident.status<>'reported'
    or v_incident.organization_id is distinct from new.organization_id
    or v_incident.property_id is distinct from new.property_id
    or (new.scope_type='room' and v_incident.room_id is distinct from new.room_id)
    or v_task.id is null
    or v_task.status<>'pending'
    or v_task.assigned_user_id is distinct from new.assigned_user_id then
    raise exception 'workflow_wf05_subject_not_current' using errcode='55000';
  end if;

  if not private.incident_internal_access_v1(
    new.organization_id,new.property_id,new.assigned_user_id,true
  ) then
    raise exception 'workflow_wf05_assignee_not_eligible' using errcode='42501';
  end if;

  insert into public.tenant_task_actions_v2(
    task_id,action_key,label,from_status,to_status,
    requires_note,sort_order,active,actor
  ) values
    (v_task.id,'accept','Aceptar gestión','pending','active',false,10,true,'assignee'),
    (v_task.id,'reject','Rechazar','pending','rejected',true,20,true,'assignee'),
    (v_task.id,'resolve','Resolver','active','completed',true,50,true,'assignee')
  on conflict(task_id,action_key,from_status)
  do update set
    label=excluded.label,
    to_status=excluded.to_status,
    requires_note=excluded.requires_note,
    sort_order=excluded.sort_order,
    active=excluded.active,
    actor=excluded.actor;

  if v_incident.opened_occupancy_id is not null then
    insert into public.tenant_task_actions_v2(
      task_id,action_key,label,from_status,to_status,
      requires_note,sort_order,active,actor
    ) values
      (v_task.id,'request_info','Solicitar información',
        'active','waiting_info',true,30,true,'assignee'),
      (v_task.id,'continue','Continuar gestión',
        'waiting_info','active',false,40,true,'assignee')
    on conflict(task_id,action_key,from_status)
    do update set
      label=excluded.label,
      to_status=excluded.to_status,
      requires_note=excluded.requires_note,
      sort_order=excluded.sort_order,
      active=excluded.active,
      actor=excluded.actor;
  end if;
  return new;
end;
$$;
revoke all on function private.workflow_wf05_seed_domain_actions_v1()
  from public,anon,authenticated,service_role;

create trigger workflow_wf05_seed_domain_actions_v1
after update of source_event_id on public.workflow_executions_v2
for each row
when (old.source_event_id is null and new.source_event_id is not null)
execute function private.workflow_wf05_seed_domain_actions_v1();

-- Usa clock_timestamp para ordenar inequívocamente petición y respuesta,
-- incluso en una regresión que ejecuta el ciclo completo en una transacción.
create or replace function public.submit_incident_information_v1(
  p_incident_id uuid,
  p_request_key text,
  p_body text
)
returns table(
  incident_id uuid,
  update_id uuid,
  incident_status text,
  applied_new boolean
)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_body text:=nullif(btrim(p_body),'');
  v_incident public.incidents_v2;
  v_update public.incident_updates_v2;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'incident_information_request_key_invalid' using errcode='22023';
  end if;
  if v_body is null or length(v_body)>5000 then
    raise exception 'incident_information_body_invalid' using errcode='22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_actor::text||':incident-information:'||p_incident_id::text||':'||v_key,0
    )
  );
  select * into v_incident
  from public.incidents_v2
  where id=p_incident_id
  for update;
  if v_incident.id is null then
    raise exception 'incident_not_found' using errcode='P0002';
  end if;
  if v_incident.created_by<>v_actor
    or not private.incident_tenant_access_v1(v_incident.id,v_actor) then
    raise exception 'incident_information_forbidden' using errcode='42501';
  end if;

  select iu.* into v_update
  from public.incident_updates_v2 iu
  where iu.incident_id=v_incident.id
    and iu.author_user_id=v_actor
    and iu.request_key=v_key;
  if v_update.id is not null then
    if v_update.update_kind<>'information_response'
      or v_update.body<>v_body then
      raise exception 'incident_information_request_key_conflict' using errcode='55000';
    end if;
    return query select v_incident.id,v_update.id,v_incident.status,false;
    return;
  end if;
  if v_incident.status<>'waiting_info' then
    raise exception 'incident_not_waiting_information' using errcode='55000';
  end if;

  insert into public.incident_updates_v2(
    incident_id,author_user_id,visibility,body,update_kind,request_key,created_at
  ) values (
    v_incident.id,v_actor,'tenant',v_body,'information_response',v_key,
    clock_timestamp()
  ) returning * into v_update;

  insert into public.notifications_v2(
    organization_id,recipient_user_id,event_type,title,body,status,
    channel_in_app,channel_email,source_kind,source_id,event_key
  )
  select
    v_incident.organization_id,e.assigned_user_id,
    'incident_information_received','Información recibida',
    'La persona inquilina ha respondido a la solicitud de información.',
    'pending',true,false,'incident',v_incident.id,
    'information_received:'||v_key
  from public.workflow_executions_v2 e
  where e.incident_id=v_incident.id
    and e.spec_snapshot->>'flowType'='maintenance'
    and e.spec_snapshot->>'closeType'='domain_adapter'
    and e.assigned_user_id is not null
  order by e.created_at desc
  limit 1
  on conflict (source_kind,source_id,event_key,recipient_user_id)
  where source_kind is not null and source_id is not null and event_key is not null
  do nothing;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_incident.organization_id,v_actor,'incident_information_submitted',
    'incident',v_incident.id::text,'success',
    jsonb_build_object('update_id',v_update.id,'request_key',v_key)
  );
  return query select v_incident.id,v_update.id,v_incident.status,true;
end;
$$;
revoke all on function public.submit_incident_information_v1(uuid,text,text)
  from public,anon;
grant execute on function public.submit_incident_information_v1(uuid,text,text)
  to authenticated,service_role;

create function private.apply_wf05_domain_action_v1(
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
  v_note text:=nullif(btrim(p_note),'');
  v_task public.tenant_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_event public.workflow_event_outbox_v2;
  v_incident public.incidents_v2;
  v_action public.tenant_task_actions_v2;
  v_previous public.workflow_execution_events_v2;
  v_from_status text;
  v_last_request_at timestamptz;
  v_resolved_event uuid;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_wf05_request_key_invalid' using errcode='22023';
  end if;
  if p_action_key not in ('accept','reject','request_info','continue','resolve')
    or p_action_key is null then
    raise exception 'workflow_wf05_action_not_supported' using errcode='22023';
  end if;
  if v_note is not null and length(v_note)>5000 then
    raise exception 'workflow_wf05_note_invalid' using errcode='22023';
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
  if v_execution.id is null
    or v_execution.spec_snapshot->>'flowType'<>'maintenance'
    or v_execution.spec_snapshot->>'eventType'<>'incident.created'
    or v_execution.spec_snapshot->>'closeType'<>'domain_adapter'
    or v_execution.source_event_id is null
    or v_execution.incident_id is null then
    raise exception 'workflow_wf05_domain_required' using errcode='22023';
  end if;

  perform private.workflow_require_current_actor_v1(v_execution.id);
  if not private.incident_internal_access_v1(
    v_execution.organization_id,v_execution.property_id,v_actor,true
  ) then
    raise exception 'workflow_wf05_assignee_not_eligible' using errcode='42501';
  end if;
  perform private.workflow_wf05_require_privileged_aal2_v1(
    v_execution.organization_id,v_actor
  );

  select * into v_event
  from public.workflow_event_outbox_v2
  where id=v_execution.source_event_id;
  select * into v_incident
  from public.incidents_v2
  where id=v_execution.incident_id
  for update;
  if v_event.id is null
    or v_event.event_type<>'incident.created'
    or v_event.source_kind<>'incident'
    or v_event.source_id is distinct from v_incident.id
    or v_event.organization_id is distinct from v_incident.organization_id
    or v_event.property_id is distinct from v_incident.property_id
    or v_event.room_id is distinct from v_incident.room_id
    or v_event.occupancy_id is distinct from v_incident.opened_occupancy_id
    or v_execution.organization_id is distinct from v_incident.organization_id
    or v_execution.property_id is distinct from v_incident.property_id
    or (v_execution.scope_type='room'
        and v_execution.room_id is distinct from v_incident.room_id)
    or v_task.organization_id is distinct from v_execution.organization_id
    or v_task.property_id is distinct from v_execution.property_id
    or v_task.room_id is distinct from v_execution.room_id
    or v_task.tenant_id is not null
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
    raise exception 'workflow_wf05_subject_not_current' using errcode='55000';
  end if;

  select * into v_previous
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='wf05_domain_action'
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
  if v_action.requires_note and v_note is null then
    raise exception 'workflow_action_note_required' using errcode='22023';
  end if;
  v_from_status:=v_task.status;

  if p_action_key='accept' then
    if v_incident.status<>'reported'
      or v_action.to_status<>'active' then
      raise exception 'workflow_wf05_transition_mismatch' using errcode='55000';
    end if;
    update public.incidents_v2
    set status='in_progress',assigned_to=v_actor,updated_at=clock_timestamp()
    where id=v_incident.id returning * into v_incident;
  elsif p_action_key='reject' then
    if v_incident.status<>'reported'
      or v_action.to_status<>'rejected' then
      raise exception 'workflow_wf05_transition_mismatch' using errcode='55000';
    end if;
    update public.incidents_v2
    set status='rejected',assigned_to=v_actor,rejection_reason=v_note,
        updated_at=clock_timestamp()
    where id=v_incident.id returning * into v_incident;
    insert into public.incident_updates_v2(
      incident_id,author_user_id,visibility,body,update_kind,request_key,created_at
    ) values (
      v_incident.id,v_actor,
      case when v_incident.opened_occupancy_id is null then 'internal' else 'tenant' end,
      v_note,'rejection',v_key,clock_timestamp()
    );
  elsif p_action_key='request_info' then
    if v_incident.status<>'in_progress'
      or v_action.to_status<>'waiting_info' then
      raise exception 'workflow_wf05_transition_mismatch' using errcode='55000';
    end if;
    update public.incidents_v2
    set status='waiting_info',updated_at=clock_timestamp()
    where id=v_incident.id returning * into v_incident;
    insert into public.incident_updates_v2(
      incident_id,author_user_id,visibility,body,update_kind,request_key,created_at
    ) values (
      v_incident.id,v_actor,
      case when v_incident.opened_occupancy_id is null then 'internal' else 'tenant' end,
      v_note,'request_info',v_key,clock_timestamp()
    );
  elsif p_action_key='continue' then
    if v_incident.status<>'waiting_info'
      or v_action.to_status<>'active' then
      raise exception 'workflow_wf05_transition_mismatch' using errcode='55000';
    end if;
    select max(iu.created_at) into v_last_request_at
    from public.incident_updates_v2 iu
    where iu.incident_id=v_incident.id and iu.update_kind='request_info';
    if v_last_request_at is null or not exists(
      select 1 from public.incident_updates_v2 iu
      where iu.incident_id=v_incident.id
        and iu.update_kind='information_response'
        and iu.created_at>v_last_request_at
    ) then
      raise exception 'workflow_wf05_information_response_required' using errcode='55000';
    end if;
    update public.incidents_v2
    set status='in_progress',updated_at=clock_timestamp()
    where id=v_incident.id returning * into v_incident;
  else
    if v_incident.status<>'in_progress'
      or v_action.to_status<>'completed' then
      raise exception 'workflow_wf05_transition_mismatch' using errcode='55000';
    end if;
    if coalesce((v_execution.spec_snapshot#>>'{steps,photo}')::boolean,false)
      and not (
        exists(select 1 from public.workflow_execution_photo_resources_v2 r
          where r.execution_id=v_execution.id)
        and not exists(select 1 from public.workflow_execution_photo_resources_v2 r
          where r.execution_id=v_execution.id and r.status<>'submitted')
      ) then
      raise exception 'workflow_wf05_photo_required' using errcode='55000';
    end if;
    if coalesce((v_execution.spec_snapshot#>>'{steps,checklist}')::boolean,false)
      and (
        jsonb_typeof(v_execution.checklist_state)<>'array'
        or jsonb_array_length(v_execution.checklist_state)=0
        or exists(
          select 1 from jsonb_array_elements(v_execution.checklist_state) item
          where coalesce((item->>'required')::boolean,true)
            and not coalesce((item->>'completed')::boolean,false)
        )
      ) then
      raise exception 'workflow_wf05_checklist_required' using errcode='55000';
    end if;
    if coalesce((v_execution.spec_snapshot#>>'{steps,document}')::boolean,false)
      and not exists(
        select 1 from public.workflow_execution_documents_v2 d
        where d.execution_id=v_execution.id and d.status='submitted'
      ) then
      raise exception 'workflow_wf05_document_required' using errcode='55000';
    end if;
    update public.incidents_v2
    set status='resolved',resolved_at=clock_timestamp(),updated_at=clock_timestamp()
    where id=v_incident.id returning * into v_incident;
    insert into public.incident_updates_v2(
      incident_id,author_user_id,visibility,body,update_kind,request_key,created_at
    ) values (
      v_incident.id,v_actor,
      case when v_incident.opened_occupancy_id is null then 'internal' else 'tenant' end,
      v_note,'resolution',v_key,clock_timestamp()
    );
  end if;

  update public.tenant_tasks_v2
  set status=v_action.to_status,updated_at=clock_timestamp()
  where id=v_task.id returning * into v_task;
  update public.workflow_executions_v2 e
  set status=v_action.to_status,
      updated_at=clock_timestamp(),
      started_at=case when p_action_key='accept'
        then coalesce(e.started_at,clock_timestamp()) else e.started_at end,
      completed_at=case when p_action_key='resolve'
        then coalesce(e.completed_at,clock_timestamp()) else e.completed_at end
  where id=v_execution.id returning * into v_execution;

  if p_action_key in ('request_info','reject','resolve') then
    insert into public.notifications_v2(
      organization_id,recipient_user_id,event_type,title,body,status,
      channel_in_app,channel_email,source_kind,source_id,event_key
    ) values (
      v_incident.organization_id,v_incident.created_by,
      case p_action_key
        when 'request_info' then 'incident_information_requested'
        when 'reject' then 'incident_rejected'
        else 'incident_resolved' end,
      case p_action_key
        when 'request_info' then 'Información necesaria'
        when 'reject' then 'Incidencia rechazada'
        else 'Incidencia resuelta' end,
      case p_action_key
        when 'request_info' then v_note
        when 'reject' then 'La incidencia se cerró como rechazada.'
        else 'La incidencia se ha resuelto.' end,
      'pending',true,false,'incident',v_incident.id,
      case p_action_key
        when 'request_info' then 'information_requested:'||v_key
        when 'reject' then 'rejected'
        else 'resolved' end
    )
    on conflict (source_kind,source_id,event_key,recipient_user_id)
    where source_kind is not null and source_id is not null and event_key is not null
    do nothing;
  end if;

  if p_action_key='resolve' then
    v_resolved_event:=private.workflow_enqueue_event_v1(
      v_incident.organization_id,'incident.resolved','incident',v_incident.id,
      'resolved',v_incident.property_id,v_incident.room_id,
      v_incident.opened_occupancy_id,
      jsonb_build_object(
        'incident_kind',v_incident.incident_kind,
        'management_execution_id',v_execution.id
      ),v_actor,clock_timestamp()
    );
  end if;

  insert into public.tenant_task_history_v2(
    task_id,action_key,action_label,from_status,to_status,note,actor_user_id
  ) values (
    v_task.id,v_action.action_key,v_action.label,v_from_status,
    v_action.to_status,v_note,v_actor
  );
  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,
    actor_user_id,details
  ) values (
    v_execution.id,v_execution.organization_id,'wf05_domain_action',
    v_from_status,v_execution.status,v_actor,
    jsonb_build_object(
      'task_id',v_task.id,'action_key',p_action_key,'request_key',v_key,
      'source_event_id',v_event.id,'incident_id',v_incident.id,
      'resolved_event_id',v_resolved_event
    )
  );
  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,v_actor,'workflow_wf05_action_applied',
    'workflow_execution',v_execution.id::text,'success',
    jsonb_build_object(
      'task_id',v_task.id,'incident_id',v_incident.id,
      'action_key',p_action_key,'request_key',v_key,
      'from_status',v_from_status,'to_status',v_execution.status,
      'resolved_event_id',v_resolved_event
    )
  );
  return query select v_task.id,v_task.status,v_execution.id,v_execution.status,true;
end;
$$;
revoke all on function private.apply_wf05_domain_action_v1(uuid,text,text,text)
  from public,anon,authenticated,service_role;

-- Conserva la firma pública. WF-04 y los workflows genéricos mantienen sus
-- adaptadores actuales; solo el snapshot opt-in de mantenimiento usa WF-05.
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
    if v_spec->>'flowType'='maintenance'
      and v_spec->>'eventType'='incident.created'
      and v_spec->>'closeType'='domain_adapter' then
      return query select * from private.apply_wf05_domain_action_v1(
        p_task_id,p_action_key,p_request_key,p_note
      );
      return;
    end if;
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

comment on function private.apply_wf05_domain_action_v1(uuid,text,text,text) is
  'Aplica aceptar, solicitar información, continuar, resolver o rechazar al expediente y a la misma tarea/ejecución WF-05, con revalidación e idempotencia.';
comment on function public.submit_incident_information_v1(uuid,text,text) is
  'Registra una respuesta idempotente del inquilino mientras el mismo expediente WF-05 espera información y notifica al asignado actual.';
