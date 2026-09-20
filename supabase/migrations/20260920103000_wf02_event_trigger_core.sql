-- GestionPisos · WF-02 · disparador genérico por evento
-- Núcleo reproducible sin pg_cron. El cron se registra en una migración separada.

create table public.workflow_event_outbox_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  event_type text not null check (event_type in ('occupancy.created')),
  source_kind text not null check (source_kind in ('occupancy')),
  source_id uuid not null,
  event_key text not null check (length(btrim(event_key)) between 1 and 120),
  property_id uuid references public.properties_v2(id) on delete restrict,
  room_id uuid references public.rooms_v2(id) on delete restrict,
  occupancy_id uuid references public.occupancies_v2(id) on delete restrict,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  actor_user_id uuid references auth.users(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending','processed','processed_with_errors')),
  occurred_at timestamptz not null default now(),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint workflow_event_outbox_v2_source_uq
    unique(organization_id,event_type,source_kind,source_id,event_key),
  constraint workflow_event_outbox_v2_status_time_check check (
    (status='pending' and processed_at is null)
    or (status in ('processed','processed_with_errors') and processed_at is not null)
  )
);

create index workflow_event_outbox_v2_pending_idx
  on public.workflow_event_outbox_v2(occurred_at,id)
  where status='pending';

create table public.workflow_event_dispatches_v2 (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.workflow_event_outbox_v2(id) on delete restrict,
  application_id uuid not null references public.workflow_applications_v2(id) on delete restrict,
  execution_id uuid references public.workflow_executions_v2(id) on delete restrict,
  status text not null check (status in ('executed','failed')),
  error_code text,
  error_key text,
  created_at timestamptz not null default now(),
  constraint workflow_event_dispatches_v2_event_application_uq
    unique(event_id,application_id),
  constraint workflow_event_dispatches_v2_result_check check (
    (status='executed' and execution_id is not null and error_code is null and error_key is null)
    or (status='failed' and execution_id is null and error_code is not null)
  )
);

create index workflow_event_dispatches_v2_application_idx
  on public.workflow_event_dispatches_v2(application_id,created_at desc);

alter table public.workflow_event_outbox_v2 enable row level security;
alter table public.workflow_event_dispatches_v2 enable row level security;

revoke all on public.workflow_event_outbox_v2
  from public,anon,authenticated,service_role;
revoke all on public.workflow_event_dispatches_v2
  from public,anon,authenticated,service_role;

create or replace function private.workflow_sanitize_authoring_spec_v3(
  p_spec jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $workflow_sanitize_v3$
declare
  v_spec jsonb;
  v_trigger_type text;
  v_event_type text;
  v_timezone text;
  v_utc text;
  v_local text;
  v_run_at timestamptz;
  v_roundtrip text;
  v_assignment_type text;
  v_assignment_user_id text;
  v_assignment_role text;
begin
  v_spec:=private.workflow_sanitize_authoring_spec_v2(p_spec);
  v_trigger_type:=nullif(v_spec->>'triggerType','');
  v_event_type:=nullif(btrim(coalesce(p_spec->>'eventType','')),'');
  v_assignment_type:=nullif(v_spec->>'assignmentType','');
  v_assignment_user_id:=nullif(btrim(coalesce(p_spec->>'assignmentUserId','')),'');
  v_assignment_role:=nullif(btrim(coalesce(p_spec->>'assignmentRole','')),'');

  if v_trigger_type='event' then
    if v_event_type is not null and v_event_type not in ('occupancy.created') then
      raise exception 'workflow_event_type_invalid' using errcode='22023';
    end if;
  else
    v_event_type:=null;
  end if;

  if v_assignment_type='fixed_person' then
    if v_assignment_user_id is not null
      and v_assignment_user_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'workflow_fixed_person_invalid' using errcode='22023';
    end if;
  else
    v_assignment_user_id:=null;
  end if;

  if v_assignment_type='role' then
    if v_assignment_role is not null
      and v_assignment_role not in ('admin','employee','tenant') then
      raise exception 'workflow_assignment_role_invalid' using errcode='22023';
    end if;
  else
    v_assignment_role:=null;
  end if;

  v_spec:=v_spec || jsonb_build_object(
    'eventType',coalesce(v_event_type,''),
    'assignmentUserId',coalesce(lower(v_assignment_user_id),''),
    'assignmentRole',coalesce(v_assignment_role,'')
  );

  if v_trigger_type not in ('scheduled_once','recurring') then
    return v_spec || jsonb_build_object(
      'scheduledTimezone','',
      'scheduledAtUtc',''
    );
  end if;

  v_timezone:=nullif(btrim(coalesce(p_spec->>'scheduledTimezone','')),'');
  v_utc:=nullif(btrim(coalesce(p_spec->>'scheduledAtUtc','')),'');
  v_local:=nullif(btrim(coalesce(p_spec->>'scheduledAt','')),'');

  if v_timezone is null
    or length(v_timezone)>80
    or not exists(
      select 1
      from pg_catalog.pg_timezone_names tz
      where tz.name=v_timezone
    ) then
    raise exception 'workflow_schedule_timezone_invalid' using errcode='22023';
  end if;

  if v_utc is null
    or v_utc !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{3})?Z$' then
    raise exception 'workflow_scheduled_utc_invalid' using errcode='22023';
  end if;

  begin
    v_run_at:=v_utc::timestamptz;
  exception when others then
    raise exception 'workflow_scheduled_utc_invalid' using errcode='22023';
  end;

  if v_run_at is distinct from date_trunc('minute',v_run_at) then
    raise exception 'workflow_schedule_time_mismatch' using errcode='22023';
  end if;

  v_roundtrip:=to_char(
    v_run_at at time zone v_timezone,
    'YYYY-MM-DD"T"HH24:MI'
  );

  if v_local is null or v_roundtrip is distinct from v_local then
    raise exception 'workflow_schedule_time_mismatch' using errcode='22023';
  end if;

  if exists(
    select 1
    from generate_series(-180,180) as delta(minutes)
    where delta.minutes<>0
      and to_char(
        (v_run_at + delta.minutes * interval '1 minute') at time zone v_timezone,
        'YYYY-MM-DD"T"HH24:MI'
      )=v_local
  ) then
    raise exception 'workflow_schedule_local_time_ambiguous' using errcode='22023';
  end if;

  return v_spec || jsonb_build_object(
    'scheduledAt',v_local,
    'scheduledTimezone',v_timezone,
    'scheduledAtUtc',v_utc
  );
end;
$workflow_sanitize_v3$;

revoke all on function private.workflow_sanitize_authoring_spec_v3(jsonb)
  from public,anon,authenticated,service_role;

create or replace function public.workflow_authoring_complete_v1(p_spec jsonb)
returns boolean
language plpgsql
immutable
set search_path=public,pg_temp
as $workflow_complete$
declare
  v_item jsonb;
  v_has_required boolean:=false;
begin
  if jsonb_typeof(p_spec)<>'object'
    or not (
      case
        when coalesce(p_spec->>'authoringVersion','') ~ '^[0-9]+$'
          then (p_spec->>'authoringVersion')::integer>=2
        else false
      end
    )
    or char_length(btrim(coalesce(p_spec->>'flowName',''))) not between 3 and 80
    or (p_spec->>'flowType') not in ('cleaning','inspection','maintenance','checkin','checkout','custom')
    or (p_spec->>'scopeType') not in ('organization','property','room','occupancy')
    or (p_spec->>'triggerType') not in ('manual','recurring','scheduled_once','event')
    or not (
      (p_spec->>'triggerType')='manual'
      or (
        (p_spec->>'triggerType')='event'
        and coalesce(p_spec->>'eventType','') in ('occupancy.created')
      )
      or (
        (p_spec->>'triggerType')='scheduled_once'
        and coalesce(p_spec->>'scheduledAt','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$'
        and char_length(btrim(coalesce(p_spec->>'scheduledTimezone',''))) between 1 and 80
        and coalesce(p_spec->>'scheduledAtUtc','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{3})?Z$'
      )
      or (
        (p_spec->>'triggerType')='recurring'
        and coalesce(p_spec->>'scheduledAt','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$'
        and char_length(btrim(coalesce(p_spec->>'scheduledTimezone',''))) between 1 and 80
        and coalesce(p_spec->>'scheduledAtUtc','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{3})?Z$'
        and (
          (p_spec->>'recurrence') in ('weekly','biweekly','monthly')
          or (
            (p_spec->>'recurrence')='custom'
            and case
              when coalesce(p_spec->>'customEvery','') ~ '^[0-9]+$'
                then (p_spec->>'customEvery')::integer between 1 and 365
              else false
            end
            and (p_spec->>'customUnit') in ('day','week','month')
          )
        )
      )
    )
    or (
      (p_spec->>'triggerType')<>'event'
      and coalesce(p_spec->>'eventType','')<>''
    )
    or (
      (p_spec->>'triggerType')='event'
      and (p_spec->>'assignmentType')='manual'
    )
    or (p_spec->>'assignmentType') not in ('property_responsible','active_occupants_rotation','fixed_person','role','manual')
    or (
      (p_spec->>'assignmentType')='property_responsible'
      and (p_spec->>'scopeType')='organization'
    )
    or (
      (p_spec->>'assignmentType')='fixed_person'
      and coalesce(p_spec->>'assignmentUserId','')
        !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    )
    or (
      (p_spec->>'assignmentType')='role'
      and coalesce(p_spec->>'assignmentRole','') not in ('admin','employee','tenant')
    )
    or (
      (p_spec->>'assignmentType')='role'
      and (p_spec->>'assignmentRole')='tenant'
      and (p_spec->>'scopeType')='organization'
    )
    or (
      (p_spec->>'assignmentType')='role'
      and (p_spec->>'assignmentRole') in ('admin','employee')
      and (p_spec->>'scopeType')='occupancy'
    )
    or (
      (p_spec->>'assignmentType')='active_occupants_rotation'
      and (p_spec->>'scopeType')='organization'
    )
    or not (
      coalesce(p_spec#>>'{steps,accept}','false')='true'
      or coalesce(p_spec#>>'{steps,photo}','false')='true'
      or coalesce(p_spec#>>'{steps,checklist}','false')='true'
      or coalesce(p_spec#>>'{steps,document}','false')='true'
    )
    or (p_spec->>'closeType') not in ('auto','human_review','domain_adapter') then
    return false;
  end if;

  if coalesce((p_spec#>>'{steps,checklist}')::boolean,false) then
    if jsonb_typeof(p_spec->'checklistItems')<>'array'
      or jsonb_array_length(p_spec->'checklistItems')<1
      or jsonb_array_length(p_spec->'checklistItems')>30 then
      return false;
    end if;

    for v_item in select value from jsonb_array_elements(p_spec->'checklistItems')
    loop
      if jsonb_typeof(v_item)<>'object'
        or char_length(btrim(coalesce(v_item->>'text',''))) not between 1 and 160
        or (v_item ? 'required' and jsonb_typeof(v_item->'required')<>'boolean') then
        return false;
      end if;
      if coalesce((v_item->>'required')::boolean,true) then
        v_has_required:=true;
      end if;
    end loop;

    if not v_has_required then
      return false;
    end if;
  end if;

  return true;
end;
$workflow_complete$;

revoke all on function public.workflow_authoring_complete_v1(jsonb)
  from public,anon;
grant execute on function public.workflow_authoring_complete_v1(jsonb)
  to authenticated;

alter table public.workflow_executions_v2
  drop constraint if exists workflow_executions_v2_trigger_kind_check;
alter table public.workflow_executions_v2
  add constraint workflow_executions_v2_trigger_kind_check
  check (trigger_kind in ('manual_now','scheduled_once','recurring','event'));

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
  v_spec_trigger text;
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

  if p_trigger_kind not in ('manual_now','scheduled_once','recurring','event') then
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

  v_spec_trigger:=nullif(v_spec->>'triggerType','');
  if v_spec_trigger='event' and p_trigger_kind<>'event' then
    raise exception 'workflow_event_manual_execution_forbidden' using errcode='55000';
  end if;
  if p_trigger_kind='event' and v_spec_trigger<>'event' then
    raise exception 'workflow_event_trigger_mismatch' using errcode='55000';
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
) from public,anon,authenticated,service_role;

create or replace function private.workflow_execution_trigger_kind_guard_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $workflow_trigger_guard$
declare
  v_spec_trigger text:=nullif(new.spec_snapshot->>'triggerType','');
begin
  if v_spec_trigger='scheduled_once' and new.trigger_kind<>'scheduled_once' then
    raise exception 'workflow_scheduled_manual_execution_forbidden' using errcode='55000';
  end if;

  if v_spec_trigger='recurring' and new.trigger_kind<>'recurring' then
    raise exception 'workflow_recurring_manual_execution_forbidden' using errcode='55000';
  end if;

  if v_spec_trigger='event' and new.trigger_kind<>'event' then
    raise exception 'workflow_event_manual_execution_forbidden' using errcode='55000';
  end if;

  if new.trigger_kind='scheduled_once' and v_spec_trigger<>'scheduled_once' then
    raise exception 'workflow_scheduled_trigger_mismatch' using errcode='55000';
  end if;

  if new.trigger_kind='recurring' and v_spec_trigger<>'recurring' then
    raise exception 'workflow_recurring_trigger_mismatch' using errcode='55000';
  end if;

  if new.trigger_kind='event' and v_spec_trigger<>'event' then
    raise exception 'workflow_event_trigger_mismatch' using errcode='55000';
  end if;

  return new;
end;
$workflow_trigger_guard$;

revoke all on function private.workflow_execution_trigger_kind_guard_v1()
  from public,anon,authenticated,service_role;

create or replace function private.workflow_enqueue_event_v1(
  p_organization_id uuid,
  p_event_type text,
  p_source_kind text,
  p_source_id uuid,
  p_event_key text,
  p_property_id uuid,
  p_room_id uuid,
  p_occupancy_id uuid,
  p_payload jsonb default '{}'::jsonb,
  p_actor_user_id uuid default null,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path=''
as $workflow_enqueue_event$
declare
  v_event_id uuid;
  v_occ public.occupancies_v2;
begin
  if p_organization_id is null or p_source_id is null
    or nullif(btrim(p_event_key),'') is null then
    raise exception 'workflow_event_identity_invalid' using errcode='22023';
  end if;

  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'workflow_event_payload_invalid' using errcode='22023';
  end if;

  if p_event_type='occupancy.created' then
    if p_source_kind<>'occupancy'
      or p_occupancy_id is distinct from p_source_id then
      raise exception 'workflow_event_source_invalid' using errcode='22023';
    end if;

    select o.* into v_occ
    from public.occupancies_v2 o
    where o.id=p_source_id;

    if v_occ.id is null
      or v_occ.organization_id is distinct from p_organization_id
      or v_occ.property_id is distinct from p_property_id
      or v_occ.room_id is distinct from p_room_id then
      raise exception 'workflow_event_routing_invalid' using errcode='22023';
    end if;
  else
    raise exception 'workflow_event_type_invalid' using errcode='22023';
  end if;

  insert into public.workflow_event_outbox_v2(
    organization_id,event_type,source_kind,source_id,event_key,
    property_id,room_id,occupancy_id,payload,actor_user_id,occurred_at
  ) values (
    p_organization_id,p_event_type,p_source_kind,p_source_id,btrim(p_event_key),
    p_property_id,p_room_id,p_occupancy_id,p_payload,p_actor_user_id,
    coalesce(p_occurred_at,now())
  )
  on conflict(organization_id,event_type,source_kind,source_id,event_key)
  do nothing
  returning id into v_event_id;

  if v_event_id is null then
    select e.id into v_event_id
    from public.workflow_event_outbox_v2 e
    where e.organization_id=p_organization_id
      and e.event_type=p_event_type
      and e.source_kind=p_source_kind
      and e.source_id=p_source_id
      and e.event_key=btrim(p_event_key);
  end if;

  return v_event_id;
end;
$workflow_enqueue_event$;

revoke all on function private.workflow_enqueue_event_v1(
  uuid,text,text,uuid,text,uuid,uuid,uuid,jsonb,uuid,timestamptz
) from public,anon,authenticated,service_role;

create or replace function private.workflow_capture_occupancy_created_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $workflow_capture_occupancy_created$
begin
  perform private.workflow_enqueue_event_v1(
    new.organization_id,
    'occupancy.created',
    'occupancy',
    new.id,
    'created',
    new.property_id,
    new.room_id,
    new.id,
    jsonb_build_object(
      'status',new.status::text,
      'startsOn',new.starts_on
    ),
    auth.uid(),
    now()
  );
  return new;
end;
$workflow_capture_occupancy_created$;

revoke all on function private.workflow_capture_occupancy_created_v1()
  from public,anon,authenticated,service_role;

drop trigger if exists workflow_occupancy_created_event_v1
  on public.occupancies_v2;
create trigger workflow_occupancy_created_event_v1
after insert on public.occupancies_v2
for each row
execute function private.workflow_capture_occupancy_created_v1();

create or replace function private.process_pending_workflow_events_v1(
  p_limit integer default 50
)
returns integer
language plpgsql
security definer
set search_path=''
as $workflow_process_events$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),500);
  v_event public.workflow_event_outbox_v2;
  v_app record;
  v_execution_id uuid;
  v_execution_status text;
  v_execution_assignee uuid;
  v_execution_created_at timestamptz;
  v_created_new boolean;
  v_errors integer;
  v_processed integer:=0;
  v_key text;
begin
  for v_event in
    select e.*
    from public.workflow_event_outbox_v2 e
    where e.status='pending'
    order by e.occurred_at,e.id
    limit v_limit
    for update skip locked
  loop
    v_errors:=0;

    for v_app in
      select
        a.id as application_id,
        a.created_by,
        a.scope_type,
        a.property_id,
        a.room_id,
        a.occupancy_id
      from public.workflow_applications_v2 a
      join public.workflow_definition_versions_v2 wv
        on wv.id=a.definition_version_id
       and wv.definition_id=a.definition_id
       and wv.organization_id=a.organization_id
      join public.workflow_definitions_v2 d
        on d.id=a.definition_id
       and d.organization_id=a.organization_id
      where a.organization_id=v_event.organization_id
        and a.status='configured'
        and d.status='published'
        and wv.spec->>'triggerType'='event'
        and wv.spec->>'eventType'=v_event.event_type
        and (
          a.scope_type='organization'
          or (
            a.scope_type='property'
            and a.property_id=v_event.property_id
          )
          or (
            a.scope_type='room'
            and a.property_id=v_event.property_id
            and a.room_id=v_event.room_id
          )
          or (
            a.scope_type='occupancy'
            and a.occupancy_id=v_event.occupancy_id
          )
        )
      order by a.id
    loop
      if exists(
        select 1
        from public.workflow_event_dispatches_v2 d
        where d.event_id=v_event.id
          and d.application_id=v_app.application_id
      ) then
        continue;
      end if;

      v_key:='event:'||v_event.id::text;

      begin
        select x.execution_id,x.status,x.assigned_user_id,x.created_at,x.created_new
        into v_execution_id,v_execution_status,v_execution_assignee,
             v_execution_created_at,v_created_new
        from private.workflow_execute_application_internal_v1(
          v_app.application_id,
          v_key,
          null,
          'event',
          v_app.created_by
        ) x
        limit 1;

        insert into public.workflow_event_dispatches_v2(
          event_id,application_id,execution_id,status
        ) values (
          v_event.id,v_app.application_id,v_execution_id,'executed'
        );

        insert into public.audit_log_v2(
          organization_id,actor_user_id,action,entity_type,entity_id,result,details
        ) values (
          v_event.organization_id,v_app.created_by,
          'workflow_event_dispatched','workflow_event',v_event.id::text,'success',
          jsonb_build_object(
            'event_type',v_event.event_type,
            'source_kind',v_event.source_kind,
            'source_id',v_event.source_id,
            'application_id',v_app.application_id,
            'execution_id',v_execution_id
          )
        );
      exception when others then
        v_errors:=v_errors+1;

        insert into public.workflow_event_dispatches_v2(
          event_id,application_id,status,error_code,error_key
        ) values (
          v_event.id,v_app.application_id,'failed',sqlstate,left(sqlerrm,120)
        )
        on conflict(event_id,application_id) do nothing;

        insert into public.audit_log_v2(
          organization_id,actor_user_id,action,entity_type,entity_id,result,details
        ) values (
          v_event.organization_id,v_app.created_by,
          'workflow_event_dispatch_failed','workflow_event',v_event.id::text,'failure',
          jsonb_build_object(
            'event_type',v_event.event_type,
            'source_kind',v_event.source_kind,
            'source_id',v_event.source_id,
            'application_id',v_app.application_id,
            'sqlstate',sqlstate
          )
        );
      end;
    end loop;

    update public.workflow_event_outbox_v2
    set status=case when v_errors>0 then 'processed_with_errors' else 'processed' end,
        processed_at=now()
    where id=v_event.id;

    v_processed:=v_processed+1;
  end loop;

  return v_processed;
end;
$workflow_process_events$;

revoke all on function private.process_pending_workflow_events_v1(integer)
  from public,anon,authenticated,service_role;

comment on table public.workflow_event_outbox_v2 is
  'Outbox inmutable de eventos de negocio que pueden activar aplicaciones de workflow; los productores no ejecutan tareas dentro de su transacción.';
comment on table public.workflow_event_dispatches_v2 is
  'Recibo idempotente por evento y aplicación, enlazando el evento origen con la ejecución creada o el fallo de despacho.';
comment on function private.process_pending_workflow_events_v1(integer) is
  'Despacha eventos pendientes hacia el motor común; un fallo de una aplicación no revierte el evento de negocio ni otros despachos.';

-- Mantener operativo el factory reset explícito de pruebas: las nuevas tablas
-- participan en el mismo TRUNCATE para no bloquear el reset por FKs.
create or replace function public.factory_reset_test_data_service(
  p_actor_user_id uuid,
  p_operator_user_id uuid,
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $factory_reset$
declare
  v_reset_at timestamptz := now();
  v_profile_organization_id uuid;
  v_active_organization_count integer := 0;
begin
  perform set_config('lock_timeout','5s',true);
  perform set_config('statement_timeout','30s',true);

  if p_actor_user_id is null or p_operator_user_id is null or p_organization_id is null then
    raise exception 'factory_reset_invalid_protected_identity';
  end if;

  if p_actor_user_id=p_operator_user_id then
    raise exception 'factory_reset_operator_must_be_independent';
  end if;

  if not exists(
    select 1
    from public.user_roles ur
    where ur.user_id=p_actor_user_id
      and lower(ur.role::text)='root'
      and ur.revoked_at is null
  ) then
    raise exception 'factory_reset_root_required';
  end if;

  if not exists(
    select 1
    from public.organizations o
    where o.id=p_organization_id
      and lower(o.status::text)='active'
  ) then
    raise exception 'factory_reset_active_organization_required';
  end if;

  select p.organization_id
  into v_profile_organization_id
  from public.profiles p
  where p.user_id=p_actor_user_id
    and lower(p.status::text)='active'
  limit 1;

  if v_profile_organization_id is not null then
    if v_profile_organization_id<>p_organization_id then
      raise exception 'factory_reset_root_organization_mismatch';
    end if;
  else
    select count(*) into v_active_organization_count
    from public.organizations o
    where lower(o.status::text)='active';

    if v_active_organization_count<>1 then
      raise exception 'factory_reset_root_organization_ambiguous';
    end if;
  end if;

  if not exists(
    select 1
    from public.platform_operators po
    where po.user_id=p_operator_user_id
      and po.active=true
      and po.can_recover_root=true
  ) then
    raise exception 'factory_reset_root_recovery_operator_required';
  end if;

  truncate table
    public.access_requests,
    public.admin_capability_holders,
    public.admin_capability_requests,
    public.audit_log_v2,
    public.broadcasts_v2,
    public.claims_v2,
    public.cleaning_audit_items_v2,
    public.cleaning_audit_policies_v2,
    public.cleaning_audits_v2,
    public.cleaning_debts_v2,
    public.cleaning_photo_request_policies_v2,
    public.cleaning_photo_requests_v2,
    public.cleaning_plans_v2,
    public.cleaning_swap_requests_v2,
    public.cleaning_tasks_v2,
    public.external_account_onboarding,
    public.incident_evidence_v2,
    public.incident_updates_v2,
    public.incidents_v2,
    public.internal_staff_onboarding,
    public.internal_staff_onboarding_access_snapshot,
    public.notifications_v2,
    public.workflow_event_dispatches_v2,
    public.workflow_event_outbox_v2,
    public.occupancies_v2,
    public.owners,
    public.payment_obligations_v2,
    public.photo_patterns_v2,
    public.photo_verification_items_v2,
    public.photo_verification_runs_v2,
    public.properties,
    public.properties_v2,
    public.property_qr_tokens,
    public.property_staff_access_v2,
    public.property_staff_access_v3,
    public.property_staff_assignments,
    public.random_photo_requests_v2,
    public.reminder_rules_v2,
    public.rooms,
    public.rooms_v2,
    public.tenancies,
    public.tenant_documents_v2,
    public.tenant_privacy_events_v2,
    public.tenant_task_actions_v2,
    public.tenant_task_history_v2,
    public.tenant_tasks_v2,
    public.tenants_v2,
    public.verification_policies_v2,
    public.workflow_execution_photo_resources_v2,
    public.workflow_application_photo_resources_v2,
    public.workflow_execution_events_v2,
    public.workflow_executions_v2,
    public.workflow_applications_v2,
    public.workflow_definition_versions_v2,
    public.workflow_definitions_v2
  restart identity;

  delete from public.platform_operators
  where user_id<>p_operator_user_id;

  delete from public.profiles
  where user_id<>p_actor_user_id;

  delete from public.user_roles
  where user_id<>p_actor_user_id;

  delete from public.organizations
  where id<>p_organization_id;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    p_organization_id,p_actor_user_id,'factory_reset_completed',
    'organization',p_organization_id::text,'success',
    jsonb_build_object(
      'mode','test_factory_reset',
      'preserved_root_user_id',p_actor_user_id,
      'preserved_operator_user_id',p_operator_user_id,
      'historical_audit_cleared',true,
      'static_workflow_templates_preserved',true,
      'completed_at',v_reset_at
    )
  );

  return jsonb_build_object(
    'ok',true,
    'completed_at',v_reset_at,
    'preserved_root_user_id',p_actor_user_id,
    'preserved_operator_user_id',p_operator_user_id,
    'preserved_organization_id',p_organization_id
  );
end;
$factory_reset$;

