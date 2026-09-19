-- GestionPisos · Fecha concreta · precisión temporal y autoría
-- Complementa 20260919190000 sin reescribir su arquitectura.
--
-- El spec publicado conserva tres piezas inseparables:
--   scheduledAt        -> hora local vista por el autor (YYYY-MM-DDTHH:mm)
--   scheduledTimezone  -> zona IANA del navegador (ej. Europe/Madrid)
--   scheduledAtUtc     -> instante UTC exacto elegido por el navegador
--
-- El scheduler utiliza scheduledAtUtc y verifica que al representarlo en la
-- zona IANA vuelva exactamente a scheduledAt. Así no interpreta datetime-local
-- como UTC ni decide por su cuenta una hora ambigua en cambios DST.

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

  if v_trigger_type<>'scheduled_once' then
    return v_spec || jsonb_build_object(
      'scheduledTimezone','',
      'scheduledAtUtc',''
    );
  end if;

  v_timezone:=nullif(btrim(coalesce(p_spec->>'scheduledTimezone','')),'');
  v_utc:=nullif(btrim(coalesce(p_spec->>'scheduledAtUtc','')),'');
  v_local:=nullif(btrim(coalesce(v_spec->>'scheduledAt','')),'');

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
        (p_spec->>'triggerType')='scheduled_once'
        and coalesce(p_spec->>'scheduledAt','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$'
        and char_length(btrim(coalesce(p_spec->>'scheduledTimezone',''))) between 1 and 80
        and coalesce(p_spec->>'scheduledAtUtc','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{3})?Z$'
      )
      or (
        (p_spec->>'triggerType')='recurring'
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

create or replace function public.save_workflow_definition_draft_v2(
  p_spec jsonb,
  p_definition_id uuid default null,
  p_expected_revision bigint default null
)
returns table(definition_id uuid,revision bigint,updated_at timestamptz)
language plpgsql
security definer
set search_path=public,private,pg_temp
as $workflow_save_v2$
declare
  v_actor uuid:=auth.uid();
  v_org uuid;
  v_role public.app_role;
  v_spec jsonb;
  v_complete boolean;
  v_definition public.workflow_definitions_v2;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select ur.role,ur.organization_id
  into v_role,v_org
  from public.user_roles ur
  where ur.user_id=v_actor
    and ur.revoked_at is null
    and ur.role in ('root','admin')
  order by case when ur.role='root' then 0 else 1 end
  limit 1;

  if v_role is null then
    raise exception 'workflow_author_role_required' using errcode='42501';
  end if;

  if v_role='root' and v_org is null then
    select o.id into v_org
    from public.organizations o
    where o.status='active'
    order by o.created_at
    limit 1;

    if v_org is null then
      raise exception 'organization_missing';
    end if;
    if (select count(*) from public.organizations o where o.status='active')<>1 then
      raise exception 'organization_selection_required';
    end if;
  end if;

  if v_org is null then
    raise exception 'organization_missing';
  end if;

  v_spec:=private.workflow_sanitize_authoring_spec_v3(p_spec);
  v_complete:=public.workflow_authoring_complete_v1(v_spec);

  if p_definition_id is null then
    insert into public.workflow_definitions_v2(
      organization_id,name,flow_type,description,scope_type,trigger_type,
      assignment_type,close_type,status,draft_spec,authoring_complete,created_by,updated_by
    ) values (
      v_org,
      v_spec->>'flowName',
      nullif(v_spec->>'flowType',''),
      nullif(v_spec->>'flowDescription',''),
      nullif(v_spec->>'scopeType',''),
      nullif(v_spec->>'triggerType',''),
      nullif(v_spec->>'assignmentType',''),
      nullif(v_spec->>'closeType',''),
      'draft',v_spec,v_complete,v_actor,v_actor
    )
    returning * into v_definition;

    insert into public.audit_log_v2(
      organization_id,actor_user_id,action,entity_type,entity_id,result,details
    ) values (
      v_org,v_actor,'workflow_draft_created','workflow_definition',v_definition.id::text,'success',
      jsonb_build_object(
        'flow_type',nullif(v_spec->>'flowType',''),
        'scope_type',nullif(v_spec->>'scopeType',''),
        'revision',v_definition.revision,
        'authoring_complete',v_complete
      )
    );
  else
    select * into v_definition
    from public.workflow_definitions_v2 wd
    where wd.id=p_definition_id
      and wd.organization_id=v_org
    for update;

    if v_definition.id is null then
      raise exception 'workflow_definition_not_found' using errcode='P0002';
    end if;
    if v_definition.status<>'draft' then
      raise exception 'workflow_definition_not_editable' using errcode='55000';
    end if;
    if p_expected_revision is not null and p_expected_revision<>v_definition.revision then
      raise exception 'workflow_draft_conflict' using errcode='40001';
    end if;

    if v_definition.draft_spec=v_spec
      and v_definition.authoring_complete=v_complete then
      return query select v_definition.id,v_definition.revision,v_definition.updated_at;
      return;
    end if;

    update public.workflow_definitions_v2 wd
    set name=v_spec->>'flowName',
        flow_type=nullif(v_spec->>'flowType',''),
        description=nullif(v_spec->>'flowDescription',''),
        scope_type=nullif(v_spec->>'scopeType',''),
        trigger_type=nullif(v_spec->>'triggerType',''),
        assignment_type=nullif(v_spec->>'assignmentType',''),
        close_type=nullif(v_spec->>'closeType',''),
        draft_spec=v_spec,
        authoring_complete=v_complete,
        revision=wd.revision+1,
        updated_by=v_actor,
        updated_at=now()
    where wd.id=p_definition_id
    returning * into v_definition;

    insert into public.audit_log_v2(
      organization_id,actor_user_id,action,entity_type,entity_id,result,details
    ) values (
      v_org,v_actor,'workflow_draft_updated','workflow_definition',v_definition.id::text,'success',
      jsonb_build_object(
        'flow_type',nullif(v_spec->>'flowType',''),
        'scope_type',nullif(v_spec->>'scopeType',''),
        'revision',v_definition.revision,
        'authoring_complete',v_complete
      )
    );
  end if;

  return query select v_definition.id,v_definition.revision,v_definition.updated_at;
end;
$workflow_save_v2$;

revoke all on function public.save_workflow_definition_draft_v2(jsonb,uuid,bigint)
  from public,anon;
grant execute on function public.save_workflow_definition_draft_v2(jsonb,uuid,bigint)
  to authenticated;

create or replace function public.save_workflow_definition_revision_draft_v1(
  p_definition_id uuid,
  p_spec jsonb,
  p_expected_revision bigint default null
)
returns table(
  definition_id uuid,
  base_version integer,
  revision bigint,
  authoring_complete boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path=public,private,pg_temp
as $save_revision$
declare
  v_actor uuid:=auth.uid();
  v_definition public.workflow_definitions_v2;
  v_draft public.workflow_definition_revision_drafts_v2;
  v_spec jsonb;
  v_complete boolean;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select wd.* into v_definition
  from public.workflow_definitions_v2 wd
  where wd.id=p_definition_id;

  if v_definition.id is null then
    raise exception 'workflow_definition_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_definition.organization_id) then
    raise exception 'workflow_author_role_required' using errcode='42501';
  end if;

  if v_definition.status<>'published' then
    raise exception 'workflow_revision_requires_published_definition' using errcode='55000';
  end if;

  select rd.* into v_draft
  from public.workflow_definition_revision_drafts_v2 rd
  where rd.definition_id=p_definition_id
    and rd.published_at is null
  for update;

  if v_draft.definition_id is null then
    raise exception 'workflow_revision_draft_not_found' using errcode='P0002';
  end if;

  if p_expected_revision is not null
    and p_expected_revision<>v_draft.revision then
    raise exception 'workflow_draft_conflict' using errcode='40001';
  end if;

  v_spec:=private.workflow_sanitize_authoring_spec_v3(p_spec);
  v_complete:=public.workflow_authoring_complete_v1(v_spec);

  if v_draft.draft_spec=v_spec
    and v_draft.authoring_complete=v_complete then
    return query
    select v_draft.definition_id,v_draft.base_version,v_draft.revision,
           v_draft.authoring_complete,v_draft.updated_at;
    return;
  end if;

  update public.workflow_definition_revision_drafts_v2 d
  set draft_spec=v_spec,
      authoring_complete=v_complete,
      revision=d.revision+1,
      updated_by=v_actor,
      updated_at=now()
  where d.definition_id=p_definition_id
  returning * into v_draft;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_definition.organization_id,v_actor,'workflow_revision_draft_updated',
    'workflow_definition',p_definition_id::text,'success',
    jsonb_build_object(
      'base_version',v_draft.base_version,
      'draft_revision',v_draft.revision,
      'authoring_complete',v_draft.authoring_complete
    )
  );

  return query
  select v_draft.definition_id,v_draft.base_version,v_draft.revision,
         v_draft.authoring_complete,v_draft.updated_at;
end;
$save_revision$;

revoke all on function public.save_workflow_definition_revision_draft_v1(uuid,jsonb,bigint)
  from public,anon;
grant execute on function public.save_workflow_definition_revision_draft_v1(uuid,jsonb,bigint)
  to authenticated;

-- La edición en sitio de un flujo publicado sin historial debe conservar los
-- campos temporales exactos. El v1 original usaba el saneador v2 y los eliminaba.
create or replace function public.update_unexecuted_workflow_v1(
  p_definition_id uuid,
  p_spec jsonb,
  p_property_id uuid default null,
  p_room_id uuid default null,
  p_occupancy_id uuid default null,
  p_photo_pattern_ids uuid[] default '{}'::uuid[],
  p_expected_revision bigint default null,
  p_execute boolean default false,
  p_idempotency_key text default null,
  p_assigned_user_id uuid default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  application_id uuid,
  execution_id uuid,
  execution_status text,
  assigned_user_id uuid,
  revision bigint
)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $
declare
  v_actor uuid:=auth.uid();
  v_definition public.workflow_definitions_v2;
  v_version public.workflow_definition_versions_v2;
  v_spec jsonb;
  v_new_revision bigint;
  v_application record;
  v_execution_id uuid;
  v_execution_status text;
  v_execution_assigned_user_id uuid;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if coalesce(auth.jwt()->>'aal','aal1') <> 'aal2' then
    raise exception 'aal2_required' using errcode='42501';
  end if;

  select wd.* into v_definition
  from public.workflow_definitions_v2 wd
  where wd.id=p_definition_id
  for update;

  if v_definition.id is null then
    raise exception 'workflow_definition_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_definition.organization_id) then
    raise exception 'workflow_author_role_required' using errcode='42501';
  end if;

  if v_definition.status<>'published' then
    raise exception 'workflow_definition_not_editable' using errcode='55000';
  end if;

  if p_expected_revision is not null and p_expected_revision<>v_definition.revision then
    raise exception 'workflow_draft_conflict' using errcode='40001';
  end if;

  if exists(
    select 1
    from public.workflow_executions_v2 e
    join public.workflow_applications_v2 a on a.id=e.application_id
    where a.definition_id=p_definition_id
  ) then
    raise exception 'workflow_definition_has_history' using errcode='55000';
  end if;

  v_spec:=private.workflow_sanitize_authoring_spec_v3(p_spec);
  if not public.workflow_authoring_complete_v1(v_spec) then
    raise exception 'workflow_authoring_incomplete' using errcode='22023';
  end if;

  select wv.* into v_version
  from public.workflow_definition_versions_v2 wv
  where wv.definition_id=p_definition_id
    and wv.organization_id=v_definition.organization_id
  order by wv.version desc
  limit 1
  for update;

  if v_version.id is null then
    raise exception 'workflow_published_version_missing' using errcode='55000';
  end if;

  v_new_revision:=v_definition.revision+1;

  update public.workflow_definitions_v2 wd
  set name=v_spec->>'flowName',
      flow_type=nullif(v_spec->>'flowType',''),
      description=nullif(v_spec->>'flowDescription',''),
      scope_type=nullif(v_spec->>'scopeType',''),
      trigger_type=nullif(v_spec->>'triggerType',''),
      assignment_type=nullif(v_spec->>'assignmentType',''),
      close_type=nullif(v_spec->>'closeType',''),
      draft_spec=v_spec,
      authoring_complete=true,
      revision=v_new_revision,
      updated_by=v_actor,
      updated_at=now()
  where wd.id=p_definition_id;

  update public.workflow_definition_versions_v2 wv
  set spec=v_spec || jsonb_build_object('definitionRevision',v_new_revision)
  where wv.id=v_version.id;

  delete from public.workflow_definition_revision_drafts_v2 rd
  where rd.definition_id=p_definition_id;

  delete from public.workflow_application_photo_resources_v2 r
  where r.application_id in (
    select a.id
    from public.workflow_applications_v2 a
    where a.definition_id=p_definition_id
  );

  delete from public.workflow_applications_v2 a
  where a.definition_id=p_definition_id;

  select * into v_application
  from public.create_workflow_application_v2(
    v_version.id,
    p_property_id,
    p_room_id,
    p_occupancy_id,
    coalesce(p_photo_pattern_ids,'{}'::uuid[])
  )
  limit 1;

  if p_execute then
    select x.execution_id,x.status,x.assigned_user_id
    into v_execution_id,v_execution_status,v_execution_assigned_user_id
    from public.execute_workflow_application_now_v1(
      v_application.application_id,
      p_idempotency_key,
      p_assigned_user_id
    ) as x
    limit 1;
  end if;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_definition.organization_id,v_actor,
    case when p_execute then 'workflow_unexecuted_updated_and_executed' else 'workflow_unexecuted_updated' end,
    'workflow_definition',p_definition_id::text,'success',
    jsonb_build_object(
      'version_id',v_version.id,
      'version',v_version.version,
      'revision',v_new_revision,
      'application_id',v_application.application_id,
      'execution_id',v_execution_id
    )
  );

  return query
  select
    p_definition_id,
    v_version.id,
    v_version.version,
    v_application.application_id,
    v_execution_id,
    v_execution_status,
    v_execution_assigned_user_id,
    v_new_revision;
end;
$;

-- Los borradores programados creados antes de este incremento deben volver a
-- validarse al editar; no inventamos zona ni UTC para decisiones históricas.
update public.workflow_definitions_v2
set authoring_complete=public.workflow_authoring_complete_v1(draft_spec)
where status='draft';

update public.workflow_definition_revision_drafts_v2
set authoring_complete=public.workflow_authoring_complete_v1(draft_spec)
where published_at is null;

-- Verifica que trigger_kind corresponde al trigger publicado. Evita que
-- scheduled_once se ejecute accidentalmente como manual_now.
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

  if new.trigger_kind='scheduled_once' and v_spec_trigger<>'scheduled_once' then
    raise exception 'workflow_scheduled_trigger_mismatch' using errcode='55000';
  end if;

  return new;
end;
$workflow_trigger_guard$;

revoke all on function private.workflow_execution_trigger_kind_guard_v1()
  from public,anon,authenticated;

drop trigger if exists workflow_execution_trigger_kind_guard_v1
  on public.workflow_executions_v2;

create trigger workflow_execution_trigger_kind_guard_v1
before insert on public.workflow_executions_v2
for each row
execute function private.workflow_execution_trigger_kind_guard_v1();

-- Sustituye la interpretación de datetime-local por el instante UTC exacto
-- ya congelado en la versión publicada. La zona recibida por el RPC solo se
-- acepta si coincide con el spec, evitando divergencia frontend/backend.
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

-- Un fallo deja la programación bloqueada y terminal. Persistimos solo SQLSTATE
-- como diagnóstico técnico; el texto completo del error no queda almacenado.
-- La notificación se deduplica por aplicación + instante programado.
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
  v_event_key text;
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

comment on function private.workflow_sanitize_authoring_spec_v3(jsonb) is
  'Saneado de autoría con instante exacto para scheduled_once: hora local + zona IANA + UTC deben representar el mismo momento.';
