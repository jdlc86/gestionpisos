-- GestionPisos · Workflow human-review access hardening
-- Follow-up posterior a 20260918233000_workflow_human_review.
-- No modifica ni reemplaza la política legacy de lectura.
--
-- PostgreSQL combina políticas PERMISSIVE con OR y políticas RESTRICTIVE con AND.
-- La política existente decide si el usuario puede leer acciones de la tarea;
-- esta barrera adicional limita únicamente las acciones de tareas workflow
-- según el actor declarado en tenant_task_actions_v2.

drop policy if exists tenant_task_actions_v2_workflow_actor_gate
  on public.tenant_task_actions_v2;

create policy tenant_task_actions_v2_workflow_actor_gate
as restrictive
on public.tenant_task_actions_v2
for select
to authenticated
using (
  exists(
    select 1
    from public.tenant_tasks_v2 t
    where t.id=tenant_task_actions_v2.task_id
      and (
        -- Legacy queda intacto: esta política restrictiva devuelve TRUE.
        t.task_type<>'workflow'
        or t.source_kind is distinct from 'workflow_execution'
        or (
          t.task_type='workflow'
          and t.source_kind='workflow_execution'
          and (
            (
              tenant_task_actions_v2.actor='assignee'
              and t.assigned_user_id=auth.uid()
            )
            or (
              tenant_task_actions_v2.actor='agency'
              and public.workflow_can_manage_v1(t.organization_id)
            )
            or (
              tenant_task_actions_v2.actor='tenant'
              and exists(
                select 1
                from public.tenants_v2 tn
                where tn.id=t.tenant_id
                  and tn.user_id=auth.uid()
              )
            )
          )
        )
      )
  )
);

comment on policy tenant_task_actions_v2_workflow_actor_gate
  on public.tenant_task_actions_v2 is
  'Barrera RLS restrictiva: en tareas workflow el actor de la acción controla su visibilidad; las tareas legacy no cambian.';
