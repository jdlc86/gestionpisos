-- GestionPisos · WF-07 post-merge hardening
--
-- apply_workflow_task_action_pre_wf07_v1() es una implementación supersedida
-- conservada únicamente como helper interno del router vigente. No debe ser un
-- RPC cliente ni una superficie service-role independiente.
--
-- El router público actual es SECURITY DEFINER propiedad de postgres, por lo
-- que puede seguir invocando esta función por derecho del propietario aunque
-- se retire EXECUTE de los roles externos.

revoke all on function public.apply_workflow_task_action_pre_wf07_v1(
  uuid,text,text,text
) from public,anon,authenticated,service_role;

comment on function public.apply_workflow_task_action_pre_wf07_v1(
  uuid,text,text,text
) is
  'Router workflow supersedido por WF-07. Helper interno exclusivamente; sin EXECUTE para roles externos.';
