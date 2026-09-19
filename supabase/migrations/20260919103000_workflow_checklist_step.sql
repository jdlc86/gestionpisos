-- GestionPisos · Flujos de Trabajo · paso Checklist operativo
-- Checklist v1: lista ordenada de elementos requerido/opcional, congelada por ejecución.
-- No crea un segundo motor de tareas: reutiliza tenant_tasks_v2 y workflow_executions_v2.

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

revoke all on function public.workflow_authoring_complete_v1(jsonb) from public;
revoke execute on function public.workflow_authoring_complete_v1(jsonb) from anon;

create or replace function private.workflow_sanitize_authoring_spec_v2(
  p_spec jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $sanitize$
declare
  v_name text;
  v_flow_type text;
  v_description text;
  v_scope_type text;
  v_trigger_type text;
  v_recurrence text;
  v_scheduled_at text;
  v_custom_every text;
  v_custom_unit text;
  v_assignment_type text;
  v_close_type text;
  v_steps jsonb;
  v_notifications jsonb;
  v_checklist_items jsonb;
  v_normalized_checklist jsonb:='[]'::jsonb;
  v_item jsonb;
  v_item_text text;
  v_item_required boolean;
  v_item_index integer:=0;
  v_authoring_version integer:=1;
begin
  if p_spec is null or jsonb_typeof(p_spec)<>'object' then
    raise exception 'workflow_spec_object_required' using errcode='22023';
  end if;

  v_name:=btrim(coalesce(p_spec->>'flowName',''));
  v_flow_type:=nullif(p_spec->>'flowType','');
  v_description:=nullif(btrim(coalesce(p_spec->>'flowDescription','')),'');
  v_scope_type:=nullif(p_spec->>'scopeType','');
  v_trigger_type:=nullif(p_spec->>'triggerType','');
  v_recurrence:=nullif(p_spec->>'recurrence','');
  v_scheduled_at:=nullif(btrim(coalesce(p_spec->>'scheduledAt','')),'');
  v_custom_every:=nullif(btrim(coalesce(p_spec->>'customEvery','')),'');
  v_custom_unit:=nullif(p_spec->>'customUnit','');
  v_assignment_type:=nullif(p_spec->>'assignmentType','');
  v_close_type:=nullif(p_spec->>'closeType','');
  v_steps:=coalesce(p_spec->'steps','{}'::jsonb);
  v_notifications:=coalesce(p_spec->'notifications','{}'::jsonb);
  v_checklist_items:=coalesce(p_spec->'checklistItems','[]'::jsonb);

  if coalesce(p_spec->>'authoringVersion','') ~ '^[0-9]+$' then
    v_authoring_version:=greatest(1,(p_spec->>'authoringVersion')::integer);
  end if;

  if v_authoring_version<2 then
    v_flow_type:=null;
    v_scope_type:=null;
    v_trigger_type:=null;
    v_recurrence:=null;
    v_scheduled_at:=null;
    v_custom_every:=null;
    v_custom_unit:=null;
    v_assignment_type:=null;
    v_close_type:=null;
    v_steps:='{}'::jsonb;
    v_notifications:='{}'::jsonb;
    v_checklist_items:='[]'::jsonb;
  end if;

  if char_length(v_name)<3 or char_length(v_name)>80 then
    raise exception 'workflow_name_invalid' using errcode='22023';
  end if;
  if v_flow_type is not null
    and v_flow_type not in ('cleaning','inspection','maintenance','checkin','checkout','custom') then
    raise exception 'workflow_type_invalid' using errcode='22023';
  end if;
  if v_description is not null and char_length(v_description)>400 then
    raise exception 'workflow_description_too_long' using errcode='22023';
  end if;
  if v_scope_type is not null
    and v_scope_type not in ('organization','property','room','occupancy') then
    raise exception 'workflow_scope_invalid' using errcode='22023';
  end if;
  if v_trigger_type is not null
    and v_trigger_type not in ('manual','recurring','scheduled_once','event') then
    raise exception 'workflow_trigger_invalid' using errcode='22023';
  end if;
  if v_trigger_type='recurring'
    and v_recurrence is not null
    and v_recurrence not in ('weekly','biweekly','monthly','custom') then
    raise exception 'workflow_recurrence_invalid' using errcode='22023';
  end if;
  if v_scheduled_at is not null
    and v_scheduled_at !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$' then
    raise exception 'workflow_scheduled_at_invalid' using errcode='22023';
  end if;
  if v_custom_every is not null then
    if v_custom_every !~ '^[0-9]+$'
      or v_custom_every::integer<1
      or v_custom_every::integer>365 then
      raise exception 'workflow_custom_recurrence_invalid' using errcode='22023';
    end if;
  end if;
  if v_custom_unit is not null and v_custom_unit not in ('day','week','month') then
    raise exception 'workflow_custom_recurrence_invalid' using errcode='22023';
  end if;

  if v_trigger_type is distinct from 'recurring' then
    v_recurrence:=null;
    v_custom_every:=null;
    v_custom_unit:=null;
  elsif v_recurrence is distinct from 'custom' then
    v_custom_every:=null;
    v_custom_unit:=null;
  end if;

  if v_trigger_type is distinct from 'scheduled_once' then
    v_scheduled_at:=null;
  end if;

  if v_assignment_type is not null
    and v_assignment_type not in ('property_responsible','active_occupants_rotation','fixed_person','role','manual') then
    raise exception 'workflow_assignment_invalid' using errcode='22023';
  end if;
  if v_close_type is not null
    and v_close_type not in ('auto','human_review','domain_adapter') then
    raise exception 'workflow_close_invalid' using errcode='22023';
  end if;

  if jsonb_typeof(v_steps)<>'object'
    or jsonb_typeof(v_notifications)<>'object'
    or jsonb_typeof(v_checklist_items)<>'array' then
    raise exception 'workflow_nested_spec_invalid' using errcode='22023';
  end if;

  if (v_steps ? 'accept' and jsonb_typeof(v_steps->'accept')<>'boolean')
    or (v_steps ? 'photo' and jsonb_typeof(v_steps->'photo')<>'boolean')
    or (v_steps ? 'checklist' and jsonb_typeof(v_steps->'checklist')<>'boolean')
    or (v_steps ? 'document' and jsonb_typeof(v_steps->'document')<>'boolean')
    or (v_notifications ? 'onCreate' and jsonb_typeof(v_notifications->'onCreate')<>'boolean')
    or (v_notifications ? 'onClose' and jsonb_typeof(v_notifications->'onClose')<>'boolean') then
    raise exception 'workflow_nested_spec_invalid' using errcode='22023';
  end if;

  if jsonb_array_length(v_checklist_items)>30 then
    raise exception 'workflow_checklist_too_many_items' using errcode='22023';
  end if;

  if coalesce((v_steps->>'checklist')::boolean,false) then
    for v_item in select value from jsonb_array_elements(v_checklist_items)
    loop
      if jsonb_typeof(v_item)<>'object' then
        raise exception 'workflow_checklist_item_invalid' using errcode='22023';
      end if;
      v_item_text:=btrim(coalesce(v_item->>'text',''));
      if char_length(v_item_text)>160 then
        raise exception 'workflow_checklist_item_text_invalid' using errcode='22023';
      end if;
      if v_item ? 'required' and jsonb_typeof(v_item->'required')<>'boolean' then
        raise exception 'workflow_checklist_item_required_invalid' using errcode='22023';
      end if;
      v_item_required:=coalesce((v_item->>'required')::boolean,true);
      v_item_index:=v_item_index+1;
      v_normalized_checklist:=v_normalized_checklist || jsonb_build_array(
        jsonb_build_object(
          'key','item-'||v_item_index::text,
          'text',v_item_text,
          'required',v_item_required
        )
      );
    end loop;
  else
    v_normalized_checklist:='[]'::jsonb;
  end if;

  return jsonb_build_object(
    'authoringVersion',v_authoring_version,
    'flowName',v_name,
    'flowType',coalesce(v_flow_type,''),
    'flowDescription',coalesce(v_description,''),
    'scopeType',coalesce(v_scope_type,''),
    'triggerType',coalesce(v_trigger_type,''),
    'recurrence',coalesce(v_recurrence,''),
    'scheduledAt',coalesce(v_scheduled_at,''),
    'customEvery',coalesce(v_custom_every,''),
    'customUnit',coalesce(v_custom_unit,''),
    'assignmentType',coalesce(v_assignment_type,''),
    'steps',jsonb_build_object(
      'accept',coalesce((v_steps->>'accept')::boolean,false),
      'photo',coalesce((v_steps->>'photo')::boolean,false),
      'checklist',coalesce((v_steps->>'checklist')::boolean,false),
      'document',coalesce((v_steps->>'document')::boolean,false)
    ),
    'checklistItems',v_normalized_checklist,
    'closeType',coalesce(v_close_type,''),
    'notifications',jsonb_build_object(
      'onCreate',coalesce((v_notifications->>'onCreate')::boolean,false),
      'onClose',coalesce((v_notifications->>'onClose')::boolean,false)
    )
  );
end;
$sanitize$;

revoke all on function private.workflow_sanitize_authoring_spec_v2(jsonb)
  from public,anon,authenticated;

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

  v_spec:=private.workflow_sanitize_authoring_spec_v2(p_spec);
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

revoke all on function public.save_workflow_definition_draft_v2(jsonb,uuid,bigint) from public,anon;
grant execute on function public.save_workflow_definition_draft_v2(jsonb,uuid,bigint) to authenticated;

update public.workflow_definitions_v2
set draft_spec=draft_spec || jsonb_build_object(
      'checklistItems',
      case
        when coalesce((draft_spec#>>'{steps,checklist}')::boolean,false)
          and jsonb_typeof(draft_spec->'checklistItems')='array'
          then draft_spec->'checklistItems'
        else '[]'::jsonb
      end
    )
where status='draft';

update public.workflow_definitions_v2
set authoring_complete=public.workflow_authoring_complete_v1(draft_spec)
where status='draft';

update public.workflow_definition_revision_drafts_v2
set draft_spec=draft_spec || jsonb_build_object(
      'checklistItems',
      case
        when coalesce((draft_spec#>>'{steps,checklist}')::boolean,false)
          and jsonb_typeof(draft_spec->'checklistItems')='array'
          then draft_spec->'checklistItems'
        else '[]'::jsonb
      end
    ),
    authoring_complete=public.workflow_authoring_complete_v1(
      draft_spec || jsonb_build_object(
        'checklistItems',
        case
          when coalesce((draft_spec#>>'{steps,checklist}')::boolean,false)
            and jsonb_typeof(draft_spec->'checklistItems')='array'
            then draft_spec->'checklistItems'
          else '[]'::jsonb
        end
      )
    )
where published_at is null;

alter table public.workflow_executions_v2
  add column if not exists checklist_state jsonb not null default '[]'::jsonb;

alter table public.workflow_executions_v2
  drop constraint if exists workflow_executions_v2_checklist_state_check;
alter table public.workflow_executions_v2
  add constraint workflow_executions_v2_checklist_state_check
  check (jsonb_typeof(checklist_state)='array');

create or replace function private.workflow_initialize_checklist_state_v1()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $workflow_checklist_init$
declare
  v_item jsonb;
  v_state jsonb:='[]'::jsonb;
begin
  if not coalesce((new.spec_snapshot#>>'{steps,checklist}')::boolean,false) then
    new.checklist_state:='[]'::jsonb;
    return new;
  end if;

  if jsonb_typeof(new.spec_snapshot->'checklistItems')<>'array'
    or jsonb_array_length(new.spec_snapshot->'checklistItems')<1 then
    raise exception 'workflow_checklist_definition_missing' using errcode='55000';
  end if;

  for v_item in select value from jsonb_array_elements(new.spec_snapshot->'checklistItems')
  loop
    v_state:=v_state || jsonb_build_array(
      jsonb_build_object(
        'key',v_item->>'key',
        'text',v_item->>'text',
        'required',coalesce((v_item->>'required')::boolean,true),
        'completed',false,
        'completedAt',null,
        'completedBy',null
      )
    );
  end loop;

  new.checklist_state:=v_state;
  return new;
end;
$workflow_checklist_init$;

revoke all on function private.workflow_initialize_checklist_state_v1()
  from public,anon,authenticated;

drop trigger if exists workflow_execution_initialize_checklist_v1
  on public.workflow_executions_v2;
create trigger workflow_execution_initialize_checklist_v1
before insert on public.workflow_executions_v2
for each row execute function private.workflow_initialize_checklist_state_v1();

create unique index if not exists workflow_execution_events_v2_checklist_request_uq
  on public.workflow_execution_events_v2(
    execution_id,(details->>'request_key')
  )
  where event_type='checklist_item_changed'
    and nullif(details->>'request_key','') is not null;

create or replace function public.set_workflow_checklist_item_v1(
  p_task_id uuid,
  p_item_key text,
  p_completed boolean,
  p_request_key text
)
returns table(
  task_id uuid,
  task_status text,
  execution_id uuid,
  execution_status text,
  checklist_state jsonb,
  all_required_complete boolean,
  applied_new boolean
)
language plpgsql
security definer
set search_path=public,pg_temp
as $workflow_checklist_apply$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_item_key text:=nullif(btrim(p_item_key),'');
  v_task public.tenant_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_previous public.workflow_execution_events_v2;
  v_item jsonb;
  v_item_index integer;
  v_new_state jsonb;
  v_all_required boolean:=false;
  v_photo_complete boolean:=true;
  v_document_pending boolean:=false;
  v_close_type text;
  v_target_status text;
  v_from_status text;
  v_requires_accept boolean:=false;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_checklist_request_key_invalid' using errcode='22023';
  end if;
  if v_item_key is null or length(v_item_key)>80 then
    raise exception 'workflow_checklist_item_key_invalid' using errcode='22023';
  end if;

  select * into v_task
  from public.tenant_tasks_v2
  where id=p_task_id
  for update;

  if v_task.id is null
    or v_task.task_type<>'workflow'
    or v_task.source_kind<>'workflow_execution'
    or v_task.source_id is null then
    raise exception 'workflow_task_required' using errcode='22023';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_task.source_id
  for update;

  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  if v_task.organization_id<>v_execution.organization_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id
    or v_task.property_id is distinct from v_execution.property_id
    or v_task.room_id is distinct from v_execution.room_id
    or v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_identity_mismatch' using errcode='55000';
  end if;

  if v_actor is distinct from v_execution.assigned_user_id then
    raise exception 'workflow_checklist_actor_forbidden' using errcode='42501';
  end if;

  if not coalesce((v_execution.spec_snapshot#>>'{steps,checklist}')::boolean,false) then
    raise exception 'workflow_checklist_not_configured' using errcode='22023';
  end if;

  v_requires_accept:=coalesce((v_execution.spec_snapshot#>>'{steps,accept}')::boolean,false);
  if v_requires_accept and v_task.status='pending' then
    raise exception 'workflow_checklist_accept_required' using errcode='55000';
  end if;
  if v_task.status not in ('pending','active') then
    raise exception 'workflow_checklist_not_actionable' using errcode='55000';
  end if;

  select * into v_previous
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='checklist_item_changed'
    and ev.details->>'request_key'=v_key
  order by ev.id
  limit 1;

  if v_previous.id is not null then
    if v_previous.details->>'item_key' is distinct from v_item_key
      or coalesce((v_previous.details->>'completed')::boolean,false) is distinct from p_completed then
      raise exception 'workflow_checklist_request_key_conflict' using errcode='55000';
    end if;

    select not exists(
      select 1 from jsonb_array_elements(v_execution.checklist_state) item
      where coalesce((item->>'required')::boolean,true)
        and not coalesce((item->>'completed')::boolean,false)
    ) into v_all_required;

    return query
    select v_task.id,v_task.status,v_execution.id,v_execution.status,
           v_execution.checklist_state,v_all_required,false;
    return;
  end if;

  select value,ord::integer
  into v_item,v_item_index
  from jsonb_array_elements(v_execution.checklist_state) with ordinality as x(value,ord)
  where value->>'key'=v_item_key
  limit 1;

  if v_item is null then
    raise exception 'workflow_checklist_item_not_found' using errcode='P0002';
  end if;

  if coalesce((v_item->>'completed')::boolean,false)=p_completed then
    -- A semantic no-op still gets an idempotency receipt so retries remain safe.
    v_new_state:=v_execution.checklist_state;
  else
    select coalesce(jsonb_agg(
      case
        when ord=v_item_index then
          jsonb_set(
            jsonb_set(
              jsonb_set(value,'{completed}',to_jsonb(p_completed),true),
              '{completedAt}',
              case when p_completed then to_jsonb(now()) else 'null'::jsonb end,
              true
            ),
            '{completedBy}',
            case when p_completed then to_jsonb(v_actor::text) else 'null'::jsonb end,
            true
          )
        else value
      end
      order by ord
    ),'[]'::jsonb)
    into v_new_state
    from jsonb_array_elements(v_execution.checklist_state) with ordinality as x(value,ord);
  end if;

  select not exists(
    select 1 from jsonb_array_elements(v_new_state) item
    where coalesce((item->>'required')::boolean,true)
      and not coalesce((item->>'completed')::boolean,false)
  ) into v_all_required;

  if coalesce((v_execution.spec_snapshot#>>'{steps,photo}')::boolean,false) then
    select exists(
      select 1
      from public.workflow_execution_photo_resources_v2 r
      where r.execution_id=v_execution.id
    ) and not exists(
      select 1
      from public.workflow_execution_photo_resources_v2 r
      where r.execution_id=v_execution.id
        and r.status<>'submitted'
    ) into v_photo_complete;
  end if;

  v_document_pending:=coalesce((v_execution.spec_snapshot#>>'{steps,document}')::boolean,false);
  v_close_type:=nullif(v_execution.spec_snapshot->>'closeType','');
  v_from_status:=v_execution.status;
  v_target_status:=v_execution.status;

  if v_all_required and v_photo_complete and not v_document_pending then
    if v_close_type='auto' then
      v_target_status:='completed';
    elsif v_close_type='human_review' then
      v_target_status:='waiting_review';
    end if;
  elsif v_target_status='pending' then
    v_target_status:='active';
  end if;

  update public.workflow_executions_v2 e
  set checklist_state=v_new_state,
      status=v_target_status,
      updated_at=now(),
      started_at=coalesce(e.started_at,now()),
      completed_at=case
        when v_target_status='completed' then coalesce(e.completed_at,now())
        else e.completed_at
      end
  where e.id=v_execution.id
  returning * into v_execution;

  if v_task.status is distinct from v_target_status then
    update public.tenant_tasks_v2
    set status=v_target_status,updated_at=now()
    where id=v_task.id
    returning * into v_task;
  end if;

  insert into public.tenant_task_history_v2(
    task_id,action_key,action_label,from_status,to_status,note,actor_user_id
  ) values (
    v_task.id,
    case when p_completed then 'checklist_item_completed' else 'checklist_item_reopened' end,
    case when p_completed then 'Elemento de checklist completado' else 'Elemento de checklist reabierto' end,
    v_from_status,
    v_target_status,
    nullif(v_item->>'text',''),
    v_actor
  );

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,v_execution.organization_id,'checklist_item_changed',
    v_from_status,v_target_status,v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'item_key',v_item_key,
      'item_text',v_item->>'text',
      'required',coalesce((v_item->>'required')::boolean,true),
      'completed',p_completed,
      'all_required_complete',v_all_required,
      'photo_complete',v_photo_complete,
      'document_pending',v_document_pending,
      'request_key',v_key
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,v_actor,'workflow_checklist_item_changed',
    'workflow_execution',v_execution.id::text,'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'item_key',v_item_key,
      'completed',p_completed,
      'task_status',v_task.status,
      'execution_status',v_execution.status
    )
  );

  return query
  select v_task.id,v_task.status,v_execution.id,v_execution.status,
         v_execution.checklist_state,v_all_required,true;
end;
$workflow_checklist_apply$;

revoke all on function public.set_workflow_checklist_item_v1(uuid,text,boolean,text)
  from public,anon;
grant execute on function public.set_workflow_checklist_item_v1(uuid,text,boolean,text)
  to authenticated;

-- Foto + Checklist deben cerrar en cualquier orden. La foto deja de considerar
-- "checklist configurado" como pendiente cuando los obligatorios ya están completos.
create or replace function public.submit_workflow_photo_verification_v1(
  p_run_id uuid,
  p_item_id uuid,
  p_request_key text
)
returns table(
  photo_resource_id uuid,
  photo_resource_status text,
  all_photos_complete boolean,
  task_status text,
  execution_status text,
  applied_new boolean
)
language plpgsql
security definer
set search_path=public,storage,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_run public.photo_verification_runs_v2;
  v_item public.photo_verification_items_v2;
  v_resource public.workflow_execution_photo_resources_v2;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_previous_event public.workflow_execution_events_v2;
  v_expected_path text;
  v_all_complete boolean:=false;
  v_other_steps boolean:=false;
  v_close_type text;
  v_target_status text;
  v_from_status text;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_photo_request_key_invalid' using errcode='22023';
  end if;

  select * into v_run
  from public.photo_verification_runs_v2
  where id=p_run_id
  for update;

  if v_run.id is null
    or v_run.source_type<>'workflow_execution'
    or v_run.source_id is null then
    raise exception 'workflow_photo_run_not_found' using errcode='P0002';
  end if;

  select * into v_resource
  from public.workflow_execution_photo_resources_v2
  where photo_run_id=v_run.id
  for update;

  if v_resource.id is null then
    raise exception 'workflow_photo_resource_not_found' using errcode='55000';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_resource.execution_id
  for update;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id
  for update;

  if v_actor is distinct from v_run.actor_user_id
    or v_actor is distinct from v_execution.assigned_user_id
    or v_actor is distinct from v_task.assigned_user_id then
    raise exception 'workflow_photo_actor_forbidden' using errcode='42501';
  end if;

  if v_run.source_id is distinct from v_execution.id
    or v_run.organization_id<>v_execution.organization_id
    or v_run.property_id<>v_execution.property_id
    or v_resource.pattern_id is null then
    raise exception 'workflow_photo_identity_mismatch' using errcode='55000';
  end if;

  if v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_state_mismatch' using errcode='55000';
  end if;

  v_from_status:=v_execution.status;

  select * into v_previous_event
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='photo_evidence_submitted'
    and ev.details->>'request_key'=v_key
  order by ev.id
  limit 1;

  if v_previous_event.id is not null then
    if v_previous_event.details->>'photo_resource_id' is distinct from v_resource.id::text
      or v_previous_event.details->>'photo_run_id' is distinct from p_run_id::text
      or v_previous_event.details->>'item_id' is distinct from p_item_id::text then
      raise exception 'workflow_photo_request_key_conflict' using errcode='55000';
    end if;

    select not exists(
      select 1 from public.workflow_execution_photo_resources_v2 er
      where er.execution_id=v_execution.id and er.status<>'submitted'
    ) into v_all_complete;

    return query
    select v_resource.id,v_resource.status,v_all_complete,v_task.status,v_execution.status,false;
    return;
  end if;

  if v_run.status='submitted' and v_resource.status='submitted' then
    select not exists(
      select 1 from public.workflow_execution_photo_resources_v2 er
      where er.execution_id=v_execution.id and er.status<>'submitted'
    ) into v_all_complete;

    return query
    select v_resource.id,v_resource.status,v_all_complete,v_task.status,v_execution.status,false;
    return;
  end if;

  if v_run.status<>'capturing' or v_resource.status<>'capturing' then
    raise exception 'workflow_photo_not_capturing' using errcode='55000';
  end if;

  select * into v_item
  from public.photo_verification_items_v2
  where id=p_item_id
    and run_id=v_run.id;

  if v_item.id is null
    or v_item.pattern_id is distinct from v_resource.pattern_id then
    raise exception 'workflow_photo_item_invalid' using errcode='22023';
  end if;

  v_expected_path:=v_run.organization_id::text||'/'||v_run.id::text||'/'||v_item.id::text||'.jpg';
  if v_item.storage_path is distinct from v_expected_path then
    raise exception 'workflow_photo_storage_path_invalid' using errcode='55000';
  end if;

  if not exists(
    select 1
    from storage.objects o
    where o.bucket_id='photo-verification'
      and o.name=v_expected_path
      and o.owner_id=v_actor::text
  ) then
    raise exception 'workflow_photo_object_missing' using errcode='55000';
  end if;

  update public.photo_verification_runs_v2
  set status='submitted',submitted_at=coalesce(submitted_at,now())
  where id=v_run.id
  returning * into v_run;

  update public.workflow_execution_photo_resources_v2
  set status='submitted',completed_at=coalesce(completed_at,now())
  where id=v_resource.id
  returning * into v_resource;

  select not exists(
    select 1
    from public.workflow_execution_photo_resources_v2 er
    where er.execution_id=v_execution.id
      and er.status<>'submitted'
  ) into v_all_complete;

  v_target_status:=v_execution.status;

  if v_all_complete then
    v_other_steps:=
      coalesce((v_execution.spec_snapshot->'steps'->>'document')::boolean,false)
      or (
        coalesce((v_execution.spec_snapshot->'steps'->>'checklist')::boolean,false)
        and (
          jsonb_typeof(v_execution.checklist_state)<>'array'
          or jsonb_array_length(v_execution.checklist_state)=0
          or exists(
            select 1
            from jsonb_array_elements(v_execution.checklist_state) item
            where coalesce((item->>'required')::boolean,true)
              and not coalesce((item->>'completed')::boolean,false)
          )
        )
      );
    v_close_type:=nullif(v_execution.spec_snapshot->>'closeType','');

    if not v_other_steps then
      if v_close_type='auto' then
        v_target_status:='completed';
      elsif v_close_type='human_review' then
        v_target_status:='waiting_review';
      end if;
    end if;
  end if;

  if v_target_status is distinct from v_execution.status then
    insert into public.tenant_task_history_v2(
      task_id,action_key,action_label,from_status,to_status,note,actor_user_id
    ) values (
      v_task.id,
      'photo_complete',
      case
        when v_target_status='completed' then 'Evidencia fotográfica completada'
        when v_target_status='waiting_review' then 'Evidencia fotográfica enviada a revisión'
        else 'Evidencia fotográfica'
      end,
      v_task.status,
      v_target_status,
      null,
      v_actor
    );

    update public.tenant_tasks_v2
    set status=v_target_status,updated_at=now()
    where id=v_task.id
    returning * into v_task;

    update public.workflow_executions_v2 as updated_execution
    set status=v_target_status,
        updated_at=now(),
        started_at=coalesce(updated_execution.started_at,now()),
        completed_at=case
          when v_target_status='completed' then coalesce(updated_execution.completed_at,now())
          else updated_execution.completed_at
        end
    where id=v_execution.id
    returning * into v_execution;
  end if;

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,
    v_execution.organization_id,
    'photo_evidence_submitted',
    v_from_status,
    v_execution.status,
    v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'photo_resource_id',v_resource.id,
      'photo_run_id',v_run.id,
      'item_id',v_item.id,
      'pattern_id',v_resource.pattern_id,
      'request_key',v_key,
      'all_photos_complete',v_all_complete
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,
    v_actor,
    'workflow_photo_evidence_submitted',
    'workflow_execution',
    v_execution.id::text,
    'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'photo_resource_id',v_resource.id,
      'photo_run_id',v_run.id,
      'item_id',v_item.id,
      'pattern_id',v_resource.pattern_id,
      'all_photos_complete',v_all_complete,
      'task_status',v_task.status,
      'execution_status',v_execution.status
    )
  );

  return query
  select v_resource.id,v_resource.status,v_all_complete,v_task.status,v_execution.status,true;
end;
$$;

revoke all on function public.submit_workflow_photo_verification_v1(uuid,uuid,text) from public;
revoke execute on function public.submit_workflow_photo_verification_v1(uuid,uuid,text) from anon;
grant execute on function public.submit_workflow_photo_verification_v1(uuid,uuid,text) to authenticated;

comment on column public.workflow_executions_v2.checklist_state is
  'Snapshot operativo mutable del checklist congelado por ejecución. La receta permanece inmutable en spec_snapshot.';
comment on function public.save_workflow_definition_draft_v2(jsonb,uuid,bigint) is
  'Guarda autoría v2 mediante el saneador común, incluida la configuración Checklist, sin fabricar revisiones en guardados no-op.';
comment on function public.set_workflow_checklist_item_v1(uuid,text,boolean,text) is
  'Actualiza idempotentemente un elemento Checklist del asignado y sincroniza checklist, tarea, ejecución, histórico y cierre.';
