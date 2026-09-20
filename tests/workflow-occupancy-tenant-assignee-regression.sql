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
do $prerequisites$
begin
  if nullif(current_setting('gestionpisos.tenant_assignee.org',true),'') is null
    or nullif(current_setting('gestionpisos.tenant_assignee.root',true),'') is null then
    raise exception 'tenant workflow assignee prerequisites missing';
  end if;
end;
$prerequisites$;

select set_config('gestionpisos.tenant_assignee.owner',gen_random_uuid()::text,true);
select set_config('gestionpisos.tenant_assignee.property',gen_random_uuid()::text,true);

select set_config('gestionpisos.tenant_assignee.user','88888888-8888-4888-8888-888888888881',true);
select set_config('gestionpisos.tenant_assignee.foreign_user','88888888-8888-4888-8888-888888888882',true);
select set_config('gestionpisos.tenant_assignee.employee_user','88888888-8888-4888-8888-888888888883',true);
select set_config('gestionpisos.tenant_assignee.tenant',gen_random_uuid()::text,true);
select set_config('gestionpisos.tenant_assignee.foreign_tenant',gen_random_uuid()::text,true);
select set_config('gestionpisos.tenant_assignee.room',gen_random_uuid()::text,true);
select set_config('gestionpisos.tenant_assignee.occupancy',gen_random_uuid()::text,true);

insert into public.owners(id,organization_id,full_name,status)
values(
  current_setting('gestionpisos.tenant_assignee.owner')::uuid,
  current_setting('gestionpisos.tenant_assignee.org')::uuid,
  'Workflow tenant assignee owner',
  'active'
);

insert into public.properties_v2(
  id,organization_id,owner_id,name,address_line,status
) values(
  current_setting('gestionpisos.tenant_assignee.property')::uuid,
  current_setting('gestionpisos.tenant_assignee.org')::uuid,
  current_setting('gestionpisos.tenant_assignee.owner')::uuid,
  'Workflow tenant assignee property',
  'Regression only',
  'active'
);

insert into auth.users(id)
values
  (current_setting('gestionpisos.tenant_assignee.user')::uuid),
  (current_setting('gestionpisos.tenant_assignee.foreign_user')::uuid),
  (current_setting('gestionpisos.tenant_assignee.employee_user')::uuid)
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
  ),
  (
    current_setting('gestionpisos.tenant_assignee.employee_user')::uuid,
    current_setting('gestionpisos.tenant_assignee.org')::uuid,
    'employee'
  )
on conflict do nothing;

insert into public.property_staff_access_v3(
  organization_id,property_id,employee_user_id,assignment_type,can_write,granted_by
) values(
  current_setting('gestionpisos.tenant_assignee.org')::uuid,
  current_setting('gestionpisos.tenant_assignee.property')::uuid,
  current_setting('gestionpisos.tenant_assignee.employee_user')::uuid,
  'access',
  false,
  current_setting('gestionpisos.tenant_assignee.root')::uuid
);

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
  current_date-2,
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

select set_config(
  'gestionpisos.tenant_assignee.task',
  (
    select id::text
    from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('gestionpisos.tenant_assignee.execution')::uuid
    limit 1
  ),
  true
);

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

-- Un destino Inquilino nunca convierte a ROOT en ejecutor por defecto.
do $occupancy_root_denied$
begin
  perform *
  from public.execute_workflow_application_now_v1(
    current_setting('gestionpisos.tenant_assignee.application')::uuid,
    'tenant-assignee-root-forbidden-001',
    current_setting('gestionpisos.tenant_assignee.root')::uuid
  );
  raise exception 'root unexpectedly accepted as occupancy assignee';
exception
  when insufficient_privilege then
    if sqlerrm<>'workflow_manual_assignee_not_eligible' then
      raise;
    end if;
end;
$occupancy_root_denied$;

-- Piso: puede ejecutar un empleado asociado incluso con acceso general de
-- lectura; la asignación explícita de la tarea es la capacidad operativa.
select set_config(
  'gestionpisos.tenant_assignee.property_application',
  (
    select application_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Workflow de piso por relación',
        'flowType','custom',
        'flowDescription','Regresión de ejecutores asociados al piso',
        'scopeType','property',
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
      null,
      '{}'::uuid[],
      true,
      'property-assignee-ready-001',
      'property-assignee-employee-001',
      current_setting('gestionpisos.tenant_assignee.employee_user')::uuid
    )
    limit 1
  ),
  true
);

-- El inquilino activo del mismo piso también es ejecutor válido.
select *
from public.execute_workflow_application_now_v1(
  current_setting('gestionpisos.tenant_assignee.property_application')::uuid,
  'property-assignee-tenant-001',
  current_setting('gestionpisos.tenant_assignee.user')::uuid
);

-- ROOT administra el flujo pero no aparece como ejecutor operativo del piso.
do $property_root_denied$
begin
  perform *
  from public.execute_workflow_application_now_v1(
    current_setting('gestionpisos.tenant_assignee.property_application')::uuid,
    'property-assignee-root-forbidden-001',
    current_setting('gestionpisos.tenant_assignee.root')::uuid
  );
  raise exception 'root unexpectedly accepted as property assignee';
exception
  when insufficient_privilege then
    if sqlerrm<>'workflow_manual_assignee_not_eligible' then
      raise;
    end if;
end;
$property_root_denied$;

-- Habitación: el inquilino que ocupa esa habitación es válido.
select set_config(
  'gestionpisos.tenant_assignee.room_application',
  (
    select application_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Workflow de habitación por relación',
        'flowType','custom',
        'flowDescription','Regresión de ejecutores asociados a habitación',
        'scopeType','room',
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
      current_setting('gestionpisos.tenant_assignee.room')::uuid,
      null,
      '{}'::uuid[],
      true,
      'room-assignee-ready-001',
      'room-assignee-tenant-001',
      current_setting('gestionpisos.tenant_assignee.user')::uuid
    )
    limit 1
  ),
  true
);

-- El personal asociado al piso también puede ejecutar una tarea de habitación.
select *
from public.execute_workflow_application_now_v1(
  current_setting('gestionpisos.tenant_assignee.room_application')::uuid,
  'room-assignee-employee-001',
  current_setting('gestionpisos.tenant_assignee.employee_user')::uuid
);

-- Mientras la ocupación sigue vigente, el inquilino asignado ve ejecución,
-- tarea y acciones.
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.tenant_assignee.user'),
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

do $tenant_current_access$
begin
  if public.workflow_execution_actor_current_v1(
    current_setting('gestionpisos.tenant_assignee.execution')::uuid
  ) is distinct from true then
    raise exception 'current occupancy tenant unexpectedly lost workflow access';
  end if;

  if (
    select count(*)
    from public.workflow_executions_v2
    where id=current_setting('gestionpisos.tenant_assignee.execution')::uuid
  )<>1 then
    raise exception 'current occupancy tenant cannot read assigned execution';
  end if;

  if (
    select count(*)
    from public.tenant_tasks_v2
    where id=current_setting('gestionpisos.tenant_assignee.task')::uuid
  )<>1 then
    raise exception 'current occupancy tenant cannot read assigned task';
  end if;

  if (
    select count(*)
    from public.tenant_task_actions_v2
    where task_id=current_setting('gestionpisos.tenant_assignee.task')::uuid
  )<1 then
    raise exception 'current occupancy tenant cannot read task actions';
  end if;
end;
$tenant_current_access$;

-- La relación termina después de asignar. La identidad histórica queda intacta,
-- pero ya no concede lectura ni acción.
reset role;
update public.occupancies_v2
set ends_on=current_date-1
where id=current_setting('gestionpisos.tenant_assignee.occupancy')::uuid;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.tenant_assignee.user'),
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

do $tenant_expired_access_revoked$
begin
  if public.workflow_execution_actor_current_v1(
    current_setting('gestionpisos.tenant_assignee.execution')::uuid
  ) is distinct from false then
    raise exception 'expired occupancy tenant retained workflow access';
  end if;

  if exists(
    select 1
    from public.workflow_executions_v2
    where id=current_setting('gestionpisos.tenant_assignee.execution')::uuid
  ) then
    raise exception 'expired occupancy tenant can still read execution';
  end if;

  if exists(
    select 1
    from public.tenant_tasks_v2
    where id=current_setting('gestionpisos.tenant_assignee.task')::uuid
  ) then
    raise exception 'expired occupancy tenant can still read task';
  end if;

  if exists(
    select 1
    from public.tenant_task_actions_v2
    where task_id=current_setting('gestionpisos.tenant_assignee.task')::uuid
  ) then
    raise exception 'expired occupancy tenant can still read task actions';
  end if;

  begin
    perform *
    from public.apply_workflow_task_action_v1(
      current_setting('gestionpisos.tenant_assignee.task')::uuid,
      'accept',
      'tenant-assignee-expired-action-001',
      null
    );
    raise exception 'expired occupancy tenant unexpectedly applied workflow action';
  exception
    when insufficient_privilege then
      if sqlerrm<>'workflow_assignee_access_revoked' then
        raise;
      end if;
  end;
end;
$tenant_expired_access_revoked$;

reset role;
rollback;
