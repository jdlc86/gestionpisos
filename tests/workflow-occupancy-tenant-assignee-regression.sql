-- Flujos · regresión de asignación manual al inquilino de una ocupación.
-- PostgreSQL desechable. Todo se revierte.

begin;

select set_config(
  'gestionpisos.tenant_assignee.org',
  (select organization_id::text
   from public.user_roles
   where role='root' and revoked_at is null
   limit 1),
  true
);
select set_config(
  'gestionpisos.tenant_assignee.root',
  (select user_id::text
   from public.user_roles
   where role='root' and revoked_at is null
   limit 1),
  true
);
select set_config(
  'gestionpisos.tenant_assignee.property',
  (
    select id::text
    from public.properties_v2
    where organization_id=current_setting('gestionpisos.tenant_assignee.org')::uuid
      and archived_at is null
      and status<>'archived'
    order by created_at
    limit 1
  ),
  true
);

do $prerequisites$
begin
  if nullif(current_setting('gestionpisos.tenant_assignee.org',true),'') is null
    or nullif(current_setting('gestionpisos.tenant_assignee.root',true),'') is null
    or nullif(current_setting('gestionpisos.tenant_assignee.property',true),'') is null then
    raise exception 'tenant workflow assignee prerequisites missing';
  end if;
end;
$prerequisites$;

select set_config('gestionpisos.tenant_assignee.user','88888888-8888-4888-8888-888888888881',true);
select set_config('gestionpisos.tenant_assignee.foreign_user','88888888-8888-4888-8888-888888888882',true);
select set_config('gestionpisos.tenant_assignee.tenant',gen_random_uuid()::text,true);
select set_config('gestionpisos.tenant_assignee.foreign_tenant',gen_random_uuid()::text,true);
select set_config('gestionpisos.tenant_assignee.room',gen_random_uuid()::text,true);
select set_config('gestionpisos.tenant_assignee.occupancy',gen_random_uuid()::text,true);

insert into auth.users(id)
values
  (current_setting('gestionpisos.tenant_assignee.user')::uuid),
  (current_setting('gestionpisos.tenant_assignee.foreign_user')::uuid)
on conflict(id) do nothing;

insert into public.user_roles(user_id,organization_id,role)
values
  (
    current_setting('gestionpisos.tenant_assignee.user')::uuid,
    current_setting('gestionpisos.tenant_assignee.org')::uuid,
    'tenant'
  ),
  (
    current_setting('gestionpisos.tenant_assignee.foreign_user')::uuid,
    current_setting('gestionpisos.tenant_assignee.org')::uuid,
    'tenant'
  )
on conflict do nothing;

insert into public.tenants_v2(
  id,organization_id,user_id,full_name,document_type,document_number,email,status
) values
(
  current_setting('gestionpisos.tenant_assignee.tenant')::uuid,
  current_setting('gestionpisos.tenant_assignee.org')::uuid,
  current_setting('gestionpisos.tenant_assignee.user')::uuid,
  'Workflow occupancy tenant',
  'other',
  'WF-OCC-TENANT-1',
  'workflow-occupancy-tenant@example.invalid',
  'active'
),
(
  current_setting('gestionpisos.tenant_assignee.foreign_tenant')::uuid,
  current_setting('gestionpisos.tenant_assignee.org')::uuid,
  current_setting('gestionpisos.tenant_assignee.foreign_user')::uuid,
  'Workflow foreign tenant',
  'other',
  'WF-OCC-TENANT-2',
  'workflow-foreign-tenant@example.invalid',
  'active'
);

insert into public.rooms_v2(id,property_id,label,status)
values(
  current_setting('gestionpisos.tenant_assignee.room')::uuid,
  current_setting('gestionpisos.tenant_assignee.property')::uuid,
  'Workflow tenant assignee room',
  'active'
);

insert into public.occupancies_v2(
  id,organization_id,property_id,room_id,occupant_email,starts_on,ends_on,status,user_id,tenant_id
) values(
  current_setting('gestionpisos.tenant_assignee.occupancy')::uuid,
  current_setting('gestionpisos.tenant_assignee.org')::uuid,
  current_setting('gestionpisos.tenant_assignee.property')::uuid,
  current_setting('gestionpisos.tenant_assignee.room')::uuid,
  'workflow-occupancy-tenant@example.invalid',
  current_date,
  null,
  'active',
  current_setting('gestionpisos.tenant_assignee.user')::uuid,
  current_setting('gestionpisos.tenant_assignee.tenant')::uuid
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.tenant_assignee.root'),
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

select set_config(
  'gestionpisos.tenant_assignee.application',
  (
    select application_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Workflow asignado a inquilino',
        'flowType','custom',
        'flowDescription','Regresión de asignación manual al inquilino del destino',
        'scopeType','occupancy',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object(
          'accept',true,
          'photo',false,
          'checklist',false,
          'document',false
        ),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      current_setting('gestionpisos.tenant_assignee.property')::uuid,
      null,
      current_setting('gestionpisos.tenant_assignee.occupancy')::uuid,
      '{}'::uuid[],
      true,
      'tenant-assignee-ready-001',
      'tenant-assignee-execute-001',
      current_setting('gestionpisos.tenant_assignee.user')::uuid
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.tenant_assignee.execution',
  (
    select id::text
    from public.workflow_executions_v2
    where application_id=current_setting('gestionpisos.tenant_assignee.application')::uuid
      and idempotency_key='tenant-assignee-execute-001'
    limit 1
  ),
  true
);

do $linked_tenant_assigned$
declare
  v_execution_user uuid;
  v_task_user uuid;
  v_task_tenant uuid;
begin
  select assigned_user_id
  into v_execution_user
  from public.workflow_executions_v2
  where id=current_setting('gestionpisos.tenant_assignee.execution')::uuid;

  select assigned_user_id,tenant_id
  into v_task_user,v_task_tenant
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('gestionpisos.tenant_assignee.execution')::uuid;

  if v_execution_user<>current_setting('gestionpisos.tenant_assignee.user')::uuid
    or v_task_user<>current_setting('gestionpisos.tenant_assignee.user')::uuid
    or v_task_tenant<>current_setting('gestionpisos.tenant_assignee.tenant')::uuid then
    raise exception 'linked occupancy tenant was not preserved as execution/task assignee';
  end if;
end;
$linked_tenant_assigned$;

do $foreign_tenant_denied$
begin
  perform *
  from public.execute_workflow_application_now_v1(
    current_setting('gestionpisos.tenant_assignee.application')::uuid,
    'tenant-assignee-foreign-001',
    current_setting('gestionpisos.tenant_assignee.foreign_user')::uuid
  );
  raise exception 'foreign tenant unexpectedly accepted as occupancy assignee';
exception
  when insufficient_privilege then
    if sqlerrm<>'workflow_manual_assignee_not_eligible' then
      raise;
    end if;
end;
$foreign_tenant_denied$;

reset role;
rollback;
