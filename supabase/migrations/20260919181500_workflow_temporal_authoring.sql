-- GestionPisos · Flujos · contrato de autoría temporal
-- Recurrente/Fecha concreta necesitan una fecha local, zona horaria IANA y
-- asignación resoluble por servidor. No activa todavía el scheduler.
--
-- Compatibilidad:
-- - las versiones publicadas históricas no se reescriben;
-- - un recurrente legacy sin ancla/zona sigue publicado, pero una edición
--   deberá completar estos datos antes de volver a publicarse;
-- - scheduledAt se reutiliza como primera ejecución para recurring.

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
  v_schedule_timezone text;
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
  v_schedule_timezone:=nullif(btrim(coalesce(p_spec->>'scheduleTimeZone','')),'');
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
    v_schedule_timezone:=null;
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
  if v_scheduled_at is not null then
    if v_scheduled_at !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}
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

  if v_trigger_type not in ('scheduled_once','recurring') then
    v_scheduled_at:=null;
    v_schedule_timezone:=null;
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
    'scheduleTimeZone',coalesce(v_schedule_timezone,''),
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
$sanitize$; then
      raise exception 'workflow_scheduled_at_invalid' using errcode='22023';
    end if;
    begin
      perform v_scheduled_at::timestamp without time zone;
    exception
      when datetime_field_overflow or invalid_datetime_format then
        raise exception 'workflow_scheduled_at_invalid' using errcode='22023';
    end;
  end if;

  if v_schedule_timezone is not null
    and not exists(
      select 1
      from pg_catalog.pg_timezone_names tz
      where tz.name=v_schedule_timezone
    ) then
    raise exception 'workflow_schedule_timezone_invalid' using errcode='22023';
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
        and coalesce(p_spec->>'scheduledAt','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}
    or (p_spec->>'assignmentType') not in ('property_responsible','active_occupants_rotation','fixed_person','role','manual')
    or (
      (p_spec->>'triggerType') in ('scheduled_once','recurring')
      and (
        (p_spec->>'assignmentType')<>'property_responsible'
        or (p_spec->>'scopeType') not in ('property','room','occupancy')
      )
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
        and char_length(btrim(coalesce(p_spec->>'scheduleTimeZone',''))) between 1 and 80
      )
      or (
        (p_spec->>'triggerType')='recurring'
        and coalesce(p_spec->>'scheduledAt','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}
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
        and char_length(btrim(coalesce(p_spec->>'scheduleTimeZone',''))) between 1 and 80
        and (
          (p_spec->>'recurrence') in ('weekly','biweekly','monthly')
          or (
            (p_spec->>'recurrence')='custom'
            and case
              when coalesce(p_spec->>'customEvery','') ~ '^[0-9]+
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

comment on function private.workflow_sanitize_authoring_spec_v2(jsonb) is
  'Sanea autoría v2 e incorpora scheduledAt + scheduleTimeZone para activaciones temporales. Valida zona IANA sin reescribir specs históricos.';

comment on function public.workflow_authoring_complete_v1(jsonb) is
  'Considera temporal completo solo con fecha/hora local, zona horaria y asignación property_responsible sobre ámbito con piso.';
