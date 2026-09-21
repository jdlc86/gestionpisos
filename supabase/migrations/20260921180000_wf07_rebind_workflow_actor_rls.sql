-- GestionPisos · WF-07 · re-enlace RLS al gate de actor vigente
--
-- WF-07 renombra workflow_execution_actor_current_v1() para conservar el
-- comportamiento previo y publica un wrapper nuevo. PostgreSQL liga las
-- expresiones de POLICY al OID de la función; renombrar no cambia ese OID.
-- Por tanto, las policies creadas antes del wrapper seguirían evaluando
-- workflow_execution_actor_current_pre_wf07_v1(). Se recrean SIN ampliar
-- permisos ni cambiar predicados para enlazarlas al gate WF-07 actual.

drop policy if exists workflow_executions_v2_read_authorized
  on public.workflow_executions_v2;
create policy workflow_executions_v2_read_authorized
on public.workflow_executions_v2
for select
to authenticated
using (
  public.workflow_can_read_definitions_v1(organization_id)
  or (
    assigned_user_id=auth.uid()
    and public.workflow_execution_actor_current_v1(id)
  )
);

drop policy if exists tenant_tasks_v2_assignee_read
  on public.tenant_tasks_v2;
create policy tenant_tasks_v2_assignee_read
on public.tenant_tasks_v2
for select
to authenticated
using (
  assigned_user_id=auth.uid()
  and (
    source_kind is distinct from 'workflow_execution'
    or source_id is null
    or public.workflow_execution_actor_current_v1(source_id)
  )
);

drop policy if exists tenant_tasks_v2_tenant_read
  on public.tenant_tasks_v2;
create policy tenant_tasks_v2_tenant_read
on public.tenant_tasks_v2
for select
to authenticated
using (
  tenant_id is not null
  and exists(
    select 1
    from public.tenants_v2 tn
    where tn.id=tenant_tasks_v2.tenant_id
      and tn.user_id=auth.uid()
  )
  and (
    source_kind is distinct from 'workflow_execution'
    or source_id is null
    or public.workflow_execution_actor_current_v1(source_id)
  )
);

drop policy if exists tenant_task_actions_v2_workflow_actor_gate
  on public.tenant_task_actions_v2;
create policy tenant_task_actions_v2_workflow_actor_gate
on public.tenant_task_actions_v2
as restrictive
for select
to authenticated
using (
  exists(
    select 1
    from public.tenant_tasks_v2 t
    where t.id=tenant_task_actions_v2.task_id
      and (
        t.task_type<>'workflow'
        or t.source_kind is distinct from 'workflow_execution'
        or (
          t.task_type='workflow'
          and t.source_kind='workflow_execution'
          and (
            (
              tenant_task_actions_v2.actor='assignee'
              and t.assigned_user_id=auth.uid()
              and public.workflow_execution_actor_current_v1(t.source_id)
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
              and public.workflow_execution_actor_current_v1(t.source_id)
            )
          )
        )
      )
  )
);

drop policy if exists workflow_execution_documents_v2_read
  on public.workflow_execution_documents_v2;
create policy workflow_execution_documents_v2_read
on public.workflow_execution_documents_v2
for select
to authenticated
using (
  public.workflow_can_read_definitions_v1(organization_id)
  or (
    public.workflow_execution_actor_current_v1(execution_id)
    and (
      uploaded_by=(select auth.uid())
      or exists(
        select 1
        from public.workflow_executions_v2 e
        where e.id=workflow_execution_documents_v2.execution_id
          and e.assigned_user_id=(select auth.uid())
      )
    )
  )
);

drop policy if exists workflow_execution_photo_resources_v2_read
  on public.workflow_execution_photo_resources_v2;
create policy workflow_execution_photo_resources_v2_read
on public.workflow_execution_photo_resources_v2
for select
to authenticated
using (
  public.workflow_can_read_definitions_v1(organization_id)
  or (
    public.workflow_execution_actor_current_v1(execution_id)
    and exists(
      select 1
      from public.workflow_executions_v2 e
      where e.id=workflow_execution_photo_resources_v2.execution_id
        and e.assigned_user_id=auth.uid()
    )
  )
);

drop policy if exists photo_runs_actor_read
  on public.photo_verification_runs_v2;
create policy photo_runs_actor_read
on public.photo_verification_runs_v2
for select
to authenticated
using (
  public.photo_verification_can_review_v1(organization_id::text)
  or (
    actor_user_id=auth.uid()
    and (
      source_type<>'workflow_execution'
      or source_id is null
      or public.workflow_execution_actor_current_v1(source_id)
    )
  )
);

drop policy if exists photo_items_actor_read
  on public.photo_verification_items_v2;
create policy photo_items_actor_read
on public.photo_verification_items_v2
for select
to authenticated
using (
  exists(
    select 1
    from public.photo_verification_runs_v2 r
    where r.id=photo_verification_items_v2.run_id
      and (
        public.photo_verification_can_review_v1(r.organization_id::text)
        or (
          r.actor_user_id=auth.uid()
          and (
            r.source_type<>'workflow_execution'
            or r.source_id is null
            or public.workflow_execution_actor_current_v1(r.source_id)
          )
        )
      )
  )
);

drop policy if exists photo_items_actor_insert
  on public.photo_verification_items_v2;
create policy photo_items_actor_insert
on public.photo_verification_items_v2
for insert
to authenticated
with check (
  exists(
    select 1
    from public.photo_verification_runs_v2 r
    join public.photo_patterns_v2 p
      on p.id=photo_verification_items_v2.pattern_id
    where r.id=photo_verification_items_v2.run_id
      and r.actor_user_id=(select auth.uid())
      and r.status='capturing'
      and p.property_id=r.property_id
      and p.organization_id=r.organization_id
      and p.active=true
      and (
        r.source_type<>'workflow_execution'
        or r.source_id is null
        or public.workflow_execution_actor_current_v1(r.source_id)
      )
  )
  and ai_score is null
  and ai_result is null
  and manual_result is null
  and reviewed_by is null
  and reviewed_at is null
);

drop policy if exists workflow_documents_storage_insert
  on storage.objects;
create policy workflow_documents_storage_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id='workflow-documents-v2'
  and exists(
    select 1
    from public.workflow_execution_documents_v2 d
    join public.workflow_executions_v2 e on e.id=d.execution_id
    join public.tenant_tasks_v2 t on t.id=d.task_id
    where d.storage_path=storage.objects.name
      and d.status='uploading'
      and d.uploaded_by=(select auth.uid())
      and e.organization_id=d.organization_id
      and e.assigned_user_id=(select auth.uid())
      and t.source_kind='workflow_execution'
      and t.source_id=e.id
      and t.assigned_user_id=(select auth.uid())
      and t.status in ('pending','active')
      and e.status=t.status
      and public.workflow_execution_actor_current_v1(e.id)
  )
);

drop policy if exists workflow_documents_storage_select
  on storage.objects;
create policy workflow_documents_storage_select
on storage.objects
for select
to authenticated
using (
  bucket_id='workflow-documents-v2'
  and exists(
    select 1
    from public.workflow_execution_documents_v2 d
    join public.workflow_executions_v2 e on e.id=d.execution_id
    where d.storage_path=storage.objects.name
      and (
        public.workflow_can_read_definitions_v1(d.organization_id)
        or (
          public.workflow_execution_actor_current_v1(e.id)
          and (
            d.uploaded_by=(select auth.uid())
            or e.assigned_user_id=(select auth.uid())
          )
        )
      )
  )
);

comment on function public.workflow_execution_actor_current_v1(uuid) is
  'Gate de actor vigente. WF-07 añade validación estricta para fianza/daños; las policies RLS dependientes se re-enlazan al wrapper actual.';
