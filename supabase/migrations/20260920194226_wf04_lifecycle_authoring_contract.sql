-- WF-04: nuevas recetas de Entrada/Salida usan el evento de negocio exacto
-- y el adaptador de dominio. Las versiones históricas de cierre genérico
-- siguen ejecutándose con su snapshot anterior, sin migración retroactiva.

alter function public.workflow_authoring_complete_v1(jsonb)
  rename to workflow_authoring_complete_pre_wf04_v1;
revoke all on function public.workflow_authoring_complete_pre_wf04_v1(jsonb)
  from public,anon,authenticated,service_role;

create function public.workflow_authoring_complete_v1(p_spec jsonb)
returns boolean
language plpgsql
immutable
security definer
set search_path=''
as $$
declare v_flow text:=coalesce(p_spec->>'flowType','');
begin
  if not public.workflow_authoring_complete_pre_wf04_v1(p_spec) then
    return false;
  end if;

  if v_flow in ('checkin','checkout') then
    return p_spec->>'scopeType' in ('property','room')
      and p_spec->>'triggerType'='event'
      and p_spec->>'eventType'=case v_flow
        when 'checkin' then 'occupancy.created'
        else 'occupancy.offboarded' end
      and p_spec->>'assignmentType' in
        ('property_responsible','fixed_person','role')
      and (
        p_spec->>'assignmentType'<>'role'
        or p_spec->>'assignmentRole' in ('admin','employee')
      )
      and p_spec#>>'{steps,accept}'='true'
      and coalesce(p_spec#>>'{steps,photo}','false')='false'
      and coalesce(p_spec#>>'{steps,checklist}','false')='false'
      and coalesce(p_spec#>>'{steps,document}','false')='false'
      and p_spec->>'closeType'='domain_adapter';
  end if;

  return true;
end;
$$;
revoke all on function public.workflow_authoring_complete_v1(jsonb)
  from public,anon,service_role;
grant execute on function public.workflow_authoring_complete_v1(jsonb)
  to authenticated;

comment on function public.workflow_authoring_complete_v1(jsonb) is
  'Validador transversal más contrato WF-04: Entrada y Salida nuevas exigen evento lifecycle exacto, piso/habitación, asignación operativa y cierre por adaptador sin pasos genéricos paralelos.';
