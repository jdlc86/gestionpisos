-- GestionPisos · WF-03 · contrato de autoría para Limpieza.
-- El primer adaptador de dominio usa una única tarjeta transversal y su propio
-- ciclo foto/auditoría. Por eso la receta genérica solo aporta Aceptar/Rechazar.

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
    or (p_spec->>'closeType') not in ('auto','human_review','domain_adapter')
    or (
      (p_spec->>'flowType')='cleaning'
      and (
        (p_spec->>'scopeType')='organization'
        or coalesce(p_spec#>>'{steps,accept}','false')<>'true'
        or coalesce(p_spec#>>'{steps,photo}','false')='true'
        or coalesce(p_spec#>>'{steps,checklist}','false')='true'
        or coalesce(p_spec#>>'{steps,document}','false')='true'
        or (p_spec->>'closeType')<>'domain_adapter'
      )
    ) then
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

comment on function public.workflow_authoring_complete_v1(jsonb) is
  'Valida una receta completa; WF-03 exige que Limpieza use ámbito con piso, Aceptar/Rechazar y cierre domain_adapter sin pasos genéricos paralelos.';
