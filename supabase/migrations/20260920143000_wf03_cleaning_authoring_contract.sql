-- GestionPisos · WF-03 · contrato de autoría para Limpieza.
-- Preserva íntegramente el validador transversal vigente y añade solo la
-- restricción especializada de WF-03.

alter function public.workflow_authoring_complete_v1(jsonb)
  rename to workflow_authoring_complete_core_v1;

revoke all on function public.workflow_authoring_complete_core_v1(jsonb)
  from public,anon,authenticated,service_role;

create or replace function public.workflow_authoring_complete_v1(p_spec jsonb)
returns boolean
language plpgsql
immutable
security definer
set search_path=''
as $workflow_cleaning_authoring_gate$
begin
  if not public.workflow_authoring_complete_core_v1(p_spec) then
    return false;
  end if;

  if coalesce(p_spec->>'flowType','')='cleaning' and (
    coalesce(p_spec->>'scopeType','')='organization'
    or coalesce(p_spec#>>'{steps,accept}','false')<>'true'
    or coalesce(p_spec#>>'{steps,photo}','false')='true'
    or coalesce(p_spec#>>'{steps,checklist}','false')='true'
    or coalesce(p_spec#>>'{steps,document}','false')='true'
    or coalesce(p_spec->>'closeType','')<>'domain_adapter'
  ) then
    return false;
  end if;

  return true;
end;
$workflow_cleaning_authoring_gate$;

revoke all on function public.workflow_authoring_complete_v1(jsonb)
  from public,anon,authenticated,service_role;
grant execute on function public.workflow_authoring_complete_v1(jsonb)
  to authenticated;

comment on function public.workflow_authoring_complete_v1(jsonb) is
  'Validador transversal vigente más contrato WF-03: Limpieza requiere ámbito con piso, Aceptar/Rechazar y cierre domain_adapter sin pasos genéricos paralelos.';
comment on function public.workflow_authoring_complete_core_v1(jsonb) is
  'Validador transversal previo a WF-03, encapsulado para conservar todos los contratos de autoría existentes sin exponer un bypass al cliente.';
