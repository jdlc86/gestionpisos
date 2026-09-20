-- WF-01 · Asignaciones genéricas. Base PostgreSQL desechable; rollback total.
begin;

select set_config('wf01.org',(
  select organization_id::text from public.user_roles
  where role='root' and revoked_at is null limit 1
),true);
select set_config('wf01.root',(
  select user_id::text from public.user_roles
  where role='root' and revoked_at is null limit 1
),true);
select set_config('wf01.owner',gen_random_uuid()::text,true);
select set_config('wf01.property',gen_random_uuid()::text,true);
select set_config('wf01.room1',gen_random_uuid()::text,true);
select set_config('wf01.room2',gen_random_uuid()::text,true);
select set_config('wf01.room3',gen_random_uuid()::text,true);
select set_config('wf01.employee',gen_random_uuid()::text,true);
select set_config('wf01.admin',gen_random_uuid()::text,true);
select set_config('wf01.tenant1',gen_random_uuid()::text,true);
select set_config('wf01.tenant2',gen_random_uuid()::text,true);
select set_config('wf01.tenant3',gen_random_uuid()::text,true);
select set_config('wf01.tenant_row1',gen_random_uuid()::text,true);
select set_config('wf01.tenant_row2',gen_random_uuid()::text,true);
select set_config('wf01.tenant_row3',gen_random_uuid()::text,true);
select set_config('wf01.occupancy1',gen_random_uuid()::text,true);
select set_config('wf01.occupancy2',gen_random_uuid()::text,true);
select set_config('wf01.occupancy3',gen_random_uuid()::text,true);

insert into auth.users(id) values
  (current_setting('wf01.employee')::uuid),
  (current_setting('wf01.admin')::uuid),
  (current_setting('wf01.tenant1')::uuid),
  (current_setting('wf01.tenant2')::uuid),
  (current_setting('wf01.tenant3')::uuid);

insert into public.profiles(user_id,organization_id,display_name,status)
values
  (current_setting('wf01.employee')::uuid,current_setting('wf01.org')::uuid,'WF01 empleado','active'),
  (current_setting('wf01.admin')::uuid,current_setting('wf01.org')::uuid,'WF01 admin','active');

insert into public.user_roles(user_id,organization_id,role)
values
  (current_setting('wf01.employee')::uuid,current_setting('wf01.org')::uuid,'employee'),
  (current_setting('wf01.admin')::uuid,current_setting('wf01.org')::uuid,'admin'),
  (current_setting('wf01.tenant1')::uuid,current_setting('wf01.org')::uuid,'tenant'),
  (current_setting('wf01.tenant2')::uuid,current_setting('wf01.org')::uuid,'tenant'),
  (current_setting('wf01.tenant3')::uuid,current_setting('wf01.org')::uuid,'tenant');

insert into public.owners(id,organization_id,full_name,status)
values(current_setting('wf01.owner')::uuid,current_setting('wf01.org')::uuid,'WF01 owner','active');
insert into public.properties_v2(id,organization_id,owner_id,name,address_line,status)
values(current_setting('wf01.property')::uuid,current_setting('wf01.org')::uuid,
       current_setting('wf01.owner')::uuid,'WF01 property','Regression only','active');
insert into public.rooms_v2(id,property_id,label,status)
values
  (current_setting('wf01.room1')::uuid,current_setting('wf01.property')::uuid,'WF01 A','active'),
  (current_setting('wf01.room2')::uuid,current_setting('wf01.property')::uuid,'WF01 B','active'),
  (current_setting('wf01.room3')::uuid,current_setting('wf01.property')::uuid,'WF01 C','active');

insert into public.property_staff_access_v3(
  organization_id,property_id,employee_user_id,assignment_type,can_write,granted_by
) values
  (current_setting('wf01.org')::uuid,current_setting('wf01.property')::uuid,
   current_setting('wf01.employee')::uuid,'access',false,current_setting('wf01.root')::uuid),
  (current_setting('wf01.org')::uuid,current_setting('wf01.property')::uuid,
   current_setting('wf01.admin')::uuid,'access',false,current_setting('wf01.root')::uuid);

insert into public.tenants_v2(
  id,organization_id,user_id,full_name,document_type,document_number,email,status
) values
  (current_setting('wf01.tenant_row1')::uuid,current_setting('wf01.org')::uuid,
   current_setting('wf01.tenant1')::uuid,'WF01 tenant A','other','WF01-A','wf01-a@example.invalid','active'),
  (current_setting('wf01.tenant_row2')::uuid,current_setting('wf01.org')::uuid,
   current_setting('wf01.tenant2')::uuid,'WF01 tenant B','other','WF01-B','wf01-b@example.invalid','active'),
  (current_setting('wf01.tenant_row3')::uuid,current_setting('wf01.org')::uuid,
   current_setting('wf01.tenant3')::uuid,'WF01 tenant C','other','WF01-C','wf01-c@example.invalid','active');

insert into public.occupancies_v2(
  id,organization_id,property_id,room_id,occupant_email,
  starts_on,ends_on,status,user_id,tenant_id
) values
  (current_setting('wf01.occupancy1')::uuid,current_setting('wf01.org')::uuid,
   current_setting('wf01.property')::uuid,current_setting('wf01.room1')::uuid,
   'wf01-a@example.invalid',current_date-2,null,'active',
   current_setting('wf01.tenant1')::uuid,current_setting('wf01.tenant_row1')::uuid),
  (current_setting('wf01.occupancy2')::uuid,current_setting('wf01.org')::uuid,
   current_setting('wf01.property')::uuid,current_setting('wf01.room2')::uuid,
   'wf01-b@example.invalid',current_date-2,null,'active',
   current_setting('wf01.tenant2')::uuid,current_setting('wf01.tenant_row2')::uuid);

create function pg_temp.wf01_spec(
  p_assignment text,
  p_scope text,
  p_fixed uuid default null,
  p_role text default null,
  p_trigger text default 'manual',
  p_first timestamptz default null
)
returns jsonb
language sql
stable
as $spec$
  select jsonb_build_object(
    'authoringVersion',2,'flowName','WF01 assignment regression',
    'flowType','custom','flowDescription','Regression only',
    'scopeType',p_scope,'triggerType',p_trigger,
    'recurrence',case when p_trigger='recurring' then 'weekly' else '' end,
    'scheduledAt',case when p_first is null then '' else
      to_char(p_first at time zone 'UTC','YYYY-MM-DD"T"HH24:MI') end,
    'scheduledTimezone',case when p_first is null then '' else 'UTC' end,
    'scheduledAtUtc',case when p_first is null then '' else
      to_char(p_first at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"') end,
    'customEvery','','customUnit','',
    'assignmentType',p_assignment,
    'assignmentUserId',coalesce(p_fixed::text,''),
    'assignmentRole',coalesce(p_role,''),
    'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
    'checklistItems','[]'::jsonb,
    'closeType','auto',
    'notifications',jsonb_build_object('onCreate',false,'onClose',false)
  );
$spec$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf01.root'),'role','authenticated','aal','aal2'
)::text,true);

do $invalid_configuration$
begin
  if public.workflow_authoring_complete_v1(
    pg_temp.wf01_spec('fixed_person','property')
  ) or public.workflow_authoring_complete_v1(
    pg_temp.wf01_spec('role','property',null,null)
  ) or public.workflow_authoring_complete_v1(
    pg_temp.wf01_spec('active_occupants_rotation','organization')
  ) or public.workflow_authoring_complete_v1(
    pg_temp.wf01_spec('role','organization',null,'tenant')
  ) then
    raise exception 'incomplete or impossible assignment configuration was accepted';
  end if;
end;
$invalid_configuration$;

do $root_not_executor$
begin
  begin
    perform * from public.publish_workflow_ready_v1(
      pg_temp.wf01_spec('fixed_person','property',current_setting('wf01.root')::uuid),
      current_setting('wf01.property')::uuid,null,null,'{}'::uuid[],true,
      'wf01-root-not-executor','wf01-root-first',null
    );
    raise exception 'ROOT was accepted as an operational assignee';
  exception when object_not_in_prerequisite_state then
    if sqlerrm<>'workflow_fixed_person_unavailable' then raise; end if;
  end;
end;
$root_not_executor$;

select set_config('wf01.fixed_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf01_spec('fixed_person','property',current_setting('wf01.employee')::uuid),
    current_setting('wf01.property')::uuid,null,null,'{}'::uuid[],true,
    'wf01-fixed-ready','wf01-fixed-first',null
  ) limit 1
),true);

do $fixed_positive$
declare v_execution public.workflow_executions_v2;
begin
  select * into v_execution from public.workflow_executions_v2
  where application_id=current_setting('wf01.fixed_app')::uuid
    and idempotency_key='wf01-fixed-first';
  if v_execution.assigned_user_id is distinct from current_setting('wf01.employee')::uuid
    or v_execution.spec_snapshot->>'assignmentUserId' is distinct from current_setting('wf01.employee')
    or not exists(
      select 1 from public.tenant_tasks_v2 t
      where t.source_kind='workflow_execution' and t.source_id=v_execution.id
        and t.assigned_user_id=v_execution.assigned_user_id
    ) then
    raise exception 'fixed-person assignment was not frozen in execution and task';
  end if;
end;
$fixed_positive$;

do $fixed_retry_and_override$
declare v_first uuid; v_retry record;
begin
  select id into v_first from public.workflow_executions_v2
  where application_id=current_setting('wf01.fixed_app')::uuid
    and idempotency_key='wf01-fixed-first';
  select * into v_retry from public.execute_workflow_application_now_v1(
    current_setting('wf01.fixed_app')::uuid,'wf01-fixed-first',null
  );
  if v_retry.execution_id is distinct from v_first or v_retry.created_new then
    raise exception 'fixed-person retry changed the assignment';
  end if;
  select * into v_retry from public.execute_workflow_application_now_v1(
    current_setting('wf01.fixed_app')::uuid,'wf01-fixed-first',null
  );
  if v_retry.execution_id is distinct from v_first or v_retry.created_new then
    raise exception 'second fixed-person retry changed the assignment';
  end if;
  begin
    perform * from public.execute_workflow_application_now_v1(
      current_setting('wf01.fixed_app')::uuid,'wf01-fixed-override',
      current_setting('wf01.admin')::uuid
    );
    raise exception 'client overrode a server-resolved assignee';
  exception when invalid_parameter_value then
    if sqlerrm<>'workflow_assignee_must_be_server_resolved' then raise; end if;
  end;
end;
$fixed_retry_and_override$;

select set_config('wf01.role_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf01_spec('role','property',null,'admin'),
    current_setting('wf01.property')::uuid,null,null,'{}'::uuid[],true,
    'wf01-role-ready','wf01-role-first',null
  ) limit 1
),true);

do $role_positive$
begin
  if not exists(
    select 1 from public.workflow_executions_v2 e
    join public.tenant_tasks_v2 t on t.source_kind='workflow_execution' and t.source_id=e.id
    where e.application_id=current_setting('wf01.role_app')::uuid
      and e.idempotency_key='wf01-role-first'
      and e.assigned_user_id=current_setting('wf01.admin')::uuid
      and t.assigned_user_id=e.assigned_user_id
      and e.spec_snapshot->>'assignmentRole'='admin'
  ) then
    raise exception 'role assignment did not use the current authorized admin';
  end if;
end;
$role_positive$;

select set_config('wf01.rotation_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf01_spec('active_occupants_rotation','property'),
    current_setting('wf01.property')::uuid,null,null,'{}'::uuid[],true,
    'wf01-rotation-ready','wf01-rotation-first',null
  ) limit 1
),true);

select * from public.execute_workflow_application_now_v1(
  current_setting('wf01.rotation_app')::uuid,'wf01-rotation-second',null
);

do $rotation_first_two$
declare v_first uuid; v_second uuid; v_retry record;
begin
  select assigned_user_id into v_first from public.workflow_executions_v2
  where application_id=current_setting('wf01.rotation_app')::uuid
    and idempotency_key='wf01-rotation-first';
  select assigned_user_id into v_second from public.workflow_executions_v2
  where application_id=current_setting('wf01.rotation_app')::uuid
    and idempotency_key='wf01-rotation-second';
  if v_first is null or v_second is null or v_first=v_second then
    raise exception 'rotation did not visit both current occupants';
  end if;
  select * into v_retry from public.execute_workflow_application_now_v1(
    current_setting('wf01.rotation_app')::uuid,'wf01-rotation-first',null
  );
  if v_retry.assigned_user_id is distinct from v_first or v_retry.created_new then
    raise exception 'rotation retry changed the frozen assignee';
  end if;
end;
$rotation_first_two$;

-- Automatic triggers use the same resolver and never persist a frozen
-- scheduled assignee for fixed/role/rotation.
select set_config('wf01.first_run',(
  date_trunc('minute',now())+interval '1 hour'
)::text,true);
select set_config('wf01.fixed_schedule_app',(
  select application_id::text
  from public.publish_workflow_ready_v2(
    pg_temp.wf01_spec('fixed_person','property',current_setting('wf01.employee')::uuid,
      null,'scheduled_once',current_setting('wf01.first_run')::timestamptz),
    current_setting('wf01.property')::uuid,null,null,'{}'::uuid[],false,
    'wf01-fixed-schedule-ready',null,null,'UTC',null
  ) limit 1
),true);
select set_config('wf01.role_schedule_app',(
  select application_id::text
  from public.publish_workflow_ready_v2(
    pg_temp.wf01_spec('role','property',null,'admin',
      'recurring',current_setting('wf01.first_run')::timestamptz),
    current_setting('wf01.property')::uuid,null,null,'{}'::uuid[],false,
    'wf01-role-schedule-ready',null,null,'UTC',null
  ) limit 1
),true);
select set_config('wf01.rotation_schedule_app',(
  select application_id::text
  from public.publish_workflow_ready_v2(
    pg_temp.wf01_spec('active_occupants_rotation','property',null,null,
      'recurring',current_setting('wf01.first_run')::timestamptz),
    current_setting('wf01.property')::uuid,null,null,'{}'::uuid[],false,
    'wf01-rotation-schedule-ready',null,null,'UTC',null
  ) limit 1
),true);

reset role;
do $scheduled_assignment$
declare v_app uuid; v_expected uuid; v_actual uuid;
begin
  perform private.process_due_workflow_schedules_v1(
    current_setting('wf01.first_run')::timestamptz+interval '1 minute'
  );
  for v_app,v_expected in
    select current_setting('wf01.fixed_schedule_app')::uuid,current_setting('wf01.employee')::uuid
    union all
    select current_setting('wf01.role_schedule_app')::uuid,current_setting('wf01.admin')::uuid
  loop
    select assigned_user_id into v_actual from public.workflow_executions_v2
    where application_id=v_app limit 1;
    if v_actual is distinct from v_expected then
      raise exception 'scheduled rule did not resolve current eligible assignee';
    end if;
  end loop;
  if not exists(
    select 1 from public.workflow_executions_v2
    where application_id=current_setting('wf01.rotation_schedule_app')::uuid
      and assigned_user_id in (
        current_setting('wf01.tenant1')::uuid,current_setting('wf01.tenant2')::uuid
      )
  ) then
    raise exception 'recurring rotation did not resolve an active occupant';
  end if;
  if exists(
    select 1 from public.workflow_application_schedules_v2
    where application_id in (
      current_setting('wf01.fixed_schedule_app')::uuid,
      current_setting('wf01.role_schedule_app')::uuid,
      current_setting('wf01.rotation_schedule_app')::uuid
    ) and scheduled_assigned_user_id is not null
  ) then
    raise exception 'dynamic assignment was frozen at scheduling time';
  end if;
end;
$scheduled_assignment$;

-- Suspension/Baja remove eligibility immediately, without changing history.
update public.property_staff_access_v3
set revoked_at=now()
where property_id=current_setting('wf01.property')::uuid
  and employee_user_id=current_setting('wf01.employee')::uuid;
update public.user_roles
set revoked_at=now()
where organization_id=current_setting('wf01.org')::uuid
  and user_id=current_setting('wf01.admin')::uuid
  and role='admin';

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf01.root'),'role','authenticated','aal','aal2'
)::text,true);

do $staff_revocation$
begin
  begin
    perform * from public.execute_workflow_application_now_v1(
      current_setting('wf01.fixed_app')::uuid,'wf01-fixed-after-revoke',null
    );
    raise exception 'revoked fixed person was still eligible';
  exception when object_not_in_prerequisite_state then
    if sqlerrm<>'workflow_fixed_person_unavailable' then raise; end if;
  end;
  begin
    perform * from public.execute_workflow_application_now_v1(
      current_setting('wf01.role_app')::uuid,'wf01-role-after-revoke',null
    );
    raise exception 'revoked role member was still eligible';
  exception when object_not_in_prerequisite_state then
    if sqlerrm<>'workflow_assignment_role_unavailable' then raise; end if;
  end;
end;
$staff_revocation$;

-- The current actor gate enforces revocation even for an already created task.
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf01.employee'),'role','authenticated','aal','aal1'
)::text,true);
do $fixed_actor_revoked$
begin
  if public.workflow_execution_actor_current_v1((
    select id from public.workflow_executions_v2
    where application_id=current_setting('wf01.fixed_app')::uuid
      and idempotency_key='wf01-fixed-first'
  )) is distinct from false then
    raise exception 'revoked fixed person retained task access';
  end if;
end;
$fixed_actor_revoked$;

reset role;
update public.occupancies_v2
set status='blocked',ends_on=current_date-1
where id=(
  select case when e.assigned_user_id=current_setting('wf01.tenant1')::uuid
    then current_setting('wf01.occupancy1')::uuid
    else current_setting('wf01.occupancy2')::uuid end
  from public.workflow_executions_v2 e
  where e.application_id=current_setting('wf01.rotation_app')::uuid
    and e.idempotency_key='wf01-rotation-first'
);
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(
    select assigned_user_id from public.workflow_executions_v2
    where application_id=current_setting('wf01.rotation_app')::uuid
      and idempotency_key='wf01-rotation-first'
  ),'role','authenticated','aal','aal1'
)::text,true);
set local role authenticated;
do $suspended_actor_revoked$
begin
  if public.workflow_execution_actor_current_v1((
    select id from public.workflow_executions_v2
    where application_id=current_setting('wf01.rotation_app')::uuid
      and idempotency_key='wf01-rotation-first'
  )) is distinct from false then
    raise exception 'suspended occupant retained historical task access';
  end if;
end;
$suspended_actor_revoked$;
reset role;
select set_config('wf01.remaining_tenant',(
  select case when e.assigned_user_id=current_setting('wf01.tenant1')::uuid
    then current_setting('wf01.tenant2')
    else current_setting('wf01.tenant1') end
  from public.workflow_executions_v2 e
  where e.application_id=current_setting('wf01.rotation_app')::uuid
    and e.idempotency_key='wf01-rotation-first'
),true);

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf01.root'),'role','authenticated','aal','aal2'
)::text,true);
select * from public.execute_workflow_application_now_v1(
  current_setting('wf01.rotation_app')::uuid,'wf01-rotation-after-suspension',null
);
do $rotation_after_suspension$
begin
  if not exists(
    select 1 from public.workflow_executions_v2
    where application_id=current_setting('wf01.rotation_app')::uuid
      and idempotency_key='wf01-rotation-after-suspension'
      and assigned_user_id=current_setting('wf01.remaining_tenant')::uuid
  ) then
    raise exception 'suspended occupant stayed in rotation';
  end if;
end;
$rotation_after_suspension$;

reset role;
insert into public.occupancies_v2(
  id,organization_id,property_id,room_id,occupant_email,
  starts_on,ends_on,status,user_id,tenant_id
) values(
  current_setting('wf01.occupancy3')::uuid,current_setting('wf01.org')::uuid,
  current_setting('wf01.property')::uuid,current_setting('wf01.room3')::uuid,
  'wf01-c@example.invalid',current_date,null,'active',
  current_setting('wf01.tenant3')::uuid,current_setting('wf01.tenant_row3')::uuid
);

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf01.root'),'role','authenticated','aal','aal2'
)::text,true);
select * from public.execute_workflow_application_now_v1(
  current_setting('wf01.rotation_app')::uuid,'wf01-rotation-after-entry',null
);
do $rotation_after_entry$
begin
  if not exists(
    select 1 from public.workflow_executions_v2
    where application_id=current_setting('wf01.rotation_app')::uuid
      and idempotency_key='wf01-rotation-after-entry'
      and assigned_user_id=current_setting('wf01.tenant3')::uuid
  ) then
    raise exception 'new active occupant did not join future rotation';
  end if;
  if (
    select count(*) from public.workflow_executions_v2
    where application_id=current_setting('wf01.rotation_app')::uuid
      and idempotency_key in ('wf01-rotation-first','wf01-rotation-second')
  )<>2 then
    raise exception 'historical rotations were changed';
  end if;
end;
$rotation_after_entry$;

reset role;
update public.occupancies_v2
set status='blocked'
where property_id=current_setting('wf01.property')::uuid
  and status='active';

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf01.root'),'role','authenticated','aal','aal2'
)::text,true);
do $rotation_empty$
begin
  begin
    perform * from public.execute_workflow_application_now_v1(
      current_setting('wf01.rotation_app')::uuid,'wf01-rotation-empty',null
    );
    raise exception 'empty rotation created a task';
  exception when object_not_in_prerequisite_state then
    if sqlerrm<>'workflow_rotation_no_active_occupants' then raise; end if;
  end;
end;
$rotation_empty$;

-- Non-assignees and anonymous sessions cannot use the workflow API.
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf01.tenant3'),'role','authenticated','aal','aal1'
)::text,true);
do $rls_negative$
begin
  if exists(
    select 1 from public.workflow_executions_v2
    where application_id=current_setting('wf01.fixed_app')::uuid
  ) then
    raise exception 'unrelated tenant could read fixed-person execution';
  end if;
end;
$rls_negative$;

reset role;
set local role anon;
do $anon_negative$
begin
  begin
    perform * from public.execute_workflow_application_now_v1(
      current_setting('wf01.fixed_app')::uuid,'wf01-anon',null
    );
    raise exception 'anon executed a workflow';
  exception when insufficient_privilege then null;
  end;
end;
$anon_negative$;

reset role;
rollback;
