-- WF-01 · Generic assignment rules for the shared workflow engine.
-- The application row is locked by workflow_execute_application_internal_v1
-- before calling the resolver. That serializes role/rotation decisions per app.
-- Existing executions retain their spec_snapshot and assigned_user_id.

-- WF-01: candidate eligibility follows current DB relationships, never JWT role claims.
create or replace function private.workflow_assignee_eligible_v1(
  p_organization_id uuid,
  p_scope_type text,
  p_property_id uuid,
  p_room_id uuid,
  p_occupancy_id uuid,
  p_user_id uuid,
  p_required_role text default null
)
returns boolean
language sql
stable
security definer
set search_path=''
as $workflow_eligible$
  select p_user_id is not null
    and (
      (
        p_required_role is distinct from 'tenant'
        and exists(
          select 1
          from public.user_roles ur
          join public.profiles pr
            on pr.user_id=ur.user_id
           and pr.organization_id=p_organization_id
           and pr.status='active'
           and pr.archived_at is null
          where ur.user_id=p_user_id
            and ur.organization_id=p_organization_id
            and ur.role in ('admin','employee')
            and ur.revoked_at is null
            and (p_required_role is null or ur.role::text=p_required_role)
            and (
              p_scope_type='organization'
              or (
                p_scope_type in ('property','room')
                and exists(
                  select 1
                  from public.property_staff_access_v3 a
                  where a.organization_id=p_organization_id
                    and a.property_id=p_property_id
                    and a.employee_user_id=p_user_id
                    and a.assignment_type in ('responsible','access')
                    and a.revoked_at is null
                    and a.valid_from<=now()
                    and (a.valid_until is null or a.valid_until>now())
                )
              )
            )
        )
      )
      or (
        p_required_role is distinct from 'admin'
        and p_required_role is distinct from 'employee'
        and p_scope_type in ('property','room','occupancy')
        and exists(
          select 1
          from public.occupancies_v2 o
          join public.tenants_v2 t
            on t.id=o.tenant_id
           and t.organization_id=o.organization_id
           and t.user_id=p_user_id
           and t.status='active'
           and t.archived_at is null
          join public.user_roles ur
            on ur.user_id=p_user_id
           and ur.organization_id=p_organization_id
           and ur.role='tenant'
           and ur.revoked_at is null
          where o.organization_id=p_organization_id
            and o.property_id=p_property_id
            and (p_scope_type<>'room' or o.room_id=p_room_id)
            and (p_scope_type<>'occupancy' or o.id=p_occupancy_id)
            and o.user_id=p_user_id
            and o.status='active'
            and o.starts_on is not null
            and o.starts_on<=current_date
            and (o.ends_on is null or o.ends_on>=current_date)
        )
      )
    );
$workflow_eligible$;

revoke all on function private.workflow_assignee_eligible_v1(
  uuid,text,uuid,uuid,uuid,uuid,text
) from public,anon,authenticated,service_role;

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
  v_assignment_type text;
  v_assignment_user_id text;
  v_assignment_role text;
begin
  v_spec:=private.workflow_sanitize_authoring_spec_v2(p_spec);
  v_trigger_type:=nullif(v_spec->>'triggerType','');
  v_assignment_type:=nullif(v_spec->>'assignmentType','');
  v_assignment_user_id:=nullif(btrim(coalesce(p_spec->>'assignmentUserId','')),'');
  v_assignment_role:=nullif(btrim(coalesce(p_spec->>'assignmentRole','')),'');

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
      (p_spec->>'triggerType') in ('manual','event')
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

create or replace function private.workflow_resolve_execution_assignee_v1(
  p_application_id uuid,
  p_requested_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_org uuid;
  v_scope_type text;
  v_property_id uuid;
  v_room_id uuid;
  v_occupancy_id uuid;
  v_spec jsonb;
  v_assignment_type text;
  v_assigned_user uuid;
  v_fixed_id text;
  v_role text;
begin
  select
    wa.organization_id,
    wa.scope_type,
    wa.property_id,
    wa.room_id,
    wa.occupancy_id,
    wv.spec
  into
    v_org,
    v_scope_type,
    v_property_id,
    v_room_id,
    v_occupancy_id,
    v_spec
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

    -- Organización no tiene un destino residencial concreto. Se limita a
    -- personal interno activo; ROOT no es ejecutor operativo por defecto.
    if v_scope_type='organization'
      and exists(
        select 1
        from public.user_roles ur
        where ur.user_id=p_requested_user_id
          and ur.organization_id=v_org
          and ur.role in ('admin','employee')
          and ur.revoked_at is null
      )
    then
      v_assigned_user:=p_requested_user_id;

    -- Piso/Habitación: personal con asociación vigente al piso. La asignación
    -- explícita de la tarea concede capacidad sobre ESA tarea, aunque el acceso
    -- general del empleado al piso sea de lectura.
    elsif v_scope_type in ('property','room')
      and v_property_id is not null
      and exists(
        select 1
        from public.property_staff_access_v3 a
        join public.user_roles ur
          on ur.user_id=a.employee_user_id
         and ur.organization_id=v_org
         and ur.role in ('admin','employee')
         and ur.revoked_at is null
        where a.property_id=v_property_id
          and a.employee_user_id=p_requested_user_id
          and a.assignment_type in ('responsible','access')
          and a.revoked_at is null
          and (a.valid_until is null or a.valid_until>now())
      )
    then
      v_assigned_user:=p_requested_user_id;

    -- Piso/Habitación: inquilino con identidad Auth y ocupación vigente dentro
    -- del destino. Para habitación debe pertenecer exactamente a esa habitación.
    elsif v_scope_type in ('property','room')
      and v_property_id is not null
      and exists(
        select 1
        from public.occupancies_v2 o
        join public.tenants_v2 t
          on t.id=o.tenant_id
         and t.organization_id=o.organization_id
        where o.organization_id=v_org
          and o.property_id=v_property_id
          and (v_scope_type<>'room' or o.room_id=v_room_id)
          and o.status='active'
          and o.starts_on is not null
          and o.starts_on<=current_date
          and (o.ends_on is null or o.ends_on>=current_date)
          and o.user_id=p_requested_user_id
          and t.user_id=p_requested_user_id
          and t.status='active'
          and t.archived_at is null
      )
    then
      v_assigned_user:=p_requested_user_id;

    -- Ocupación/Inquilino: solo el propio inquilino activo del destino.
    elsif v_scope_type='occupancy'
      and v_occupancy_id is not null
      and exists(
        select 1
        from public.occupancies_v2 o
        join public.tenants_v2 t
          on t.id=o.tenant_id
         and t.organization_id=o.organization_id
        where o.id=v_occupancy_id
          and o.organization_id=v_org
          and o.property_id=v_property_id
          and o.status='active'
          and o.starts_on is not null
          and o.starts_on<=current_date
          and (o.ends_on is null or o.ends_on>=current_date)
          and o.user_id=p_requested_user_id
          and t.user_id=p_requested_user_id
          and t.status='active'
          and t.archived_at is null
      )
    then
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

  elsif v_assignment_type='fixed_person' then
    if p_requested_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved' using errcode='22023';
    end if;

    v_fixed_id:=nullif(v_spec->>'assignmentUserId','');
    if v_fixed_id is null
      or v_fixed_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'workflow_fixed_person_invalid' using errcode='22023';
    end if;

    if not private.workflow_assignee_eligible_v1(
      v_org,v_scope_type,v_property_id,v_room_id,v_occupancy_id,
      v_fixed_id::uuid,null
    ) then
      raise exception 'workflow_fixed_person_unavailable' using errcode='55000';
    end if;
    v_assigned_user:=v_fixed_id::uuid;

  elsif v_assignment_type='role' then
    if p_requested_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved' using errcode='22023';
    end if;

    v_role:=nullif(v_spec->>'assignmentRole','');
    if v_role not in ('admin','employee','tenant') or v_role is null
      or (v_role='tenant' and v_scope_type='organization') then
      raise exception 'workflow_assignment_role_invalid' using errcode='22023';
    end if;

    select ur.user_id
    into v_assigned_user
    from public.user_roles ur
    where ur.organization_id=v_org
      and ur.role::text=v_role
      and ur.revoked_at is null
      and private.workflow_assignee_eligible_v1(
        v_org,v_scope_type,v_property_id,v_room_id,v_occupancy_id,
        ur.user_id,v_role
      )
    order by (
      select count(*)
      from public.workflow_executions_v2 e
      where e.application_id=p_application_id
        and e.assigned_user_id=ur.user_id
    ), (
      select max(e.created_at)
      from public.workflow_executions_v2 e
      where e.application_id=p_application_id
        and e.assigned_user_id=ur.user_id
    ) nulls first, ur.user_id
    limit 1;

    if v_assigned_user is null then
      raise exception 'workflow_assignment_role_unavailable' using errcode='55000';
    end if;

  elsif v_assignment_type='active_occupants_rotation' then
    if p_requested_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved' using errcode='22023';
    end if;
    if v_property_id is null or v_scope_type='organization' then
      raise exception 'workflow_rotation_scope_required' using errcode='22023';
    end if;

    select candidates.user_id
    into v_assigned_user
    from (
      select distinct o.user_id
      from public.occupancies_v2 o
      where o.organization_id=v_org
        and o.property_id=v_property_id
        and o.user_id is not null
        and (v_scope_type<>'room' or o.room_id=v_room_id)
        and (v_scope_type<>'occupancy' or o.id=v_occupancy_id)
    ) candidates
    where private.workflow_assignee_eligible_v1(
      v_org,v_scope_type,v_property_id,v_room_id,v_occupancy_id,
      candidates.user_id,'tenant'
    )
    order by (
      select count(*)
      from public.workflow_executions_v2 e
      where e.application_id=p_application_id
        and e.assigned_user_id=candidates.user_id
    ), (
      select max(e.created_at)
      from public.workflow_executions_v2 e
      where e.application_id=p_application_id
        and e.assigned_user_id=candidates.user_id
    ) nulls first, candidates.user_id
    limit 1;

    if v_assigned_user is null then
      raise exception 'workflow_rotation_no_active_occupants' using errcode='55000';
    end if;
  else
    raise exception 'workflow_assignment_invalid' using errcode='22023';
  end if;

  return v_assigned_user;
end;
$$;

revoke all on function private.workflow_resolve_execution_assignee_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

create or replace function public.workflow_execution_actor_current_v1(
  p_execution_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_execution public.workflow_executions_v2;
begin
  if v_actor is null or p_execution_id is null then
    return false;
  end if;

  select *
  into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id;

  if v_execution.id is null
    or v_execution.assigned_user_id is distinct from v_actor then
    return false;
  end if;

  -- Asignación automática al responsable: debe seguir siendo el responsable
  -- operativo vigente del piso. Si se transfiere la responsabilidad, la tarea
  -- histórica permanece pero el antiguo responsable deja de actuar sobre ella.
  if v_execution.assignment_type='property_responsible' then
    return exists(
      select 1
      from public.property_staff_access_v3 a
      join public.user_roles ur
        on ur.user_id=a.employee_user_id
       and ur.organization_id=v_execution.organization_id
       and ur.role in ('admin','employee')
       and ur.revoked_at is null
      where a.property_id=v_execution.property_id
        and a.employee_user_id=v_actor
        and a.assignment_type='responsible'
        and a.can_write=true
        and a.revoked_at is null
        and (a.valid_until is null or a.valid_until>now())
    );
  end if;

  if v_execution.assignment_type='fixed_person' then
    return v_execution.spec_snapshot->>'assignmentUserId'=v_actor::text
      and private.workflow_assignee_eligible_v1(
        v_execution.organization_id,v_execution.scope_type,
        v_execution.property_id,v_execution.room_id,v_execution.occupancy_id,
        v_actor,null
      );
  end if;

  if v_execution.assignment_type='role' then
    if coalesce(v_execution.spec_snapshot->>'assignmentRole','')
      not in ('admin','employee','tenant') then
      return false;
    end if;
    return private.workflow_assignee_eligible_v1(
      v_execution.organization_id,v_execution.scope_type,
      v_execution.property_id,v_execution.room_id,v_execution.occupancy_id,
      v_actor,v_execution.spec_snapshot->>'assignmentRole'
    );
  end if;

  if v_execution.assignment_type='active_occupants_rotation' then
    return private.workflow_assignee_eligible_v1(
      v_execution.organization_id,v_execution.scope_type,
      v_execution.property_id,v_execution.room_id,v_execution.occupancy_id,
      v_actor,'tenant'
    );
  end if;

  if v_execution.assignment_type<>'manual' then
    return false;
  end if;

  -- Organización: solo personal interno activo. ROOT administra, no ejecuta.
  if v_execution.scope_type='organization' then
    return exists(
      select 1
      from public.user_roles ur
      where ur.user_id=v_actor
        and ur.organization_id=v_execution.organization_id
        and ur.role in ('admin','employee')
        and ur.revoked_at is null
    );
  end if;

  -- Piso/Habitación: personal asociado actualmente al piso.
  if v_execution.scope_type in ('property','room')
    and exists(
      select 1
      from public.property_staff_access_v3 a
      join public.user_roles ur
        on ur.user_id=a.employee_user_id
       and ur.organization_id=v_execution.organization_id
       and ur.role in ('admin','employee')
       and ur.revoked_at is null
      where a.property_id=v_execution.property_id
        and a.employee_user_id=v_actor
        and a.assignment_type in ('responsible','access')
        and a.revoked_at is null
        and (a.valid_until is null or a.valid_until>now())
    )
  then
    return true;
  end if;

  -- Piso/Habitación: el inquilino debe seguir viviendo dentro del destino.
  if v_execution.scope_type in ('property','room') then
    return exists(
      select 1
      from public.occupancies_v2 o
      join public.tenants_v2 t
        on t.id=o.tenant_id
       and t.organization_id=o.organization_id
      where o.organization_id=v_execution.organization_id
        and o.property_id=v_execution.property_id
        and (v_execution.scope_type<>'room' or o.room_id=v_execution.room_id)
        and o.status='active'
        and o.starts_on is not null
        and o.starts_on<=current_date
        and (o.ends_on is null or o.ends_on>=current_date)
        and o.user_id=v_actor
        and t.user_id=v_actor
        and t.status='active'
        and t.archived_at is null
    );
  end if;

  -- Ocupación/Inquilino: solo el inquilino activo exacto del destino.
  if v_execution.scope_type='occupancy'
    and v_execution.occupancy_id is not null then
    return exists(
      select 1
      from public.occupancies_v2 o
      join public.tenants_v2 t
        on t.id=o.tenant_id
       and t.organization_id=o.organization_id
      where o.id=v_execution.occupancy_id
        and o.organization_id=v_execution.organization_id
        and o.property_id=v_execution.property_id
        and o.status='active'
        and o.starts_on is not null
        and o.starts_on<=current_date
        and (o.ends_on is null or o.ends_on>=current_date)
        and o.user_id=v_actor
        and t.user_id=v_actor
        and t.status='active'
        and t.archived_at is null
    );
  end if;

  return false;
end;
$$;

revoke all on function public.workflow_execution_actor_current_v1(uuid)
  from public,anon,authenticated;
grant execute on function public.workflow_execution_actor_current_v1(uuid)
  to authenticated,service_role;

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
  elsif v_assignment_type in (
    'property_responsible','fixed_person','role','active_occupants_rotation'
  ) then
    if p_scheduled_assigned_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved' using errcode='22023';
    end if;
    if v_assignment_type='fixed_person' then
      -- A fixed person must already be eligible when programmed and is checked
      -- again at execution time; the schedule never freezes the result.
      perform private.workflow_resolve_execution_assignee_v1(
        p_application_id,null
      );
    elsif v_assignment_type='role'
      and (
        nullif(v_spec->>'assignmentRole','') not in ('admin','employee','tenant')
        or nullif(v_spec->>'assignmentRole','') is null
        or (
          v_spec->>'assignmentRole'='tenant'
          and v_app.scope_type='organization'
        )
      ) then
      raise exception 'workflow_assignment_role_invalid' using errcode='22023';
    elsif v_assignment_type='active_occupants_rotation'
      and v_app.scope_type='organization' then
      raise exception 'workflow_rotation_scope_required' using errcode='22023';
    end if;
    -- Dynamic rules are resolved when each occurrence actually runs.
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
) from public,anon,authenticated,service_role;
