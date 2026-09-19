-- GestionPisos · Flujos recurrentes
-- Reutiliza workflow_application_schedules_v2 y el cron ya desplegado.
-- La primera ejecución es explícita; las siguientes se calculan desde esa ancla.

alter table public.workflow_application_schedules_v2
  drop constraint if exists workflow_application_schedules_v2_schedule_kind_check;

alter table public.workflow_application_schedules_v2
  add constraint workflow_application_schedules_v2_schedule_kind_check
  check (schedule_kind in ('scheduled_once','recurring'));

alter table public.workflow_application_schedules_v2
  add column if not exists next_occurrence_index bigint not null default 0,
  add column if not exists execution_count bigint not null default 0,
  add column if not exists last_scheduled_for timestamptz;

alter table public.workflow_application_schedules_v2
  drop constraint if exists workflow_application_schedules_v2_occurrence_counters_check;

alter table public.workflow_application_schedules_v2
  add constraint workflow_application_schedules_v2_occurrence_counters_check
  check (next_occurrence_index>=0 and execution_count>=0);

alter table public.workflow_executions_v2
  drop constraint if exists workflow_executions_v2_trigger_kind_check;

alter table public.workflow_executions_v2
  add constraint workflow_executions_v2_trigger_kind_check
  check (trigger_kind in ('manual_now','scheduled_once','recurring'));

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
        (p_spec->>'triggerType')='scheduled_once'
        and coalesce(p_spec->>'scheduledAt','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$'
        and char_length(btrim(coalesce(p_spec->>'scheduledTimezone',''))) between 1 and 80
        and coalesce(p_spec->>'scheduledAtUtc','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{3})?Z$'
      )
      or (
        (p_spec->>'triggerType')='recurring'
        and coalesce(p_spec->>'scheduledAt','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}
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
        and char_length(btrim(coalesce(p_spec->>'scheduledTimezone',''))) between 1 and 80
        and coalesce(p_spec->>'scheduledAtUtc','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{3})?Z
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
        and (
          (p_spec->>'recurrence') in ('weekly','biweekly','monthly')
          or (
            (p_spec->>'recurrence')='custom'
            and case
              when coalesce(p_spec->>'customEvery','') ~ '^[0-9]+
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
                then (p_spec->>'customEvery')::integer between 1 and 365
              else false
            end
            and (p_spec->>'customUnit') in ('day','week','month')
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

create or replace function private.workflow_recurring_occurrence_v1(
  p_spec jsonb,
  p_occurrence_index bigint
)
returns timestamptz
language plpgsql
stable
security definer
set search_path=''
as $workflow_recurring_occurrence$
declare
  v_index bigint:=coalesce(p_occurrence_index,-1);
  v_timezone text:=nullif(btrim(coalesce(p_spec->>'scheduledTimezone','')),'');
  v_anchor_text text:=nullif(btrim(coalesce(p_spec->>'scheduledAt','')),'');
  v_anchor_utc_text text:=nullif(btrim(coalesce(p_spec->>'scheduledAtUtc','')),'');
  v_recurrence text:=nullif(p_spec->>'recurrence','');
  v_custom_every integer;
  v_custom_unit text:=nullif(p_spec->>'customUnit','');
  v_anchor_local timestamp;
  v_candidate_local timestamp;
  v_candidate_utc timestamptz;
  v_months bigint;
  v_month_start date;
  v_last_day date;
  v_target_day integer;
  v_roundtrip text;
begin
  if v_index<0 or v_index>1000000 then
    raise exception 'workflow_recurring_occurrence_index_invalid' using errcode='22023';
  end if;

  if v_timezone is null
    or not exists(select 1 from pg_catalog.pg_timezone_names tz where tz.name=v_timezone) then
    raise exception 'workflow_schedule_timezone_invalid' using errcode='22023';
  end if;

  if v_anchor_text is null
    or v_anchor_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$' then
    raise exception 'workflow_scheduled_at_invalid' using errcode='22023';
  end if;

  v_anchor_local:=replace(v_anchor_text,'T',' ')::timestamp;

  if v_index=0 then
    begin
      v_candidate_utc:=v_anchor_utc_text::timestamptz;
    exception when others then
      raise exception 'workflow_scheduled_utc_invalid' using errcode='22023';
    end;
    v_candidate_local:=v_anchor_local;
  else
    if v_recurrence='weekly' then
      v_candidate_local:=v_anchor_local + (v_index::double precision * 7.0) * interval '1 day';
    elsif v_recurrence='biweekly' then
      v_candidate_local:=v_anchor_local + (v_index::double precision * 14.0) * interval '1 day';
    elsif v_recurrence='monthly' then
      v_months:=v_index;
    elsif v_recurrence='custom' then
      if coalesce(p_spec->>'customEvery','') !~ '^[0-9]+$' then
        raise exception 'workflow_custom_recurrence_invalid' using errcode='22023';
      end if;
      v_custom_every:=(p_spec->>'customEvery')::integer;
      if v_custom_every<1 or v_custom_every>365
        or v_custom_unit not in ('day','week','month') then
        raise exception 'workflow_custom_recurrence_invalid' using errcode='22023';
      end if;

      if v_custom_unit='day' then
        v_candidate_local:=v_anchor_local
          + (v_index::double precision * v_custom_every::double precision) * interval '1 day';
      elsif v_custom_unit='week' then
        v_candidate_local:=v_anchor_local
          + (v_index::double precision * v_custom_every::double precision * 7.0) * interval '1 day';
      else
        v_months:=v_index*v_custom_every::bigint;
      end if;
    else
      raise exception 'workflow_recurrence_invalid' using errcode='22023';
    end if;

    if v_months is not null then
      if v_months>120000 then
        raise exception 'workflow_recurring_occurrence_range_invalid' using errcode='22023';
      end if;
      v_month_start:=(
        date_trunc('month',v_anchor_local)
        + make_interval(months=>v_months::integer)
      )::date;
      v_last_day:=(v_month_start + interval '1 month - 1 day')::date;
      v_target_day:=least(
        extract(day from v_anchor_local)::integer,
        extract(day from v_last_day)::integer
      );
      v_candidate_local:=
        (v_month_start + (v_target_day-1))::date + v_anchor_local::time;
    end if;

    v_candidate_utc:=v_candidate_local at time zone v_timezone;
  end if;

  v_roundtrip:=to_char(
    v_candidate_utc at time zone v_timezone,
    'YYYY-MM-DD"T"HH24:MI'
  );

  if v_roundtrip is distinct from to_char(v_candidate_local,'YYYY-MM-DD"T"HH24:MI') then
    raise exception 'workflow_recurring_local_time_invalid' using errcode='22023';
  end if;

  if exists(
    select 1
    from generate_series(-180,180) as delta(minutes)
    where delta.minutes<>0
      and to_char(
        (v_candidate_utc + delta.minutes * interval '1 minute') at time zone v_timezone,
        'YYYY-MM-DD"T"HH24:MI'
      )=to_char(v_candidate_local,'YYYY-MM-DD"T"HH24:MI')
  ) then
    raise exception 'workflow_recurring_local_time_ambiguous' using errcode='22023';
  end if;

  return v_candidate_utc;
end;
$workflow_recurring_occurrence$;

revoke all on function private.workflow_recurring_occurrence_v1(jsonb,bigint)
  from public,anon,authenticated;


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
  v_run_at timestamptz;
  v_roundtrip_text text;
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
      select 1
      from pg_catalog.pg_timezone_names tz
      where tz.name=v_timezone
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
    -- Se resuelve al llegar la hora real. No bloqueamos hoy una programación
    -- futura porque todavía no exista un responsable operativo.
    v_resolved:=null;
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
    v_trigger_type,v_timezone,v_run_at,
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
      next_occurrence_index=0,
      execution_count=0,
      last_scheduled_for=null,
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
  v_candidate_index bigint;
  v_next_run timestamptz;
  v_skipped integer;
  v_processed integer:=0;
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
      v_schedule.next_occurrence_index::text||':'||
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

      if v_schedule.schedule_kind='scheduled_once' then
        update public.workflow_application_schedules_v2
        set status='completed',
            last_execution_id=v_execution_id,
            last_scheduled_for=v_schedule.next_run_at,
            execution_count=v_schedule.execution_count+1,
            last_error_code=null,
            last_error_at=null,
            updated_at=now()
        where application_id=v_schedule.application_id;
      else
        select wv.spec
        into v_spec
        from public.workflow_definition_versions_v2 wv
        where wv.id=v_schedule.definition_version_id
          and wv.definition_id=v_schedule.definition_id
          and wv.organization_id=v_schedule.organization_id;

        if v_spec is null then
          raise exception 'workflow_application_version_not_found' using errcode='55000';
        end if;

        v_candidate_index:=v_schedule.next_occurrence_index+1;
        v_skipped:=0;

        begin
          loop
            if v_skipped>10000 then
              raise exception 'workflow_recurring_catchup_limit' using errcode='54000';
            end if;

            v_next_run:=private.workflow_recurring_occurrence_v1(
              v_spec,v_candidate_index
            );

            exit when v_next_run>p_now;
            v_candidate_index:=v_candidate_index+1;
            v_skipped:=v_skipped+1;
          end loop;

          update public.workflow_application_schedules_v2
          set status='active',
              next_occurrence_index=v_candidate_index,
              next_run_at=v_next_run,
              last_execution_id=v_execution_id,
              last_scheduled_for=v_schedule.next_run_at,
              execution_count=v_schedule.execution_count+1,
              last_error_code=null,
              last_error_at=null,
              updated_at=now()
          where application_id=v_schedule.application_id;

          if v_skipped>0 then
            insert into public.audit_log_v2(
              organization_id,actor_user_id,action,entity_type,entity_id,result,details
            ) values (
              v_schedule.organization_id,v_schedule.created_by,
              'workflow_recurring_occurrences_skipped','workflow_application',
              v_schedule.application_id::text,'success',
              jsonb_build_object(
                'skipped_count',v_skipped,
                'last_scheduled_for',v_schedule.next_run_at,
                'next_occurrence_index',v_candidate_index,
                'next_run_at',v_next_run
              )
            );
          end if;

        exception when others then
          update public.workflow_application_schedules_v2
          set status='blocked',
              last_execution_id=v_execution_id,
              last_scheduled_for=v_schedule.next_run_at,
              execution_count=v_schedule.execution_count+1,
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
            'Programación recurrente bloqueada',
            'La tarea actual se creó, pero no se pudo calcular una próxima ejecución válida. Revisa el flujo.',
            'pending',true,false,
            'workflow_schedule',v_schedule.application_id,
            'blocked-next:'||v_candidate_index::text
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
              'phase','next_occurrence',
              'last_scheduled_for',v_schedule.next_run_at,
              'next_occurrence_index',v_candidate_index,
              'sqlstate',sqlstate
            )
          );
        end;
      end if;

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
          'phase','execution',
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
  if p_execute and coalesce(p_spec->>'triggerType','') in ('scheduled_once','recurring') then
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
    p_schedule_timezone,
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
  if p_execute and coalesce(p_spec->>'triggerType','') in ('scheduled_once','recurring') then
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
    p_schedule_timezone,
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

  if p_execute and coalesce(v_trigger_type,'') in ('scheduled_once','recurring') then
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
    p_schedule_timezone,
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

comment on function private.workflow_recurring_occurrence_v1(jsonb,bigint) is
  'Calcula una ocurrencia recurrente desde el ancla local original, preservando hora/zona y evitando deriva mensual.';
