-- GestionPisos · Flujos de Trabajo · recurrencias automáticas
-- Reutiliza workflow_application_schedules_v2 y el cron existente.
-- No crea un segundo scheduler.
--
-- Semántica:
--   * recurring exige primera fecha/hora explícita + zona IANA + UTC exacto;
--   * manual fija el asignado al Programar y se revalida en cada ejecución;
--   * property_responsible se resuelve en cada ocurrencia;
--   * la siguiente fecha se deriva siempre del ancla original, no de la
--     ocurrencia ajustada anterior, evitando deriva mensual;
--   * horas DST ambiguas/inexistentes bloquean la recurrencia, no se corrigen
--     silenciosamente;
--   * una ocurrencia vencida se procesa una vez por pasada del cron. No se
--     saltan obligaciones históricas de forma implícita.

alter table public.workflow_executions_v2
  drop constraint if exists workflow_executions_v2_trigger_kind_check;

alter table public.workflow_executions_v2
  add constraint workflow_executions_v2_trigger_kind_check
  check (trigger_kind in ('manual_now','scheduled_once','recurring'));

alter table public.workflow_application_schedules_v2
  drop constraint if exists workflow_application_schedules_v2_schedule_kind_check;

alter table public.workflow_application_schedules_v2
  add constraint workflow_application_schedules_v2_schedule_kind_check
  check (schedule_kind in ('scheduled_once','recurring'));

alter table public.workflow_application_schedules_v2
  add column if not exists occurrence_index bigint not null default 0;

alter table public.workflow_application_schedules_v2
  drop constraint if exists workflow_application_schedules_v2_occurrence_index_check;

alter table public.workflow_application_schedules_v2
  add constraint workflow_application_schedules_v2_occurrence_index_check
  check (occurrence_index>=0);

create or replace function private.workflow_local_time_to_unique_utc_v1(
  p_local timestamp,
  p_timezone text
)
returns timestamptz
language plpgsql
stable
security definer
set search_path=''
as $workflow_local_to_utc$
declare
  v_timezone text:=nullif(btrim(p_timezone),'');
  v_run_at timestamptz;
  v_roundtrip timestamp;
begin
  if p_local is null then
    raise exception 'workflow_schedule_local_time_invalid' using errcode='22023';
  end if;

  if v_timezone is null
    or not exists(
      select 1
      from pg_catalog.pg_timezone_names tz
      where tz.name=v_timezone
    ) then
    raise exception 'workflow_schedule_timezone_invalid' using errcode='22023';
  end if;

  v_run_at:=p_local at time zone v_timezone;
  v_roundtrip:=v_run_at at time zone v_timezone;

  if date_trunc('minute',v_roundtrip) is distinct from date_trunc('minute',p_local) then
    raise exception 'workflow_schedule_local_time_invalid' using errcode='22023';
  end if;

  if exists(
    select 1
    from generate_series(-180,180) as delta(minutes)
    where delta.minutes<>0
      and date_trunc(
        'minute',
        (v_run_at + delta.minutes * interval '1 minute') at time zone v_timezone
      )=date_trunc('minute',p_local)
  ) then
    raise exception 'workflow_schedule_local_time_ambiguous' using errcode='22023';
  end if;

  return v_run_at;
end;
$workflow_local_to_utc$;

revoke all on function private.workflow_local_time_to_unique_utc_v1(timestamp,text)
  from public,anon,authenticated;

create or replace function private.workflow_recurring_local_occurrence_v1(
  p_anchor_local timestamp,
  p_recurrence text,
  p_custom_every integer,
  p_custom_unit text,
  p_occurrence_index bigint
)
returns timestamp
language plpgsql
immutable
security definer
set search_path=''
as $workflow_recurring_occurrence$
declare
  v_index bigint:=coalesce(p_occurrence_index,0);
  v_days bigint;
  v_months bigint;
  v_target_month date;
  v_last_day date;
  v_anchor_day integer;
  v_target_day integer;
  v_time time;
begin
  if p_anchor_local is null or v_index<0 or v_index>1000000 then
    raise exception 'workflow_recurrence_occurrence_invalid' using errcode='22023';
  end if;

  if v_index=0 then
    return p_anchor_local;
  end if;

  if p_recurrence='weekly' then
    v_days:=7*v_index;
  elsif p_recurrence='biweekly' then
    v_days:=14*v_index;
  elsif p_recurrence='monthly' then
    v_months:=v_index;
  elsif p_recurrence='custom' then
    if p_custom_every is null or p_custom_every<1 or p_custom_every>365 then
      raise exception 'workflow_custom_recurrence_invalid' using errcode='22023';
    end if;

    if p_custom_unit='day' then
      v_days:=p_custom_every::bigint*v_index;
    elsif p_custom_unit='week' then
      v_days:=7*p_custom_every::bigint*v_index;
    elsif p_custom_unit='month' then
      v_months:=p_custom_every::bigint*v_index;
    else
      raise exception 'workflow_custom_recurrence_invalid' using errcode='22023';
    end if;
  else
    raise exception 'workflow_recurrence_invalid' using errcode='22023';
  end if;

  if v_days is not null then
    return p_anchor_local + (v_days::text||' days')::interval;
  end if;

  if v_months is null or v_months>12000000 then
    raise exception 'workflow_recurrence_occurrence_invalid' using errcode='22023';
  end if;

  v_target_month:=(
    date_trunc('month',p_anchor_local)::date
    + (v_months::text||' months')::interval
  )::date;
  v_last_day:=(v_target_month + interval '1 month - 1 day')::date;
  v_anchor_day:=extract(day from p_anchor_local)::integer;
  v_target_day:=least(v_anchor_day,extract(day from v_last_day)::integer);
  v_time:=p_anchor_local::time;

  return (v_target_month + (v_target_day-1))::timestamp + v_time;
end;
$workflow_recurring_occurrence$;

revoke all on function private.workflow_recurring_local_occurrence_v1(
  timestamp,text,integer,text,bigint
) from public,anon,authenticated;

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
  v_timezone text;
  v_utc text;
  v_local text;
  v_run_at timestamptz;
  v_roundtrip text;
begin
  v_spec:=private.workflow_sanitize_authoring_spec_v2(p_spec);
  v_trigger_type:=nullif(v_spec->>'triggerType','');

  if v_trigger_type not in ('scheduled_once','recurring') then
    return v_spec || jsonb_build_object(
      'scheduledTimezone','',
      'scheduledAtUtc',''
    );
  end if;

  -- v2 limpia scheduledAt para recurring. Recuperamos la primera ejecución
  -- desde la entrada original antes de congelar el spec.
  if v_trigger_type='recurring' then
    v_local:=nullif(btrim(coalesce(p_spec->>'scheduledAt','')),'');
    if v_local is null
      or v_local !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$' then
      raise exception 'workflow_scheduled_at_invalid' using errcode='22023';
    end if;
    v_spec:=jsonb_set(v_spec,'{scheduledAt}',to_jsonb(v_local),true);
  else
    v_local:=nullif(btrim(coalesce(v_spec->>'scheduledAt','')),'');
  end if;

  v_timezone:=nullif(btrim(coalesce(p_spec->>'scheduledTimezone','')),'');
  v_utc:=nullif(btrim(coalesce(p_spec->>'scheduledAtUtc','')),'');

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

  v_roundtrip:=to_char(
    v_run_at at time zone v_timezone,
    'YYYY-MM-DD"T"HH24:MI'
  );

  if v_local is null or v_roundtrip is distinct from v_local then
    raise exception 'workflow_schedule_time_mismatch' using errcode='22023';
  end if;

  perform private.workflow_local_time_to_unique_utc_v1(
    replace(v_local,'T',' ')::timestamp,
    v_timezone
  );

  return v_spec || jsonb_build_object(
    'scheduledTimezone',v_timezone,
    'scheduledAtUtc',v_utc
  );
end;
$workflow_sanitize_v3$;

revoke all on function private.workflow_sanitize_authoring_spec_v3(jsonb)
  from public,anon,authenticated;

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
      (p_spec->>'triggerType') in ('manual','event')
      or (
        (p_spec->>'triggerType') in ('scheduled_once','recurring')
        and coalesce(p_spec->>'scheduledAt','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$'
        and char_length(btrim(coalesce(p_spec->>'scheduledTimezone',''))) between 1 and 80
        and coalesce(p_spec->>'scheduledAtUtc','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{3})?Z$'
        and (
          (p_spec->>'triggerType')='scheduled_once'
          or (
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
    )
    or (p_spec->>'assignmentType') not in ('property_responsible','active_occupants_rotation','fixed_person','role','manual')
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

-- Amplía el núcleo único de ejecución con trigger_kind recurring.
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

  if p_trigger_kind not in ('manual_now','scheduled_once','recurring') then
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

create or replace function private.workflow_scheduled_application_requires_schedule_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $workflow_schedule_required$
declare
  v_trigger_type text;
begin
  if new.status<>'configured' then
    return new;
  end if;

  select nullif(v.spec->>'triggerType','')
  into v_trigger_type
  from public.workflow_definition_versions_v2 v
  where v.id=new.definition_version_id
    and v.definition_id=new.definition_id
    and v.organization_id=new.organization_id;

  if v_trigger_type in ('scheduled_once','recurring')
    and not exists(
      select 1
      from public.workflow_application_schedules_v2 s
      where s.application_id=new.id
        and s.definition_id=new.definition_id
        and s.definition_version_id=new.definition_version_id
        and s.organization_id=new.organization_id
        and s.schedule_kind=v_trigger_type
        and s.status in ('active','completed','blocked')
    ) then
    raise exception 'workflow_scheduled_configuration_required' using errcode='55000';
  end if;

  return new;
end;
$workflow_schedule_required$;

revoke all on function private.workflow_scheduled_application_requires_schedule_v1()
  from public,anon,authenticated;

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

  if new.trigger_kind='scheduled_once' and v_spec_trigger<>'scheduled_once' then
    raise exception 'workflow_scheduled_trigger_mismatch' using errcode='55000';
  end if;

  if new.trigger_kind='recurring' and v_spec_trigger<>'recurring' then
    raise exception 'workflow_recurring_trigger_mismatch' using errcode='55000';
  end if;

  return new;
end;
$workflow_trigger_guard$;

revoke all on function private.workflow_execution_trigger_kind_guard_v1()
  from public,anon,authenticated;

create or replace function private.workflow_configure_application_schedule_v1(
  p_application_id uuid,
  p_schedule_timezone text,
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
  v_local timestamp;
  v_run_at timestamptz;
  v_timezone text;
  v_requested_timezone text:=nullif(btrim(p_schedule_timezone),'');
  v_utc_text text;
  v_resolved uuid;
  v_schedule public.workflow_application_schedules_v2;
begin
  select wa.*
  into v_app
  from public.workflow_applications_v2 wa
  where wa.id=p_application_id
  for update;

  if v_app.id is null then
    raise exception 'workflow_application_not_found' using errcode='P0002';
  end if;

  select wv.spec
  into v_spec
  from public.workflow_definition_versions_v2 wv
  where wv.id=v_app.definition_version_id
    and wv.definition_id=v_app.definition_id
    and wv.organization_id=v_app.organization_id;

  if v_spec is null then
    raise exception 'workflow_application_version_not_found' using errcode='55000';
  end if;

  v_trigger_type:=nullif(v_spec->>'triggerType','');

  if v_trigger_type not in ('scheduled_once','recurring') then
    delete from public.workflow_application_schedules_v2
    where application_id=p_application_id;
    return null;
  end if;

  if p_actor_user_id is null then
    raise exception 'workflow_schedule_actor_required' using errcode='22023';
  end if;

  v_timezone:=nullif(btrim(v_spec->>'scheduledTimezone'),'');
  if v_timezone is null
    or not exists(
      select 1 from pg_catalog.pg_timezone_names tz where tz.name=v_timezone
    ) then
    raise exception 'workflow_schedule_timezone_invalid' using errcode='22023';
  end if;

  if v_requested_timezone is distinct from v_timezone then
    raise exception 'workflow_schedule_timezone_conflict' using errcode='22023';
  end if;

  v_local_text:=nullif(btrim(v_spec->>'scheduledAt'),'');
  v_utc_text:=nullif(btrim(v_spec->>'scheduledAtUtc'),'');

  if v_local_text is null
    or v_local_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$' then
    raise exception 'workflow_scheduled_at_invalid' using errcode='22023';
  end if;

  if v_utc_text is null
    or v_utc_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{3})?Z$' then
    raise exception 'workflow_scheduled_utc_invalid' using errcode='22023';
  end if;

  v_local:=replace(v_local_text,'T',' ')::timestamp;
  v_run_at:=private.workflow_local_time_to_unique_utc_v1(v_local,v_timezone);

  if v_run_at is distinct from v_utc_text::timestamptz then
    raise exception 'workflow_schedule_time_mismatch' using errcode='22023';
  end if;

  if v_run_at<=now() then
    raise exception 'workflow_schedule_must_be_future' using errcode='22023';
  end if;

  if v_trigger_type='recurring' then
    perform private.workflow_recurring_local_occurrence_v1(
      v_local,
      nullif(v_spec->>'recurrence',''),
      case
        when coalesce(v_spec->>'customEvery','') ~ '^[0-9]+$'
          then (v_spec->>'customEvery')::integer
        else null
      end,
      nullif(v_spec->>'customUnit',''),
      0
    );
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
    v_resolved:=null;
  else
    raise exception 'workflow_schedule_assignment_not_supported' using errcode='0A000';
  end if;

  insert into public.workflow_application_schedules_v2(
    application_id,definition_id,definition_version_id,organization_id,
    schedule_kind,schedule_timezone,next_run_at,scheduled_assigned_user_id,
    status,last_attempt_at,last_execution_id,last_error_code,last_error_at,
    created_by,created_at,updated_at,occurrence_index
  ) values (
    v_app.id,v_app.definition_id,v_app.definition_version_id,v_app.organization_id,
    v_trigger_type,v_timezone,v_run_at,
    case when v_assignment_type='manual' then v_resolved else null end,
    'active',null,null,null,null,
    p_actor_user_id,now(),now(),0
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
      occurrence_index=0,
      updated_at=now()
  returning * into v_schedule;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_app.organization_id,p_actor_user_id,'workflow_schedule_configured',
    'workflow_application',v_app.id::text,'success',
    jsonb_build_object(
      'schedule_kind',v_trigger_type,
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
  v_spec jsonb;
  v_execution_id uuid;
  v_execution_status text;
  v_execution_assignee uuid;
  v_execution_created_at timestamptz;
  v_created_new boolean;
  v_key text;
  v_event_key text;
  v_processed integer:=0;
  v_next_index bigint;
  v_anchor_local timestamp;
  v_next_local timestamp;
  v_next_run_at timestamptz;
  v_custom_every integer;
begin
  for v_schedule in
    select s.*
    from public.workflow_application_schedules_v2 s
    join public.workflow_applications_v2 a on a.id=s.application_id
    join public.workflow_definitions_v2 d on d.id=s.definition_id
    where s.status='active'
      and s.schedule_kind in ('scheduled_once','recurring')
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

    v_key:=v_schedule.schedule_kind||':'||v_schedule.application_id::text||':'||
      extract(epoch from v_schedule.next_run_at)::bigint::text;
    v_event_key:='blocked:'||
      extract(epoch from v_schedule.next_run_at)::bigint::text;

    begin
      select x.execution_id,x.status,x.assigned_user_id,x.created_at,x.created_new
      into v_execution_id,v_execution_status,v_execution_assignee,
           v_execution_created_at,v_created_new
      from private.workflow_execute_application_internal_v1(
        v_schedule.application_id,
        v_key,
        v_schedule.scheduled_assigned_user_id,
        v_schedule.schedule_kind,
        v_schedule.created_by
      ) x
      limit 1;

      v_processed:=v_processed+1;

      if v_schedule.schedule_kind='scheduled_once' then
        update public.workflow_application_schedules_v2
        set status='completed',
            last_execution_id=v_execution_id,
            last_error_code=null,
            last_error_at=null,
            updated_at=now()
        where application_id=v_schedule.application_id;
      else
        -- La ejecución actual ya es válida. El cálculo de la siguiente
        -- ocurrencia va en un sub-bloque independiente: si una futura hora es
        -- ambigua/inexistente no se revierte la tarea recién creada.
        begin
          select v.spec
          into v_spec
          from public.workflow_definition_versions_v2 v
          where v.id=v_schedule.definition_version_id
            and v.definition_id=v_schedule.definition_id
            and v.organization_id=v_schedule.organization_id;

          if v_spec is null then
            raise exception 'workflow_application_version_not_found' using errcode='55000';
          end if;

          v_anchor_local:=replace(v_spec->>'scheduledAt','T',' ')::timestamp;
          v_next_index:=v_schedule.occurrence_index+1;
          v_custom_every:=case
            when coalesce(v_spec->>'customEvery','') ~ '^[0-9]+$'
              then (v_spec->>'customEvery')::integer
            else null
          end;

          v_next_local:=private.workflow_recurring_local_occurrence_v1(
            v_anchor_local,
            nullif(v_spec->>'recurrence',''),
            v_custom_every,
            nullif(v_spec->>'customUnit',''),
            v_next_index
          );
          v_next_run_at:=private.workflow_local_time_to_unique_utc_v1(
            v_next_local,
            v_schedule.schedule_timezone
          );

          update public.workflow_application_schedules_v2
          set status='active',
              occurrence_index=v_next_index,
              next_run_at=v_next_run_at,
              last_execution_id=v_execution_id,
              last_error_code=null,
              last_error_at=null,
              updated_at=now()
          where application_id=v_schedule.application_id;

          insert into public.audit_log_v2(
            organization_id,actor_user_id,action,entity_type,entity_id,result,details
          ) values (
            v_schedule.organization_id,v_schedule.created_by,
            'workflow_recurring_advanced','workflow_application',
            v_schedule.application_id::text,'success',
            jsonb_build_object(
              'execution_id',v_execution_id,
              'occurrence_index',v_next_index,
              'next_run_at',v_next_run_at
            )
          );

        exception when others then
          update public.workflow_application_schedules_v2
          set status='blocked',
              last_execution_id=v_execution_id,
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
            'Recurrencia bloqueada',
            'La última tarea se creó, pero no se pudo calcular la siguiente fecha. Revisa el flujo.',
            'pending',true,false,
            'workflow_schedule',v_schedule.application_id,v_event_key||':next'
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
              'schedule_kind','recurring',
              'execution_id',v_execution_id,
              'sqlstate',sqlstate
            )
          );
        end;
      end if;

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
        case
          when v_schedule.schedule_kind='recurring'
            then 'Recurrencia bloqueada'
          else 'Programación bloqueada'
        end,
        'No se pudo crear la tarea programada. Revisa el flujo y su destino.',
        'pending',true,false,
        'workflow_schedule',v_schedule.application_id,v_event_key
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

comment on function private.workflow_recurring_local_occurrence_v1(
  timestamp,text,integer,text,bigint
) is
  'Calcula cada ocurrencia recurrente desde el ancla local original para evitar deriva, incluido fin de mes.';

comment on function private.process_due_workflow_schedules_v1(timestamptz) is
  'Procesa scheduled_once y recurring con SKIP LOCKED, idempotencia por instante y avance recurrente en hora local.';
