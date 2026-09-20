-- GestionPisos · WF-03 · opt-in explícito del adaptador de Limpieza.
-- Definiciones históricas flowType=cleaning con cierre genérico deben seguir
-- usando únicamente el motor transversal. El adaptador especializado entra
-- solo cuando el snapshot fija closeType=domain_adapter.

alter function private.workflow_ensure_cleaning_domain_task_v1(uuid,uuid)
  rename to workflow_ensure_cleaning_domain_task_core_v1;

revoke all on function private.workflow_ensure_cleaning_domain_task_core_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

create or replace function private.workflow_ensure_cleaning_domain_task_v1(
  p_execution_id uuid,
  p_actor_user_id uuid
)
returns public.cleaning_tasks_v2
language plpgsql
security definer
set search_path=''
as $workflow_cleaning_adapter_gate$
declare
  v_execution public.workflow_executions_v2;
begin
  select *
  into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id;

  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  if coalesce(v_execution.spec_snapshot->>'flowType','')<>'cleaning'
    or coalesce(v_execution.spec_snapshot->>'closeType','')<>'domain_adapter' then
    return null;
  end if;

  return private.workflow_ensure_cleaning_domain_task_core_v1(
    p_execution_id,
    p_actor_user_id
  );
end;
$workflow_cleaning_adapter_gate$;

revoke all on function private.workflow_ensure_cleaning_domain_task_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

comment on function private.workflow_ensure_cleaning_domain_task_v1(uuid,uuid) is
  'Puerta WF-03: solo materializa expediente especializado para flowType=cleaning + closeType=domain_adapter; Limpiezas históricas con cierre genérico permanecen en el motor transversal.';
comment on function private.workflow_ensure_cleaning_domain_task_core_v1(uuid,uuid) is
  'Implementación interna de materialización de dominio WF-03, invocada exclusivamente tras la puerta explícita del adaptador.';
