-- GestionPisos · Workflow human-review access hardening
-- Follow-up posterior a 20260918233000_workflow_human_review.
-- No modifica la migración histórica ya aplicada.
-- Hace actor-aware la lectura de acciones de tarea workflow.

drop policy if exists tenant_task_actions_v2_read_scope
  on public.tenant_task_actions_v2;

drop policy if exists tenant_task_actions_v2_workflow_manager_read
  on public.tenant_task_actions_v2;

create policy tenant_task_actions_v2_read_scope
on public.tenant_task_actions_v2
for select
to authenticated
using (
  exists(
    select 1
    from public.tenant_tasks_v2 t
    where t.id=tenant_task_actions_v2.task_id
      and (
        (
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
        or (
          (t.task_type<>'workflow' or t.source_kind is distinct from 'workflow_execution')
          and (
            public.can_operate_property_v3(t.property_id,false)
            or t.assigned_user_id=auth.uid()
            or exists(
              select 1
              from public.tenants_v2 tn
              where tn.id=t.tenant_id
                and tn.user_id=auth.uid()
            )
          )
        )
      )
  )
);

comment on policy tenant_task_actions_v2_read_scope
  on public.tenant_task_actions_v2 is
  'Legacy conserva visibilidad histórica; workflow filtra acciones por actor: assignee para asignado, agency para gestores autorizados y tenant para el inquilino vinculado.';
