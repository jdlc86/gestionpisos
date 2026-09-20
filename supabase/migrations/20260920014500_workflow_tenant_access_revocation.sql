-- GestionPisos · Flujos · revocación de acceso del inquilino cuando deja de ser vigente
-- Complementa la asignación manual al inquilino de una ocupación.
-- La autorización se vuelve a evaluar en lecturas y en RPCs operativos; no se
-- reescribe la identidad histórica de la ejecución ni de la tarea.

create or replace function public.workflow_execution_actor_current_v1(
  p_execution_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_execution public.workflow_executions_v2;
  v_is_linked_tenant boolean:=false;
begin
  if v_actor is null or p_execution_id is null then
    return false;
  end if;

  select *
  into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id;

  if v_execution.id is null then
    return false;
  end if;

  -- ROOT/ADMIN conservan acceso administrativo aunque la misma cuenta hubiera
  -- tenido previamente una relación personal con la ocupación.
  if public.workflow_can_read_definitions_v1(v_execution.organization_id) then
    return true;
  end if;

  -- Un empleado activo asignado conserva el contrato operativo existente.
  if v_execution.assigned_user_id=v_actor
    and exists(
      select 1
      from public.user_roles ur
      where ur.user_id=v_actor
        and ur.organization_id=v_execution.organization_id
        and ur.role='employee'
        and ur.revoked_at is null
    ) then
    return true;
  end if;

  -- Un propietario activo asignado no queda sometido por accidente a la
  -- vigencia de una ocupación si una cuenta acumula relaciones históricas.
  if v_execution.assigned_user_id=v_actor
    and exists(
      select 1
      from public.owners o
      where o.user_id=v_actor
        and o.organization_id=v_execution.organization_id
        and o.status='active'
    ) then
    return true;
  end if;

  if v_execution.scope_type='occupancy'
    and v_execution.occupancy_id is not null then

    select exists(
      select 1
      from public.occupancies_v2 o
      left join public.tenants_v2 t
        on t.id=o.tenant_id
       and t.organization_id=o.organization_id
      where o.id=v_execution.occupancy_id
        and o.organization_id=v_execution.organization_id
        and (o.user_id=v_actor or t.user_id=v_actor)
    )
    into v_is_linked_tenant;

    if v_is_linked_tenant then
      return exists(
        select 1
        from public.occupancies_v2 o
        join public.tenants_v2 t
          on t.id=o.tenant_id
         and t.organization_id=o.organization_id
        where o.id=v_execution.occupancy_id
          and o.organization_id=v_execution.organization_id
          and o.property_id=v_execution.property_id
          and o.status='active'
          and o.starts_on is not null
          and o.starts_on<=current_date
          and (o.ends_on is null or o.ends_on>=current_date)
          and o.user_id=v_actor
          and t.user_id=v_actor
          and t.status='active'
          and t.archived_at is null
      );
    end if;
  end if;

  -- Para actores no-tenants se conserva el contrato de asignación existente.
  return v_execution.assigned_user_id=v_actor;
end;
$$;

revoke all on function public.workflow_execution_actor_current_v1(uuid)
  from public,anon,authenticated;
grant execute on function public.workflow_execution_actor_current_v1(uuid)
  to authenticated,service_role;

comment on function public.workflow_execution_actor_current_v1(uuid) is
  'Revalida acceso actual a una ejecución. Un tenant ligado al scope occupancy pierde acceso al expirar/suspenderse su ocupación o identidad; gestores y otros asignados conservan su contrato previo.';

create or replace function private.workflow_require_current_actor_v1(
  p_execution_id uuid
)
returns void
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if public.workflow_execution_actor_current_v1(p_execution_id) is distinct from true then
    raise exception 'workflow_assignee_access_revoked' using errcode='42501';
  end if;
end;
$$;

revoke all on function private.workflow_require_current_actor_v1(uuid)
  from public,anon,authenticated,service_role;

-- Lectura de la ejecución: el ID asignado ya no basta para un tenant cuya
-- ocupación dejó de estar vigente.
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

-- Lectura de tareas. Se conservan las reglas no-workflow sin cambios.
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

-- La policy restrictiva de acciones es suficiente para negar el workflow a un
-- tenant expirado sin reescribir la policy permisiva histórica de alcance.
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

-- Evidencias documentales y fotográficas de workflow tampoco quedan
-- accesibles por el mero ID histórico del assignee.
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

-- Storage documental: conserva las reglas de identidad existentes y añade
-- la revalidación de vigencia.
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

-- Conservamos la implementación probada de los RPCs y ponemos delante un
-- wrapper pequeño que revalida vigencia. Los originales dejan de ser
-- invocables directamente por roles API.
alter function public.apply_workflow_task_action_v1(uuid,text,text,text)
  set schema private;
revoke all on function private.apply_workflow_task_action_v1(uuid,text,text,text)
  from public,anon,authenticated,service_role;

create or replace function public.apply_workflow_task_action_v1(
  p_task_id uuid,
  p_action_key text,
  p_request_key text,
  p_note text default null
)
returns table(
  task_id uuid,
  task_status text,
  execution_id uuid,
  execution_status text,
  applied_new boolean
)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_execution_id uuid;
begin
  select source_id
  into v_execution_id
  from public.tenant_tasks_v2
  where id=p_task_id
    and source_kind='workflow_execution';

  if v_execution_id is not null then
    perform private.workflow_require_current_actor_v1(v_execution_id);
  end if;

  return query
  select *
  from private.apply_workflow_task_action_v1(
    p_task_id,p_action_key,p_request_key,p_note
  );
end;
$$;

revoke all on function public.apply_workflow_task_action_v1(uuid,text,text,text)
  from public,anon,authenticated;
grant execute on function public.apply_workflow_task_action_v1(uuid,text,text,text)
  to authenticated,service_role;

alter function public.set_workflow_checklist_item_v1(uuid,text,boolean,text)
  set schema private;
revoke all on function private.set_workflow_checklist_item_v1(uuid,text,boolean,text)
  from public,anon,authenticated,service_role;

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
set search_path=''
as $$
declare
  v_execution_id uuid;
begin
  select source_id
  into v_execution_id
  from public.tenant_tasks_v2
  where id=p_task_id
    and source_kind='workflow_execution';

  if v_execution_id is not null then
    perform private.workflow_require_current_actor_v1(v_execution_id);
  end if;

  return query
  select *
  from private.set_workflow_checklist_item_v1(
    p_task_id,p_item_key,p_completed,p_request_key
  );
end;
$$;

revoke all on function public.set_workflow_checklist_item_v1(uuid,text,boolean,text)
  from public,anon,authenticated;
grant execute on function public.set_workflow_checklist_item_v1(uuid,text,boolean,text)
  to authenticated,service_role;

alter function public.prepare_workflow_document_upload_v1(uuid,text,text,bigint,text)
  set schema private;
revoke all on function private.prepare_workflow_document_upload_v1(uuid,text,text,bigint,text)
  from public,anon,authenticated,service_role;

create or replace function public.prepare_workflow_document_upload_v1(
  p_task_id uuid,
  p_original_filename text,
  p_mime_type text,
  p_size_bytes bigint,
  p_request_key text
)
returns table(
  document_id uuid,
  storage_path text,
  document_status text,
  task_status text,
  execution_status text,
  created_new boolean
)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_execution_id uuid;
begin
  select source_id
  into v_execution_id
  from public.tenant_tasks_v2
  where id=p_task_id
    and source_kind='workflow_execution';

  if v_execution_id is not null then
    perform private.workflow_require_current_actor_v1(v_execution_id);
  end if;

  return query
  select *
  from private.prepare_workflow_document_upload_v1(
    p_task_id,p_original_filename,p_mime_type,p_size_bytes,p_request_key
  );
end;
$$;

revoke all on function public.prepare_workflow_document_upload_v1(uuid,text,text,bigint,text)
  from public,anon,authenticated;
grant execute on function public.prepare_workflow_document_upload_v1(uuid,text,text,bigint,text)
  to authenticated,service_role;

alter function public.submit_workflow_document_v1(uuid,text)
  set schema private;
revoke all on function private.submit_workflow_document_v1(uuid,text)
  from public,anon,authenticated,service_role;

create or replace function public.submit_workflow_document_v1(
  p_document_id uuid,
  p_request_key text
)
returns table(
  document_id uuid,
  document_status text,
  all_documents_complete boolean,
  task_status text,
  execution_status text,
  applied_new boolean
)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_execution_id uuid;
begin
  select execution_id
  into v_execution_id
  from public.workflow_execution_documents_v2
  where id=p_document_id;

  if v_execution_id is not null then
    perform private.workflow_require_current_actor_v1(v_execution_id);
  end if;

  return query
  select *
  from private.submit_workflow_document_v1(
    p_document_id,p_request_key
  );
end;
$$;

revoke all on function public.submit_workflow_document_v1(uuid,text)
  from public,anon,authenticated;
grant execute on function public.submit_workflow_document_v1(uuid,text)
  to authenticated,service_role;

alter function public.start_workflow_photo_verification_v1(uuid)
  set schema private;
revoke all on function private.start_workflow_photo_verification_v1(uuid)
  from public,anon,authenticated,service_role;

create or replace function public.start_workflow_photo_verification_v1(
  p_execution_photo_resource_id uuid
)
returns table(
  photo_resource_id uuid,
  run_id uuid,
  organization_id uuid,
  property_id uuid,
  room_id uuid,
  pattern_id uuid,
  pattern_version integer,
  created_new boolean
)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_execution_id uuid;
begin
  select execution_id
  into v_execution_id
  from public.workflow_execution_photo_resources_v2
  where id=p_execution_photo_resource_id;

  if v_execution_id is not null then
    perform private.workflow_require_current_actor_v1(v_execution_id);
  end if;

  return query
  select *
  from private.start_workflow_photo_verification_v1(
    p_execution_photo_resource_id
  );
end;
$$;

revoke all on function public.start_workflow_photo_verification_v1(uuid)
  from public,anon,authenticated;
grant execute on function public.start_workflow_photo_verification_v1(uuid)
  to authenticated,service_role;

alter function public.submit_workflow_photo_verification_v1(uuid,uuid,text)
  set schema private;
revoke all on function private.submit_workflow_photo_verification_v1(uuid,uuid,text)
  from public,anon,authenticated,service_role;

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
set search_path=''
as $$
declare
  v_execution_id uuid;
begin
  select source_id
  into v_execution_id
  from public.photo_verification_runs_v2
  where id=p_run_id
    and source_type='workflow_execution';

  if v_execution_id is not null then
    perform private.workflow_require_current_actor_v1(v_execution_id);
  end if;

  return query
  select *
  from private.submit_workflow_photo_verification_v1(
    p_run_id,p_item_id,p_request_key
  );
end;
$$;

revoke all on function public.submit_workflow_photo_verification_v1(uuid,uuid,text)
  from public,anon,authenticated;
grant execute on function public.submit_workflow_photo_verification_v1(uuid,uuid,text)
  to authenticated,service_role;
