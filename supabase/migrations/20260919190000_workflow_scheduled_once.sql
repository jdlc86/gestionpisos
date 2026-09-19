-- GestionPisos · Flujos de Trabajo · Fecha concreta automática
-- Primer disparador automático del motor transversal.
--
-- Diseño:
--   * una programación operativa por aplicación/version;
--   * zona horaria explícita capturada al publicar;
--   * asignado persistido solo para assignmentType=manual;
--   * property_responsible se resuelve de nuevo en el instante de ejecución;
--   * ejecución manual y programada reutilizan un único núcleo privado;
--   * pg_cron se configura en una migración separada para mantener regresiones locales portables.

create schema if not exists private;

alter table public.workflow_executions_v2
  drop constraint if exists workflow_executions_v2_trigger_kind_check;

alter table public.workflow_executions_v2
  add constraint workflow_executions_v2_trigger_kind_check
  check (trigger_kind in ('manual_now','scheduled_once'));

create table public.workflow_application_schedules_v2 (
  application_id uuid primary key
    references public.workflow_applications_v2(id) on delete cascade,
  definition_id uuid not null
    references public.workflow_definitions_v2(id) on delete restrict,
  definition_version_id uuid not null
    references public.workflow_definition_versions_v2(id) on delete restrict,
  organization_id uuid not null
    references public.organizations(id) on delete restrict,
  schedule_kind text not null
    check (schedule_kind in ('scheduled_once')),
  schedule_timezone text not null
    check (length(btrim(schedule_timezone)) between 1 and 80),
  next_run_at timestamptz not null,
  scheduled_assigned_user_id uuid references auth.users(id) on delete restrict,
  status text not null default 'active'
    check (status in ('active','completed','blocked','cancelled')),
  last_attempt_at timestamptz,
  last_execution_id uuid references public.workflow_executions_v2(id) on delete restrict,
  last_error_code text,
  last_error_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workflow_application_schedules_v2_identity_fkey
    foreign key (application_id,definition_id,definition_version_id,organization_id)
    references public.workflow_applications_v2(id,definition_id,definition_version_id,organization_id)
    on delete cascade,
  constraint workflow_application_schedules_v2_error_shape_check check (
    (status='blocked' and last_error_code is not null and last_error_at is not null)
    or status<>'blocked'
  )
);

create index workflow_application_schedules_v2_due_idx
  on public.workflow_application_schedules_v2(status,next_run_at)
  where status='active';

create index workflow_application_schedules_v2_org_idx
  on public.workflow_application_schedules_v2(organization_id,status,next_run_at);

create index workflow_application_schedules_v2_assignee_idx
  on public.workflow_application_schedules_v2(scheduled_assigned_user_id)
  where scheduled_assigned_user_id is not null;

alter table public.workflow_application_schedules_v2 enable row level security;

revoke all on public.workflow_application_schedules_v2 from anon;
revoke insert,update,delete,truncate,references,trigger
  on public.workflow_application_schedules_v2 from authenticated;
grant select on public.workflow_application_schedules_v2 to authenticated;

create policy workflow_application_schedules_v2_read_authorized
on public.workflow_application_schedules_v2
for select to authenticated
using (public.workflow_can_read_definitions_v1(organization_id));

create or replace function private.workflow_resolve_execution_assignee_v1(
  p_application_id uuid,
  p_requested_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $workflow_resolve_assignee$
declare
  v_org uuid;
  v_property_id uuid;
  v_spec jsonb;
  v_assignment_type text;
  v_assigned_user uuid;
begin
  select wa.organization_id,wa.property_id,wv.spec
  into v_org,v_property_id,v_spec
  from public.workflow_applications_v2 wa
  join public.workflow_definition_versions_v2 wv
    on wv.id=wa.definition_version_id
   and wv.definition_id=wa.definition_id
   and wv.organization_id=wa.organization_id
  where wa.id=p_application_id
    and wa.status='configured';

  if v_org is null then
    raise exception 'workflow_application_not_executable' using errcode='55000';
  end if;

  v_assignment_type:=nullif(v_spec->>'assignmentType','');

  if v_assignment_type='manual' then
    if p_requested_user_id is null then
      raise exception 'workflow_manual_assignee_required' using errcode='22023';
    end if;

    if exists(
      select 1
      from public.user_roles ur
      where ur.user_id=p_requested_user_id
        and ur.role='root'
        and ur.revoked_at is null
    ) then
      v_assigned_user:=p_requested_user_id;
    elsif exists(
      select 1
      from public.user_roles ur
      where ur.user_id=p_requested_user_id
        and ur.organization_id=v_org
        and ur.role='admin'
        and ur.revoked_at is null
    ) then
      v_assigned_user:=p_requested_user_id;
    elsif exists(
      select 1
      from public.user_roles ur
      where ur.user_id=p_requested_user_id
        and ur.organization_id=v_org
        and ur.role='employee'
        and ur.revoked_at is null
    ) and (
      v_property_id is null
      or exists(
        select 1
        from public.property_staff_access_v3 a
        where a.property_id=v_property_id
          and a.employee_user_id=p_requested_user_id
          and a.revoked_at is null
          and (a.valid_until is null or a.valid_until>now())
          and a.can_write=true
          and a.assignment_type in ('responsible','access')
      )
    ) then
      v_assigned_user:=p_requested_user_id;
    else
      raise exception 'workflow_manual_assignee_not_eligible' using errcode='42501';
    end if;

  elsif v_assignment_type='property_responsible' then
    if p_requested_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved' using errcode='22023';
    end if;

    if v_property_id is null then
      raise exception 'workflow_property_responsible_scope_required' using errcode='22023';
    end if;

    select a.employee_user_id
    into v_assigned_user
    from public.property_staff_access_v3 a
    join public.user_roles ur
      on ur.user_id=a.employee_user_id
     and ur.organization_id=v_org
     and ur.role in ('employee','admin')
     and ur.revoked_at is null
    where a.property_id=v_property_id
      and a.assignment_type='responsible'
      and a.revoked_at is null
      and (a.valid_until is null or a.valid_until>now())
      and a.can_write=true
    limit 1;

    if v_assigned_user is null then
      raise exception 'workflow_property_responsible_unavailable' using errcode='55000';
    end if;

  elsif v_assignment_type in ('fixed_person','role','active_occupants_rotation') then
    raise exception 'workflow_assignment_not_supported' using errcode='0A000';
  else
    raise exception 'workflow_assignment_invalid' using errcode='22023';
  end if;

  return v_assigned_user;
end;
$workflow_resolve_assignee$;

revoke all on function private.workflow_resolve_execution_assignee_v1(uuid,uuid)
  from public,anon,authenticated;

create or replace function private.workflow_execute_application_internal_v1(
  p_application_id uuid,
  p_idempotency_key text,
  p_assigned_user_id uuid,
  p_trigger_kind text,
  p_actor_user_id uuid
)
returns table(
  execution_id uuid,
  status text,
  assigned_user_id uuid,
  created_at timestamptz,
  created_new boolean
)
language plpgsql
security definer
set search_path=''
as $workflow_execute_internal$
declare
  v_definition_id uuid;
  v_version_id uuid;
  v_org uuid;
  v_scope_type text;
  v_property_id uuid;
  v_room_id uuid;
  v_occupancy_id uuid;
  v_application_status text;
  v_spec jsonb;
  v_assignment_type text;
  v_assigned_user uuid;
  v_execution_id uuid;
  v_execution_status text;
  v_execution_created_at timestamptz;
  v_key text:=nullif(btrim(p_idempotency_key),'');
begin
  if p_actor_user_id is null then
    raise exception 'workflow_execution_actor_required' using errcode='22023';
  end if;

  if p_trigger_kind not in ('manual_now','scheduled_once') then
    raise exception 'workflow_trigger_kind_invalid' using errcode='22023';
  end if;

  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_idempotency_key_invalid' using errcode='22023';
  end if;

  select
    wa.definition_id,
    wa.definition_version_id,
    wa.organization_id,
    wa.scope_type,
    wa.property_id,
    wa.room_id,
    wa.occupancy_id,
    wa.status,
    wv.spec
  into
    v_definition_id,
    v_version_id,
    v_org,
    v_scope_type,
    v_property_id,
    v_room_id,
    v_occupancy_id,
    v_application_status,
    v_spec
  from public.workflow_applications_v2 wa
  join public.workflow_definition_versions_v2 wv
    on wv.id=wa.definition_version_id
   and wv.definition_id=wa.definition_id
   and wv.organization_id=wa.organization_id
  where wa.id=p_application_id
  for update of wa;

  if v_definition_id is null then
    raise exception 'workflow_application_not_found' using errcode='P0002';
  end if;

  if v_application_status<>'configured' then
    raise exception 'workflow_application_not_executable' using errcode='55000';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_application_id::text||':execute:'||v_key,0)
  );

  select e.id,e.status,e.assigned_user_id,e.created_at
  into v_execution_id,v_execution_status,v_assigned_user,v_execution_created_at
  from public.workflow_executions_v2 e
  where e.application_id=p_application_id
    and e.idempotency_key=v_key;

  if v_execution_id is not null then
    perform public.workflow_require_photo_snapshot_internal_v1(v_execution_id);
    perform public.workflow_materialize_execution_task_internal_v1(v_execution_id,p_actor_user_id);
    return query
    select v_execution_id,v_execution_status,v_assigned_user,v_execution_created_at,false;
    return;
  end if;

  if v_scope_type='property' then
    if not exists(
      select 1
      from public.properties_v2 p
      where p.id=v_property_id
        and p.organization_id=v_org
        and p.archived_at is null
        and p.status<>'archived'
    ) then
      raise exception 'workflow_execution_property_unavailable' using errcode='55000';
    end if;
  elsif v_scope_type='room' then
    if not exists(
      select 1
      from public.rooms_v2 r
      join public.properties_v2 p on p.id=r.property_id
      where r.id=v_room_id
        and r.property_id=v_property_id
        and p.organization_id=v_org
        and p.archived_at is null
        and p.status<>'archived'
        and r.archived_at is null
        and r.status<>'archived'
    ) then
      raise exception 'workflow_execution_room_unavailable' using errcode='55000';
    end if;
  elsif v_scope_type='occupancy' then
    if not exists(
      select 1
      from public.occupancies_v2 o
      join public.properties_v2 p on p.id=o.property_id
      where o.id=v_occupancy_id
        and o.organization_id=v_org
        and o.property_id=v_property_id
        and p.organization_id=v_org
        and p.archived_at is null
        and p.status<>'archived'
        and o.status='active'
        and o.starts_on<=current_date
        and (o.ends_on is null or o.ends_on>=current_date)
    ) then
      raise exception 'workflow_execution_occupancy_unavailable' using errcode='55000';
    end if;
  elsif v_scope_type<>'organization' then
    raise exception 'workflow_scope_invalid' using errcode='22023';
  end if;

  v_assignment_type:=nullif(v_spec->>'assignmentType','');
  v_assigned_user:=private.workflow_resolve_execution_assignee_v1(
    p_application_id,p_assigned_user_id
  );

  insert into public.workflow_executions_v2 as new_execution(
    application_id,definition_id,definition_version_id,organization_id,
    scope_type,property_id,room_id,occupancy_id,
    trigger_kind,idempotency_key,assignment_type,assigned_user_id,
    status,spec_snapshot,created_by
  ) values (
    p_application_id,v_definition_id,v_version_id,v_org,
    v_scope_type,v_property_id,v_room_id,v_occupancy_id,
    p_trigger_kind,v_key,v_assignment_type,v_assigned_user,
    'pending',v_spec,p_actor_user_id
  )
  returning new_execution.id,new_execution.status,new_execution.created_at
  into v_execution_id,v_execution_status,v_execution_created_at;

  perform public.workflow_snapshot_photo_resources_internal_v1(v_execution_id);

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution_id,v_org,'created',null,'pending',p_actor_user_id,
    jsonb_build_object(
      'trigger_kind',p_trigger_kind,
      'assignment_type',v_assignment_type,
      'assigned_user_id',v_assigned_user,
      'application_id',p_application_id,
      'definition_version_id',v_version_id
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_org,p_actor_user_id,'workflow_execution_created','workflow_execution',
    v_execution_id::text,'success',
    jsonb_build_object(
      'application_id',p_application_id,
      'definition_id',v_definition_id,
      'definition_version_id',v_version_id,
      'scope_type',v_scope_type,
      'property_id',v_property_id,
      'room_id',v_room_id,
      'occupancy_id',v_occupancy_id,
      'trigger_kind',p_trigger_kind,
      'assignment_type',v_assignment_type,
      'assigned_user_id',v_assigned_user,
      'idempotency_key',v_key
    )
  );

  perform public.workflow_materialize_execution_task_internal_v1(
    v_execution_id,p_actor_user_id
  );

  return query
  select v_execution_id,v_execution_status,v_assigned_user,v_execution_created_at,true;
end;
$workflow_execute_internal$;

revoke all on function private.workflow_execute_application_internal_v1(
  uuid,text,uuid,text,uuid
) from public,anon,authenticated;

create or replace function public.execute_workflow_application_now_v1(
  p_application_id uuid,
  p_idempotency_key text,
  p_assigned_user_id uuid default null
)
returns table(
  execution_id uuid,
  status text,
  assigned_user_id uuid,
  created_at timestamptz,
  created_new boolean
)
language plpgsql
security definer
set search_path=''
as $workflow_execute_now$
declare
  v_actor uuid:=auth.uid();
  v_org uuid;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select wa.organization_id
  into v_org
  from public.workflow_applications_v2 wa
  where wa.id=p_application_id;

  if v_org is null then
    raise exception 'workflow_application_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_org) then
    raise exception 'workflow_execution_not_authorized' using errcode='42501';
  end if;

  return query
  select *
  from private.workflow_execute_application_internal_v1(
    p_application_id,
    p_idempotency_key,
    p_assigned_user_id,
    'manual_now',
    v_actor
  );
end;
$workflow_execute_now$;

revoke all on function public.execute_workflow_application_now_v1(uuid,text,uuid)
  from public,anon;
grant execute on function public.execute_workflow_application_now_v1(uuid,text,uuid)
  to authenticated;

create or replace function private.workflow_configure_application_schedule_v1(
  p_application_id uuid,
  p_scheduled_assigned_user_id uuid,
  p_actor_user_id uuid
)
returns public.workflow_application_schedules_v2
language plpgsql
security definer
set search_path=''
as $workflow_configure_schedule$
declare
  v_app public.workflow_applications_v2;
  v_spec jsonb;
  v_trigger_type text;
  v_assignment_type text;
  v_local_text text;
  v_run_at timestamptz;
  v_roundtrip_text text;
  v_timezone text;
  v_utc_text text;
  v_resolved uuid;
  v_schedule public.workflow_application_schedules_v2;
begin
  select wa,wv.spec
  into v_app,v_spec
  from public.workflow_applications_v2 wa
  join public.workflow_definition_versions_v2 wv
    on wv.id=wa.definition_version_id
   and wv.definition_id=wa.definition_id
   and wv.organization_id=wa.organization_id
  where wa.id=p_application_id
  for update of wa;

  if v_app.id is null then
    raise exception 'workflow_application_not_found' using errcode='P0002';
  end if;

  v_trigger_type:=nullif(v_spec->>'triggerType','');

  if v_trigger_type<>'scheduled_once' then
    delete from public.workflow_application_schedules_v2
    where application_id=p_application_id;
    return null;
  end if;

  if p_actor_user_id is null then
    raise exception 'workflow_schedule_actor_required' using errcode='22023';
  end if;

  v_timezone:=nullif(btrim(v_spec->>'scheduledTimezone'),'');
  if v_timezone is null
    or not exists(select 1 from pg_catalog.pg_timezone_names where name=v_timezone) then
    raise exception 'workflow_schedule_timezone_invalid' using errcode='22023';
  end if;

  v_local_text:=nullif(btrim(v_spec->>'scheduledAt'),'');
  if v_local_text is null
    or v_local_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}

  if v_run_at<=now() then
    raise exception 'workflow_schedule_must_be_future' using errcode='22023';
  end if;

  v_assignment_type:=nullif(v_spec->>'assignmentType','');

  if v_assignment_type='manual' then
    v_resolved:=private.workflow_resolve_execution_assignee_v1(
      p_application_id,p_scheduled_assigned_user_id
    );
  elsif v_assignment_type='property_responsible' then
    if p_scheduled_assigned_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved' using errcode='22023';
    end if;
    perform private.workflow_resolve_execution_assignee_v1(p_application_id,null);
  else
    raise exception 'workflow_schedule_assignment_not_supported' using errcode='0A000';
  end if;

  insert into public.workflow_application_schedules_v2(
    application_id,definition_id,definition_version_id,organization_id,
    schedule_kind,schedule_timezone,next_run_at,scheduled_assigned_user_id,
    status,last_attempt_at,last_execution_id,last_error_code,last_error_at,
    created_by,created_at,updated_at
  ) values (
    v_app.id,v_app.definition_id,v_app.definition_version_id,v_app.organization_id,
    'scheduled_once',v_timezone,v_run_at,
    case when v_assignment_type='manual' then v_resolved else null end,
    'active',null,null,null,null,
    p_actor_user_id,now(),now()
  )
  on conflict(application_id) do update
  set schedule_kind=excluded.schedule_kind,
      schedule_timezone=excluded.schedule_timezone,
      next_run_at=excluded.next_run_at,
      scheduled_assigned_user_id=excluded.scheduled_assigned_user_id,
      status='active',
      last_attempt_at=null,
      last_execution_id=null,
      last_error_code=null,
      last_error_at=null,
      updated_at=now()
  returning * into v_schedule;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_app.organization_id,p_actor_user_id,'workflow_schedule_configured',
    'workflow_application',v_app.id::text,'success',
    jsonb_build_object(
      'schedule_kind','scheduled_once',
      'timezone',v_timezone,
      'next_run_at',v_run_at,
      'scheduled_assigned_user_id',
        case when v_assignment_type='manual' then v_resolved else null end
    )
  );

  return v_schedule;
end;
$workflow_configure_schedule$;

revoke all on function private.workflow_configure_application_schedule_v1(
  uuid,uuid,uuid
) from public,anon,authenticated;

create or replace function private.workflow_application_schedule_status_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $workflow_schedule_app_status$
begin
  if old.status is distinct from new.status
    and new.status='archived' then
    update public.workflow_application_schedules_v2
    set status='cancelled',
        updated_at=now()
    where application_id=new.id
      and status in ('active','blocked');
  end if;
  return new;
end;
$workflow_schedule_app_status$;

revoke all on function private.workflow_application_schedule_status_v1()
  from public,anon,authenticated;

drop trigger if exists workflow_application_schedule_status_v1
  on public.workflow_applications_v2;

create trigger workflow_application_schedule_status_v1
after update of status
on public.workflow_applications_v2
for each row
execute function private.workflow_application_schedule_status_v1();

create or replace function private.process_due_workflow_schedules_v1(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path=''
as $workflow_process_schedules$
declare
  v_schedule public.workflow_application_schedules_v2;
  v_execution_id uuid;
  v_execution_status text;
  v_execution_assignee uuid;
  v_execution_created_at timestamptz;
  v_created_new boolean;
  v_key text;
  v_processed integer:=0;
begin
  for v_schedule in
    select s.*
    from public.workflow_application_schedules_v2 s
    join public.workflow_applications_v2 a on a.id=s.application_id
    join public.workflow_definitions_v2 d on d.id=s.definition_id
    where s.status='active'
      and s.schedule_kind='scheduled_once'
      and s.next_run_at<=p_now
      and a.status='configured'
      and d.status='published'
    order by s.next_run_at,s.application_id
    for update of s skip locked
  loop
    update public.workflow_application_schedules_v2
    set last_attempt_at=p_now,
        updated_at=now()
    where application_id=v_schedule.application_id;

    v_key:='scheduled-once:'||v_schedule.application_id::text||':'||
      extract(epoch from v_schedule.next_run_at)::bigint::text;

    begin
      select x.execution_id,x.status,x.assigned_user_id,x.created_at,x.created_new
      into v_execution_id,v_execution_status,v_execution_assignee,
           v_execution_created_at,v_created_new
      from private.workflow_execute_application_internal_v1(
        v_schedule.application_id,
        v_key,
        v_schedule.scheduled_assigned_user_id,
        'scheduled_once',
        v_schedule.created_by
      ) x
      limit 1;

      update public.workflow_application_schedules_v2
      set status='completed',
          last_execution_id=v_execution_id,
          last_error_code=null,
          last_error_at=null,
          updated_at=now()
      where application_id=v_schedule.application_id;

      v_processed:=v_processed+1;

    exception when others then
      update public.workflow_application_schedules_v2
      set status='blocked',
          last_error_code=sqlstate,
          last_error_at=now(),
          updated_at=now()
      where application_id=v_schedule.application_id;

      insert into public.notifications_v2(
        organization_id,recipient_user_id,event_type,title,body,
        status,channel_in_app,channel_email,
        source_kind,source_id,event_key
      ) values (
        v_schedule.organization_id,
        v_schedule.created_by,
        'workflow_schedule_blocked',
        'Programación bloqueada',
        'No se pudo crear la tarea programada. Revisa el flujo y su destino.',
        'pending',true,false,
        'workflow_schedule',v_schedule.application_id,'blocked'
      )
      on conflict(source_kind,source_id,event_key,recipient_user_id)
      where source_kind is not null
        and source_id is not null
        and event_key is not null
      do nothing;

      insert into public.audit_log_v2(
        organization_id,actor_user_id,action,entity_type,entity_id,result,details
      ) values (
        v_schedule.organization_id,v_schedule.created_by,
        'workflow_schedule_blocked','workflow_application',
        v_schedule.application_id::text,'failure',
        jsonb_build_object(
          'schedule_kind',v_schedule.schedule_kind,
          'next_run_at',v_schedule.next_run_at,
          'sqlstate',sqlstate
        )
      );
    end;
  end loop;

  return v_processed;
end;
$workflow_process_schedules$;

revoke all on function private.process_due_workflow_schedules_v1(timestamptz)
  from public,anon,authenticated;

create or replace function public.publish_workflow_ready_v2(
  p_spec jsonb,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_execute boolean default false,
  p_request_key text default null,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null,
  p_schedule_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  published_at timestamptz,
  schedule_next_run_at timestamptz,
  schedule_status text
)
language plpgsql
security definer
set search_path=''
as $workflow_ready_v2$
declare
  v_actor uuid:=auth.uid();
  v_result record;
  v_schedule public.workflow_application_schedules_v2;
begin
  if p_execute and coalesce(p_spec->>'triggerType','')='scheduled_once' then
    raise exception 'workflow_scheduled_execute_now_forbidden' using errcode='22023';
  end if;

  select * into v_result
  from public.publish_workflow_ready_v1(
    p_spec,p_property_id,p_room_id,p_occupancy_id,p_photo_pattern_ids,
    p_execute,p_request_key,p_idempotency_key,p_assigned_user_id
  )
  limit 1;

  v_schedule:=private.workflow_configure_application_schedule_v1(
    v_result.application_id,
    p_schedule_assigned_user_id,
    v_actor
  );

  return query select
    v_result.definition_id,v_result.version_id,v_result.version,
    v_result.application_id,v_result.execution_id,v_result.execution_status,
    v_result.assigned_user_id,v_result.published_at,
    v_schedule.next_run_at,v_schedule.status;
end;
$workflow_ready_v2$;

revoke all on function public.publish_workflow_ready_v2(
  jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid,uuid
) from public,anon;
grant execute on function public.publish_workflow_ready_v2(
  jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid,uuid
) to authenticated;

create or replace function public.update_unexecuted_workflow_v2(
  p_definition_id uuid,
  p_spec jsonb,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_expected_revision bigint default null,
  p_execute boolean default false,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null,
  p_schedule_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  revision bigint,
  schedule_next_run_at timestamptz,
  schedule_status text
)
language plpgsql
security definer
set search_path=''
as $workflow_update_v2$
declare
  v_actor uuid:=auth.uid();
  v_result record;
  v_schedule public.workflow_application_schedules_v2;
begin
  if p_execute and coalesce(p_spec->>'triggerType','')='scheduled_once' then
    raise exception 'workflow_scheduled_execute_now_forbidden' using errcode='22023';
  end if;

  select * into v_result
  from public.update_unexecuted_workflow_v1(
    p_definition_id,p_spec,p_property_id,p_room_id,p_occupancy_id,
    p_photo_pattern_ids,p_expected_revision,p_execute,p_idempotency_key,
    p_assigned_user_id
  )
  limit 1;

  v_schedule:=private.workflow_configure_application_schedule_v1(
    v_result.application_id,
    p_schedule_assigned_user_id,
    v_actor
  );

  return query select
    v_result.definition_id,v_result.version_id,v_result.version,
    v_result.application_id,v_result.execution_id,v_result.execution_status,
    v_result.assigned_user_id,v_result.revision,
    v_schedule.next_run_at,v_schedule.status;
end;
$workflow_update_v2$;

revoke all on function public.update_unexecuted_workflow_v2(
  uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid,uuid
) from public,anon;
grant execute on function public.update_unexecuted_workflow_v2(
  uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid,uuid
) to authenticated;

create or replace function public.publish_workflow_revision_ready_v2(
  p_definition_id uuid,
  p_expected_revision bigint,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_execute boolean default false,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null,
  p_schedule_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  published_at timestamptz,
  schedule_next_run_at timestamptz,
  schedule_status text
)
language plpgsql
security definer
set search_path=''
as $workflow_revision_ready_v2$
declare
  v_actor uuid:=auth.uid();
  v_result record;
  v_schedule public.workflow_application_schedules_v2;
  v_trigger_type text;
begin
  select rd.draft_spec->>'triggerType'
  into v_trigger_type
  from public.workflow_definition_revision_drafts_v2 rd
  where rd.definition_id=p_definition_id
    and rd.published_at is null;

  if p_execute and coalesce(v_trigger_type,'')='scheduled_once' then
    raise exception 'workflow_scheduled_execute_now_forbidden' using errcode='22023';
  end if;

  select * into v_result
  from public.publish_workflow_revision_ready_v1(
    p_definition_id,p_expected_revision,p_property_id,p_room_id,p_occupancy_id,
    p_photo_pattern_ids,p_execute,p_idempotency_key,p_assigned_user_id
  )
  limit 1;

  v_schedule:=private.workflow_configure_application_schedule_v1(
    v_result.application_id,
    p_schedule_assigned_user_id,
    v_actor
  );

  return query select
    v_result.definition_id,v_result.version_id,v_result.version,
    v_result.application_id,v_result.execution_id,v_result.execution_status,
    v_result.assigned_user_id,v_result.published_at,
    v_schedule.next_run_at,v_schedule.status;
end;
$workflow_revision_ready_v2$;

revoke all on function public.publish_workflow_revision_ready_v2(
  uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid,uuid
) from public,anon;
grant execute on function public.publish_workflow_revision_ready_v2(
  uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid,uuid
) to authenticated;

comment on table public.workflow_application_schedules_v2 is
  'Estado operativo de activaciones automáticas por aplicación/version. scheduled_once es el primer tipo habilitado.';
comment on function private.workflow_execute_application_internal_v1(uuid,text,uuid,text,uuid) is
  'Núcleo único de ejecución para manual_now y scheduled_once. No es invocable por clientes.';
comment on function private.process_due_workflow_schedules_v1(timestamptz) is
  'Procesa programaciones due con SKIP LOCKED, una ejecución idempotente por fecha y bloqueo explícito ante error.';
 then
    raise exception 'workflow_scheduled_at_invalid' using errcode='22023';
  end if;

  v_utc_text:=nullif(btrim(v_spec->>'scheduledAtUtc'),'');
  if v_utc_text is null
    or v_utc_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{3})?Z

  if v_run_at<=now() then
    raise exception 'workflow_schedule_must_be_future' using errcode='22023';
  end if;

  v_assignment_type:=nullif(v_spec->>'assignmentType','');

  if v_assignment_type='manual' then
    v_resolved:=private.workflow_resolve_execution_assignee_v1(
      p_application_id,p_scheduled_assigned_user_id
    );
  elsif v_assignment_type='property_responsible' then
    if p_scheduled_assigned_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved' using errcode='22023';
    end if;
    perform private.workflow_resolve_execution_assignee_v1(p_application_id,null);
  else
    raise exception 'workflow_schedule_assignment_not_supported' using errcode='0A000';
  end if;

  insert into public.workflow_application_schedules_v2(
    application_id,definition_id,definition_version_id,organization_id,
    schedule_kind,schedule_timezone,next_run_at,scheduled_assigned_user_id,
    status,last_attempt_at,last_execution_id,last_error_code,last_error_at,
    created_by,created_at,updated_at
  ) values (
    v_app.id,v_app.definition_id,v_app.definition_version_id,v_app.organization_id,
    'scheduled_once',v_timezone,v_run_at,
    case when v_assignment_type='manual' then v_resolved else null end,
    'active',null,null,null,null,
    p_actor_user_id,now(),now()
  )
  on conflict(application_id) do update
  set schedule_kind=excluded.schedule_kind,
      schedule_timezone=excluded.schedule_timezone,
      next_run_at=excluded.next_run_at,
      scheduled_assigned_user_id=excluded.scheduled_assigned_user_id,
      status='active',
      last_attempt_at=null,
      last_execution_id=null,
      last_error_code=null,
      last_error_at=null,
      updated_at=now()
  returning * into v_schedule;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_app.organization_id,p_actor_user_id,'workflow_schedule_configured',
    'workflow_application',v_app.id::text,'success',
    jsonb_build_object(
      'schedule_kind','scheduled_once',
      'timezone',v_timezone,
      'next_run_at',v_run_at,
      'scheduled_assigned_user_id',
        case when v_assignment_type='manual' then v_resolved else null end
    )
  );

  return v_schedule;
end;
$workflow_configure_schedule$;

revoke all on function private.workflow_configure_application_schedule_v1(
  uuid,text,uuid,uuid
) from public,anon,authenticated;

create or replace function private.workflow_application_schedule_status_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $workflow_schedule_app_status$
begin
  if old.status is distinct from new.status
    and new.status='archived' then
    update public.workflow_application_schedules_v2
    set status='cancelled',
        updated_at=now()
    where application_id=new.id
      and status in ('active','blocked');
  end if;
  return new;
end;
$workflow_schedule_app_status$;

revoke all on function private.workflow_application_schedule_status_v1()
  from public,anon,authenticated;

drop trigger if exists workflow_application_schedule_status_v1
  on public.workflow_applications_v2;

create trigger workflow_application_schedule_status_v1
after update of status
on public.workflow_applications_v2
for each row
execute function private.workflow_application_schedule_status_v1();

create or replace function private.process_due_workflow_schedules_v1(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path=''
as $workflow_process_schedules$
declare
  v_schedule public.workflow_application_schedules_v2;
  v_execution_id uuid;
  v_execution_status text;
  v_execution_assignee uuid;
  v_execution_created_at timestamptz;
  v_created_new boolean;
  v_key text;
  v_processed integer:=0;
begin
  for v_schedule in
    select s.*
    from public.workflow_application_schedules_v2 s
    join public.workflow_applications_v2 a on a.id=s.application_id
    join public.workflow_definitions_v2 d on d.id=s.definition_id
    where s.status='active'
      and s.schedule_kind='scheduled_once'
      and s.next_run_at<=p_now
      and a.status='configured'
      and d.status='published'
    order by s.next_run_at,s.application_id
    for update of s skip locked
  loop
    update public.workflow_application_schedules_v2
    set last_attempt_at=p_now,
        updated_at=now()
    where application_id=v_schedule.application_id;

    v_key:='scheduled-once:'||v_schedule.application_id::text||':'||
      extract(epoch from v_schedule.next_run_at)::bigint::text;

    begin
      select x.execution_id,x.status,x.assigned_user_id,x.created_at,x.created_new
      into v_execution_id,v_execution_status,v_execution_assignee,
           v_execution_created_at,v_created_new
      from private.workflow_execute_application_internal_v1(
        v_schedule.application_id,
        v_key,
        v_schedule.scheduled_assigned_user_id,
        'scheduled_once',
        v_schedule.created_by
      ) x
      limit 1;

      update public.workflow_application_schedules_v2
      set status='completed',
          last_execution_id=v_execution_id,
          last_error_code=null,
          last_error_at=null,
          updated_at=now()
      where application_id=v_schedule.application_id;

      v_processed:=v_processed+1;

    exception when others then
      update public.workflow_application_schedules_v2
      set status='blocked',
          last_error_code=left(sqlstate||':'||sqlerrm,240),
          last_error_at=now(),
          updated_at=now()
      where application_id=v_schedule.application_id;

      insert into public.notifications_v2(
        organization_id,recipient_user_id,event_type,title,body,
        status,channel_in_app,channel_email,
        source_kind,source_id,event_key
      ) values (
        v_schedule.organization_id,
        v_schedule.created_by,
        'workflow_schedule_blocked',
        'Programación bloqueada',
        'No se pudo crear la tarea programada. Revisa el flujo y su destino.',
        'pending',true,false,
        'workflow_schedule',v_schedule.application_id,'blocked'
      )
      on conflict(source_kind,source_id,event_key,recipient_user_id)
      where source_kind is not null
        and source_id is not null
        and event_key is not null
      do nothing;

      insert into public.audit_log_v2(
        organization_id,actor_user_id,action,entity_type,entity_id,result,details
      ) values (
        v_schedule.organization_id,v_schedule.created_by,
        'workflow_schedule_blocked','workflow_application',
        v_schedule.application_id::text,'failure',
        jsonb_build_object(
          'schedule_kind',v_schedule.schedule_kind,
          'next_run_at',v_schedule.next_run_at,
          'sqlstate',sqlstate
        )
      );
    end;
  end loop;

  return v_processed;
end;
$workflow_process_schedules$;

revoke all on function private.process_due_workflow_schedules_v1(timestamptz)
  from public,anon,authenticated;

create or replace function public.publish_workflow_ready_v2(
  p_spec jsonb,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_execute boolean default false,
  p_request_key text default null,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null,
  p_schedule_timezone text default null,
  p_schedule_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  published_at timestamptz,
  schedule_next_run_at timestamptz,
  schedule_status text
)
language plpgsql
security definer
set search_path=''
as $workflow_ready_v2$
declare
  v_actor uuid:=auth.uid();
  v_result record;
  v_schedule public.workflow_application_schedules_v2;
begin
  if p_execute and coalesce(p_spec->>'triggerType','')='scheduled_once' then
    raise exception 'workflow_scheduled_execute_now_forbidden' using errcode='22023';
  end if;

  select * into v_result
  from public.publish_workflow_ready_v1(
    p_spec,p_property_id,p_room_id,p_occupancy_id,p_photo_pattern_ids,
    p_execute,p_request_key,p_idempotency_key,p_assigned_user_id
  )
  limit 1;

  v_schedule:=private.workflow_configure_application_schedule_v1(
    v_result.application_id,
    p_schedule_assigned_user_id,
    v_actor
  );

  return query select
    v_result.definition_id,v_result.version_id,v_result.version,
    v_result.application_id,v_result.execution_id,v_result.execution_status,
    v_result.assigned_user_id,v_result.published_at,
    v_schedule.next_run_at,v_schedule.status;
end;
$workflow_ready_v2$;

revoke all on function public.publish_workflow_ready_v2(
  jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid,text,uuid
) from public,anon;
grant execute on function public.publish_workflow_ready_v2(
  jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid,text,uuid
) to authenticated;

create or replace function public.update_unexecuted_workflow_v2(
  p_definition_id uuid,
  p_spec jsonb,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_expected_revision bigint default null,
  p_execute boolean default false,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null,
  p_schedule_timezone text default null,
  p_schedule_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  revision bigint,
  schedule_next_run_at timestamptz,
  schedule_status text
)
language plpgsql
security definer
set search_path=''
as $workflow_update_v2$
declare
  v_actor uuid:=auth.uid();
  v_result record;
  v_schedule public.workflow_application_schedules_v2;
begin
  if p_execute and coalesce(p_spec->>'triggerType','')='scheduled_once' then
    raise exception 'workflow_scheduled_execute_now_forbidden' using errcode='22023';
  end if;

  select * into v_result
  from public.update_unexecuted_workflow_v1(
    p_definition_id,p_spec,p_property_id,p_room_id,p_occupancy_id,
    p_photo_pattern_ids,p_expected_revision,p_execute,p_idempotency_key,
    p_assigned_user_id
  )
  limit 1;

  v_schedule:=private.workflow_configure_application_schedule_v1(
    v_result.application_id,
    p_schedule_assigned_user_id,
    v_actor
  );

  return query select
    v_result.definition_id,v_result.version_id,v_result.version,
    v_result.application_id,v_result.execution_id,v_result.execution_status,
    v_result.assigned_user_id,v_result.revision,
    v_schedule.next_run_at,v_schedule.status;
end;
$workflow_update_v2$;

revoke all on function public.update_unexecuted_workflow_v2(
  uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid,text,uuid
) from public,anon;
grant execute on function public.update_unexecuted_workflow_v2(
  uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid,text,uuid
) to authenticated;

create or replace function public.publish_workflow_revision_ready_v2(
  p_definition_id uuid,
  p_expected_revision bigint,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_execute boolean default false,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null,
  p_schedule_timezone text default null,
  p_schedule_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  published_at timestamptz,
  schedule_next_run_at timestamptz,
  schedule_status text
)
language plpgsql
security definer
set search_path=''
as $workflow_revision_ready_v2$
declare
  v_actor uuid:=auth.uid();
  v_result record;
  v_schedule public.workflow_application_schedules_v2;
  v_trigger_type text;
begin
  select rd.draft_spec->>'triggerType'
  into v_trigger_type
  from public.workflow_definition_revision_drafts_v2 rd
  where rd.definition_id=p_definition_id
    and rd.published_at is null;

  if p_execute and coalesce(v_trigger_type,'')='scheduled_once' then
    raise exception 'workflow_scheduled_execute_now_forbidden' using errcode='22023';
  end if;

  select * into v_result
  from public.publish_workflow_revision_ready_v1(
    p_definition_id,p_expected_revision,p_property_id,p_room_id,p_occupancy_id,
    p_photo_pattern_ids,p_execute,p_idempotency_key,p_assigned_user_id
  )
  limit 1;

  v_schedule:=private.workflow_configure_application_schedule_v1(
    v_result.application_id,
    p_schedule_assigned_user_id,
    v_actor
  );

  return query select
    v_result.definition_id,v_result.version_id,v_result.version,
    v_result.application_id,v_result.execution_id,v_result.execution_status,
    v_result.assigned_user_id,v_result.published_at,
    v_schedule.next_run_at,v_schedule.status;
end;
$workflow_revision_ready_v2$;

revoke all on function public.publish_workflow_revision_ready_v2(
  uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid,text,uuid
) from public,anon;
grant execute on function public.publish_workflow_revision_ready_v2(
  uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid,text,uuid
) to authenticated;

comment on table public.workflow_application_schedules_v2 is
  'Estado operativo de activaciones automáticas por aplicación/version. scheduled_once es el primer tipo habilitado.';
comment on function private.workflow_execute_application_internal_v1(uuid,text,uuid,text,uuid) is
  'Núcleo único de ejecución para manual_now y scheduled_once. No es invocable por clientes.';
comment on function private.process_due_workflow_schedules_v1(timestamptz) is
  'Procesa programaciones due con SKIP LOCKED, una ejecución idempotente por fecha y bloqueo explícito ante error.';
 then
    raise exception 'workflow_scheduled_utc_invalid' using errcode='22023';
  end if;

  begin
    v_run_at:=v_utc_text::timestamptz;
  exception when others then
    raise exception 'workflow_scheduled_utc_invalid' using errcode='22023';
  end;

  v_roundtrip_text:=to_char(
    v_run_at at time zone v_timezone,
    'YYYY-MM-DD"T"HH24:MI'
  );

  if v_roundtrip_text is distinct from v_local_text then
    raise exception 'workflow_schedule_time_mismatch' using errcode='22023';
  end if;

  if v_run_at<=now() then
    raise exception 'workflow_schedule_must_be_future' using errcode='22023';
  end if;

  v_assignment_type:=nullif(v_spec->>'assignmentType','');

  if v_assignment_type='manual' then
    v_resolved:=private.workflow_resolve_execution_assignee_v1(
      p_application_id,p_scheduled_assigned_user_id
    );
  elsif v_assignment_type='property_responsible' then
    if p_scheduled_assigned_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved' using errcode='22023';
    end if;
    perform private.workflow_resolve_execution_assignee_v1(p_application_id,null);
  else
    raise exception 'workflow_schedule_assignment_not_supported' using errcode='0A000';
  end if;

  insert into public.workflow_application_schedules_v2(
    application_id,definition_id,definition_version_id,organization_id,
    schedule_kind,schedule_timezone,next_run_at,scheduled_assigned_user_id,
    status,last_attempt_at,last_execution_id,last_error_code,last_error_at,
    created_by,created_at,updated_at
  ) values (
    v_app.id,v_app.definition_id,v_app.definition_version_id,v_app.organization_id,
    'scheduled_once',v_timezone,v_run_at,
    case when v_assignment_type='manual' then v_resolved else null end,
    'active',null,null,null,null,
    p_actor_user_id,now(),now()
  )
  on conflict(application_id) do update
  set schedule_kind=excluded.schedule_kind,
      schedule_timezone=excluded.schedule_timezone,
      next_run_at=excluded.next_run_at,
      scheduled_assigned_user_id=excluded.scheduled_assigned_user_id,
      status='active',
      last_attempt_at=null,
      last_execution_id=null,
      last_error_code=null,
      last_error_at=null,
      updated_at=now()
  returning * into v_schedule;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_app.organization_id,p_actor_user_id,'workflow_schedule_configured',
    'workflow_application',v_app.id::text,'success',
    jsonb_build_object(
      'schedule_kind','scheduled_once',
      'timezone',v_timezone,
      'next_run_at',v_run_at,
      'scheduled_assigned_user_id',
        case when v_assignment_type='manual' then v_resolved else null end
    )
  );

  return v_schedule;
end;
$workflow_configure_schedule$;

revoke all on function private.workflow_configure_application_schedule_v1(
  uuid,text,uuid,uuid
) from public,anon,authenticated;

create or replace function private.workflow_application_schedule_status_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $workflow_schedule_app_status$
begin
  if old.status is distinct from new.status
    and new.status='archived' then
    update public.workflow_application_schedules_v2
    set status='cancelled',
        updated_at=now()
    where application_id=new.id
      and status in ('active','blocked');
  end if;
  return new;
end;
$workflow_schedule_app_status$;

revoke all on function private.workflow_application_schedule_status_v1()
  from public,anon,authenticated;

drop trigger if exists workflow_application_schedule_status_v1
  on public.workflow_applications_v2;

create trigger workflow_application_schedule_status_v1
after update of status
on public.workflow_applications_v2
for each row
execute function private.workflow_application_schedule_status_v1();

create or replace function private.process_due_workflow_schedules_v1(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path=''
as $workflow_process_schedules$
declare
  v_schedule public.workflow_application_schedules_v2;
  v_execution_id uuid;
  v_execution_status text;
  v_execution_assignee uuid;
  v_execution_created_at timestamptz;
  v_created_new boolean;
  v_key text;
  v_processed integer:=0;
begin
  for v_schedule in
    select s.*
    from public.workflow_application_schedules_v2 s
    join public.workflow_applications_v2 a on a.id=s.application_id
    join public.workflow_definitions_v2 d on d.id=s.definition_id
    where s.status='active'
      and s.schedule_kind='scheduled_once'
      and s.next_run_at<=p_now
      and a.status='configured'
      and d.status='published'
    order by s.next_run_at,s.application_id
    for update of s skip locked
  loop
    update public.workflow_application_schedules_v2
    set last_attempt_at=p_now,
        updated_at=now()
    where application_id=v_schedule.application_id;

    v_key:='scheduled-once:'||v_schedule.application_id::text||':'||
      extract(epoch from v_schedule.next_run_at)::bigint::text;

    begin
      select x.execution_id,x.status,x.assigned_user_id,x.created_at,x.created_new
      into v_execution_id,v_execution_status,v_execution_assignee,
           v_execution_created_at,v_created_new
      from private.workflow_execute_application_internal_v1(
        v_schedule.application_id,
        v_key,
        v_schedule.scheduled_assigned_user_id,
        'scheduled_once',
        v_schedule.created_by
      ) x
      limit 1;

      update public.workflow_application_schedules_v2
      set status='completed',
          last_execution_id=v_execution_id,
          last_error_code=null,
          last_error_at=null,
          updated_at=now()
      where application_id=v_schedule.application_id;

      v_processed:=v_processed+1;

    exception when others then
      update public.workflow_application_schedules_v2
      set status='blocked',
          last_error_code=left(sqlstate||':'||sqlerrm,240),
          last_error_at=now(),
          updated_at=now()
      where application_id=v_schedule.application_id;

      insert into public.notifications_v2(
        organization_id,recipient_user_id,event_type,title,body,
        status,channel_in_app,channel_email,
        source_kind,source_id,event_key
      ) values (
        v_schedule.organization_id,
        v_schedule.created_by,
        'workflow_schedule_blocked',
        'Programación bloqueada',
        'No se pudo crear la tarea programada. Revisa el flujo y su destino.',
        'pending',true,false,
        'workflow_schedule',v_schedule.application_id,'blocked'
      )
      on conflict(source_kind,source_id,event_key,recipient_user_id)
      where source_kind is not null
        and source_id is not null
        and event_key is not null
      do nothing;

      insert into public.audit_log_v2(
        organization_id,actor_user_id,action,entity_type,entity_id,result,details
      ) values (
        v_schedule.organization_id,v_schedule.created_by,
        'workflow_schedule_blocked','workflow_application',
        v_schedule.application_id::text,'failure',
        jsonb_build_object(
          'schedule_kind',v_schedule.schedule_kind,
          'next_run_at',v_schedule.next_run_at,
          'sqlstate',sqlstate
        )
      );
    end;
  end loop;

  return v_processed;
end;
$workflow_process_schedules$;

revoke all on function private.process_due_workflow_schedules_v1(timestamptz)
  from public,anon,authenticated;

create or replace function public.publish_workflow_ready_v2(
  p_spec jsonb,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_execute boolean default false,
  p_request_key text default null,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null,
  p_schedule_timezone text default null,
  p_schedule_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  published_at timestamptz,
  schedule_next_run_at timestamptz,
  schedule_status text
)
language plpgsql
security definer
set search_path=''
as $workflow_ready_v2$
declare
  v_actor uuid:=auth.uid();
  v_result record;
  v_schedule public.workflow_application_schedules_v2;
begin
  if p_execute and coalesce(p_spec->>'triggerType','')='scheduled_once' then
    raise exception 'workflow_scheduled_execute_now_forbidden' using errcode='22023';
  end if;

  select * into v_result
  from public.publish_workflow_ready_v1(
    p_spec,p_property_id,p_room_id,p_occupancy_id,p_photo_pattern_ids,
    p_execute,p_request_key,p_idempotency_key,p_assigned_user_id
  )
  limit 1;

  v_schedule:=private.workflow_configure_application_schedule_v1(
    v_result.application_id,
    p_schedule_assigned_user_id,
    v_actor
  );

  return query select
    v_result.definition_id,v_result.version_id,v_result.version,
    v_result.application_id,v_result.execution_id,v_result.execution_status,
    v_result.assigned_user_id,v_result.published_at,
    v_schedule.next_run_at,v_schedule.status;
end;
$workflow_ready_v2$;

revoke all on function public.publish_workflow_ready_v2(
  jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid,text,uuid
) from public,anon;
grant execute on function public.publish_workflow_ready_v2(
  jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid,text,uuid
) to authenticated;

create or replace function public.update_unexecuted_workflow_v2(
  p_definition_id uuid,
  p_spec jsonb,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_expected_revision bigint default null,
  p_execute boolean default false,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null,
  p_schedule_timezone text default null,
  p_schedule_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  revision bigint,
  schedule_next_run_at timestamptz,
  schedule_status text
)
language plpgsql
security definer
set search_path=''
as $workflow_update_v2$
declare
  v_actor uuid:=auth.uid();
  v_result record;
  v_schedule public.workflow_application_schedules_v2;
begin
  if p_execute and coalesce(p_spec->>'triggerType','')='scheduled_once' then
    raise exception 'workflow_scheduled_execute_now_forbidden' using errcode='22023';
  end if;

  select * into v_result
  from public.update_unexecuted_workflow_v1(
    p_definition_id,p_spec,p_property_id,p_room_id,p_occupancy_id,
    p_photo_pattern_ids,p_expected_revision,p_execute,p_idempotency_key,
    p_assigned_user_id
  )
  limit 1;

  v_schedule:=private.workflow_configure_application_schedule_v1(
    v_result.application_id,
    p_schedule_assigned_user_id,
    v_actor
  );

  return query select
    v_result.definition_id,v_result.version_id,v_result.version,
    v_result.application_id,v_result.execution_id,v_result.execution_status,
    v_result.assigned_user_id,v_result.revision,
    v_schedule.next_run_at,v_schedule.status;
end;
$workflow_update_v2$;

revoke all on function public.update_unexecuted_workflow_v2(
  uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid,text,uuid
) from public,anon;
grant execute on function public.update_unexecuted_workflow_v2(
  uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid,text,uuid
) to authenticated;

create or replace function public.publish_workflow_revision_ready_v2(
  p_definition_id uuid,
  p_expected_revision bigint,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_execute boolean default false,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null,
  p_schedule_timezone text default null,
  p_schedule_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  published_at timestamptz,
  schedule_next_run_at timestamptz,
  schedule_status text
)
language plpgsql
security definer
set search_path=''
as $workflow_revision_ready_v2$
declare
  v_actor uuid:=auth.uid();
  v_result record;
  v_schedule public.workflow_application_schedules_v2;
  v_trigger_type text;
begin
  select rd.draft_spec->>'triggerType'
  into v_trigger_type
  from public.workflow_definition_revision_drafts_v2 rd
  where rd.definition_id=p_definition_id
    and rd.published_at is null;

  if p_execute and coalesce(v_trigger_type,'')='scheduled_once' then
    raise exception 'workflow_scheduled_execute_now_forbidden' using errcode='22023';
  end if;

  select * into v_result
  from public.publish_workflow_revision_ready_v1(
    p_definition_id,p_expected_revision,p_property_id,p_room_id,p_occupancy_id,
    p_photo_pattern_ids,p_execute,p_idempotency_key,p_assigned_user_id
  )
  limit 1;

  v_schedule:=private.workflow_configure_application_schedule_v1(
    v_result.application_id,
    p_schedule_assigned_user_id,
    v_actor
  );

  return query select
    v_result.definition_id,v_result.version_id,v_result.version,
    v_result.application_id,v_result.execution_id,v_result.execution_status,
    v_result.assigned_user_id,v_result.published_at,
    v_schedule.next_run_at,v_schedule.status;
end;
$workflow_revision_ready_v2$;

revoke all on function public.publish_workflow_revision_ready_v2(
  uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid,text,uuid
) from public,anon;
grant execute on function public.publish_workflow_revision_ready_v2(
  uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid,text,uuid
) to authenticated;

comment on table public.workflow_application_schedules_v2 is
  'Estado operativo de activaciones automáticas por aplicación/version. scheduled_once es el primer tipo habilitado.';
comment on function private.workflow_execute_application_internal_v1(uuid,text,uuid,text,uuid) is
  'Núcleo único de ejecución para manual_now y scheduled_once. No es invocable por clientes.';
comment on function private.process_due_workflow_schedules_v1(timestamptz) is
  'Procesa programaciones due con SKIP LOCKED, una ejecución idempotente por fecha y bloqueo explícito ante error.';
