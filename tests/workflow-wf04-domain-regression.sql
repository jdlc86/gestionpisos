-- WF-04 · Entrada/Salida y llaves. Base local desechable; rollback total.
begin;

select set_config('wf04.org','11111111-1111-4111-8111-111111111111',true);
select set_config('wf04.root','22222222-2222-4222-8222-222222222222',true);
select set_config('wf04.owner',gen_random_uuid()::text,true);
select set_config('wf04.property',gen_random_uuid()::text,true);
select set_config('wf04.room',gen_random_uuid()::text,true);
select set_config('wf04.future_room',gen_random_uuid()::text,true);
select set_config('wf04.staff',gen_random_uuid()::text,true);
select set_config('wf04.outsider',gen_random_uuid()::text,true);
select set_config('wf04.tenant_user',gen_random_uuid()::text,true);
select set_config('wf04.future_user',gen_random_uuid()::text,true);
select set_config('wf04.tenant',gen_random_uuid()::text,true);
select set_config('wf04.future_tenant',gen_random_uuid()::text,true);
select set_config('wf04.occupancy',gen_random_uuid()::text,true);
select set_config('wf04.future_occupancy',gen_random_uuid()::text,true);

insert into auth.users(id) values
  (current_setting('wf04.staff')::uuid),
  (current_setting('wf04.outsider')::uuid),
  (current_setting('wf04.tenant_user')::uuid),
  (current_setting('wf04.future_user')::uuid);

insert into public.profiles(user_id,organization_id,display_name,status) values
  (current_setting('wf04.staff')::uuid,current_setting('wf04.org')::uuid,'WF04 staff','active'),
  (current_setting('wf04.outsider')::uuid,current_setting('wf04.org')::uuid,'WF04 outsider','active');

insert into public.user_roles(user_id,organization_id,role) values
  (current_setting('wf04.staff')::uuid,current_setting('wf04.org')::uuid,'employee'),
  (current_setting('wf04.outsider')::uuid,current_setting('wf04.org')::uuid,'employee'),
  (current_setting('wf04.tenant_user')::uuid,current_setting('wf04.org')::uuid,'tenant'),
  (current_setting('wf04.future_user')::uuid,current_setting('wf04.org')::uuid,'tenant');

insert into public.owners(id,organization_id,full_name,status)
values(current_setting('wf04.owner')::uuid,current_setting('wf04.org')::uuid,
       'WF04 owner','active');
insert into public.properties_v2(
  id,organization_id,owner_id,name,address_line,status
) values (
  current_setting('wf04.property')::uuid,current_setting('wf04.org')::uuid,
  current_setting('wf04.owner')::uuid,'WF04 property','Regression only','active'
);
insert into public.rooms_v2(id,property_id,label,status) values
  (current_setting('wf04.room')::uuid,current_setting('wf04.property')::uuid,'WF04 room','active'),
  (current_setting('wf04.future_room')::uuid,current_setting('wf04.property')::uuid,'WF04 future room','active');
insert into public.property_staff_access_v3(
  organization_id,property_id,employee_user_id,assignment_type,can_write,granted_by
) values (
  current_setting('wf04.org')::uuid,current_setting('wf04.property')::uuid,
  current_setting('wf04.staff')::uuid,'responsible',true,current_setting('wf04.root')::uuid
);

insert into public.tenants_v2(
  id,organization_id,user_id,full_name,document_type,document_number,email,status
) values
  (current_setting('wf04.tenant')::uuid,current_setting('wf04.org')::uuid,
   current_setting('wf04.tenant_user')::uuid,'WF04 tenant','other','WF04-TENANT',
   'wf04-tenant@example.invalid','active'),
  (current_setting('wf04.future_tenant')::uuid,current_setting('wf04.org')::uuid,
   current_setting('wf04.future_user')::uuid,'WF04 future tenant','other','WF04-FUTURE',
   'wf04-future@example.invalid','active');

create function pg_temp.wf04_spec(p_flow text)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'authoringVersion',2,
    'flowName',case p_flow when 'checkin' then 'WF04 entrada' else 'WF04 salida' end,
    'flowType',p_flow,'flowDescription','WF04 regression only',
    'scopeType','property','triggerType','event',
    'eventType',case p_flow when 'checkin' then 'occupancy.created'
      else 'occupancy.offboarded' end,
    'recurrence','','scheduledAt','','scheduledTimezone','','scheduledAtUtc','',
    'customEvery','','customUnit','','assignmentType','property_responsible',
    'assignmentUserId','','assignmentRole','',
    'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
    'checklistItems','[]'::jsonb,'closeType','domain_adapter',
    'notifications',jsonb_build_object('onCreate',false,'onClose',false)
  );
$$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.root'),'role','authenticated','aal','aal2'
)::text,true);
select set_config('wf04.checkin_app',(
  select application_id::text from public.publish_workflow_ready_v1(
    pg_temp.wf04_spec('checkin'),current_setting('wf04.property')::uuid,
    null,null,'{}'::uuid[],false,'wf04-checkin-ready',null,null
  ) limit 1
),true);
select set_config('wf04.checkout_app',(
  select application_id::text from public.publish_workflow_ready_v1(
    pg_temp.wf04_spec('checkout'),current_setting('wf04.property')::uuid,
    null,null,'{}'::uuid[],false,'wf04-checkout-ready',null,null
  ) limit 1
),true);
reset role;

insert into public.occupancies_v2(
  id,organization_id,tenant_id,property_id,room_id,occupant_email,
  starts_on,ends_on,status,user_id
) values (
  current_setting('wf04.occupancy')::uuid,current_setting('wf04.org')::uuid,
  current_setting('wf04.tenant')::uuid,current_setting('wf04.property')::uuid,
  current_setting('wf04.room')::uuid,'wf04-tenant@example.invalid',
  current_date-1,null,'active',current_setting('wf04.tenant_user')::uuid
);

do $event_before_dispatch$
begin
  if (
    select count(*) from public.workflow_event_outbox_v2
    where source_id=current_setting('wf04.occupancy')::uuid
      and event_type='occupancy.created' and status='pending'
  )<>1 then
    raise exception 'WF04 occupancy creation was not captured once';
  end if;
  if exists(
    select 1 from public.workflow_executions_v2
    where application_id=current_setting('wf04.checkin_app')::uuid
  ) then
    raise exception 'WF04 business insert synchronously created a task';
  end if;
end;
$event_before_dispatch$;

select private.process_pending_workflow_events_v1(50);
select set_config('wf04.checkin_task',(
  select t.id::text from public.tenant_tasks_v2 t
  join public.workflow_executions_v2 e on e.id=t.source_id
  join public.workflow_event_outbox_v2 o on o.id=e.source_event_id
  where e.application_id=current_setting('wf04.checkin_app')::uuid
    and o.source_id=current_setting('wf04.occupancy')::uuid
    and o.event_type='occupancy.created'
),true);

do $checkin_materialized$
declare v_task public.tenant_tasks_v2;
begin
  select * into v_task from public.tenant_tasks_v2
  where id=current_setting('wf04.checkin_task')::uuid;
  if v_task.id is null
    or v_task.tenant_id is distinct from current_setting('wf04.tenant')::uuid
    or v_task.assigned_user_id is distinct from current_setting('wf04.staff')::uuid
    or v_task.status<>'pending' then
    raise exception 'WF04 check-in did not bind one task to exact tenant/assignee';
  end if;
  if (
    select count(*) from public.workflow_executions_v2 e
    where e.application_id=current_setting('wf04.checkin_app')::uuid
      and e.source_event_id=(
        select id from public.workflow_event_outbox_v2
        where source_id=current_setting('wf04.occupancy')::uuid
          and event_type='occupancy.created'
      )
  )<>1 then
    raise exception 'WF04 check-in execution count is not one';
  end if;
  if (
    select count(*) from public.tenant_task_actions_v2 a
    where a.task_id=v_task.id and a.active
      and a.action_key in ('accept','reject')
  )<>2 then
    raise exception 'WF04 accept/reject actions were not seeded';
  end if;
end;
$checkin_materialized$;

-- La elegibilidad se reevalúa al actuar, no solo al despachar.
update public.property_staff_access_v3
set revoked_at=now()
where property_id=current_setting('wf04.property')::uuid
  and employee_user_id=current_setting('wf04.staff')::uuid;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.staff'),'role','authenticated'
)::text,true);
do $revoked_assignee_denied$
begin
  begin
    perform * from public.apply_workflow_task_action_v1(
      current_setting('wf04.checkin_task')::uuid,'accept','wf04-revoked',null
    );
    raise exception 'revoked assignee accepted WF04 task';
  exception when insufficient_privilege then
    if sqlerrm<>'workflow_assignee_access_revoked' then raise; end if;
  end;
end;
$revoked_assignee_denied$;
reset role;
update public.property_staff_access_v3
set revoked_at=null
where property_id=current_setting('wf04.property')::uuid
  and employee_user_id=current_setting('wf04.staff')::uuid;

-- La concesión aún no vigente tampoco autoriza la acción.
update public.property_staff_access_v3
set valid_from=now()+interval '1 day'
where property_id=current_setting('wf04.property')::uuid
  and employee_user_id=current_setting('wf04.staff')::uuid;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.staff'),'role','authenticated'
)::text,true);
do $future_assignment_denied$
begin
  begin
    perform * from public.apply_workflow_task_action_v1(
      current_setting('wf04.checkin_task')::uuid,'accept','wf04-future-assignment',null
    );
    raise exception 'future assignment accepted WF04 task';
  exception when insufficient_privilege then
    if sqlerrm<>'workflow_wf04_assignee_not_eligible' then raise; end if;
  end;
end;
$future_assignment_denied$;
reset role;
update public.property_staff_access_v3
set valid_from=now()-interval '1 day'
where property_id=current_setting('wf04.property')::uuid
  and employee_user_id=current_setting('wf04.staff')::uuid;

-- La habitación origen del evento no puede sustituirse por otra vigente.
update public.occupancies_v2
set room_id=current_setting('wf04.future_room')::uuid
where id=current_setting('wf04.occupancy')::uuid;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.staff'),'role','authenticated'
)::text,true);
do $wrong_subject_denied$
begin
  begin
    perform * from public.apply_workflow_task_action_v1(
      current_setting('wf04.checkin_task')::uuid,'accept','wf04-wrong-room',null
    );
    raise exception 'moved occupancy accepted WF04 event';
  exception when object_not_in_prerequisite_state then
    if sqlerrm<>'workflow_wf04_subject_not_current' then raise; end if;
  end;
end;
$wrong_subject_denied$;
reset role;
update public.occupancies_v2
set room_id=current_setting('wf04.room')::uuid
where id=current_setting('wf04.occupancy')::uuid;

-- Otro empleado y el propio inquilino carecen de autoridad sobre esta tarea.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.outsider'),'role','authenticated'
)::text,true);
do $outsider_denied$
begin
  if (
    select count(*) from public.tenant_tasks_v2
    where id=current_setting('wf04.checkin_task')::uuid
  )<>0 then
    raise exception 'out-of-scope employee could read WF04 task';
  end if;
  begin
    perform * from public.apply_workflow_task_action_v1(
      current_setting('wf04.checkin_task')::uuid,'accept','wf04-outsider',null
    );
    raise exception 'out-of-scope employee accepted WF04 task';
  exception when insufficient_privilege then
    if sqlerrm not in ('workflow_assignee_access_revoked','workflow_wf04_assignee_not_eligible') then raise; end if;
  end;
end;
$outsider_denied$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.tenant_user'),'role','authenticated'
)::text,true);
do $tenant_denied$
begin
  if (
    select count(*) from public.tenant_tasks_v2
    where id=current_setting('wf04.checkin_task')::uuid
  )<>0 then
    raise exception 'tenant could read a staff-only WF04 task';
  end if;
  begin
    perform * from public.apply_workflow_task_action_v1(
      current_setting('wf04.checkin_task')::uuid,'accept','wf04-tenant',null
    );
    raise exception 'tenant accepted staff WF04 task';
  exception when insufficient_privilege then
    if sqlerrm<>'workflow_assignee_access_revoked' then raise; end if;
  end;
end;
$tenant_denied$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.staff'),'role','authenticated'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf04.checkin_task')::uuid,'accept','wf04-accept',null
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf04.checkin_task')::uuid,'key_pickup','wf04-key-pickup',null
);
do $key_retry$
declare v_result record;
begin
  select * into v_result from public.apply_workflow_task_action_v1(
    current_setting('wf04.checkin_task')::uuid,'key_pickup','wf04-key-pickup',null
  );
  if v_result.applied_new is distinct from false then
    raise exception 'key retry applied a second handover';
  end if;
end;
$key_retry$;
reset role;

do $key_no_access_effect$
begin
  if not exists(
    select 1 from public.occupancies_v2
    where id=current_setting('wf04.occupancy')::uuid
      and status='active' and starts_on=current_date-1
  ) or not exists(
    select 1 from public.user_roles
    where user_id=current_setting('wf04.tenant_user')::uuid
      and role='tenant' and revoked_at is null
  ) or (
    select count(*) from public.workflow_execution_events_v2 ev
    join public.workflow_executions_v2 e on e.id=ev.execution_id
    where e.application_id=current_setting('wf04.checkin_app')::uuid
      and ev.event_type='wf04_domain_action'
      and ev.details->>'action_key'='key_pickup'
  )<>1 then
    raise exception 'key pickup changed lifecycle/access or duplicated history';
  end if;
end;
$key_no_access_effect$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.staff'),'role','authenticated'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf04.checkin_task')::uuid,'check_in','wf04-check-in',null
);
reset role;

do $checkin_finished$
begin
  if not exists(
    select 1 from public.tenant_tasks_v2 t
    join public.workflow_executions_v2 e on e.id=t.source_id
    where t.id=current_setting('wf04.checkin_task')::uuid
      and t.status='completed' and e.status='completed'
  ) then
    raise exception 'check-in did not close task and execution together';
  end if;
  if private.process_pending_workflow_events_v1(50)<>0 then
    raise exception 'processed check-in event was replayed';
  end if;
end;
$checkin_finished$;

-- Baja (no Suspensión) corta acceso antes de cualquier acción de llaves.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.root'),'role','authenticated','aal','aal2'
)::text,true);
select public.offboard_tenant_occupancy_v2(
  current_setting('wf04.occupancy')::uuid,current_date
);
reset role;

do $checkout_before_dispatch$
begin
  if not exists(
    select 1 from public.workflow_event_outbox_v2
    where source_id=current_setting('wf04.occupancy')::uuid
      and event_type='occupancy.offboarded' and status='pending'
  ) or exists(
    select 1 from public.workflow_executions_v2
    where application_id=current_setting('wf04.checkout_app')::uuid
  ) then
    raise exception 'Baja failed outbox decoupling';
  end if;
end;
$checkout_before_dispatch$;

select private.process_pending_workflow_events_v1(50);
select set_config('wf04.checkout_task',(
  select t.id::text from public.tenant_tasks_v2 t
  join public.workflow_executions_v2 e on e.id=t.source_id
  join public.workflow_event_outbox_v2 o on o.id=e.source_event_id
  where e.application_id=current_setting('wf04.checkout_app')::uuid
    and o.source_id=current_setting('wf04.occupancy')::uuid
    and o.event_type='occupancy.offboarded'
),true);

do $checkout_materialized$
begin
  if (
    select count(*) from public.tenant_tasks_v2
    where id=current_setting('wf04.checkout_task')::uuid
      and tenant_id=current_setting('wf04.tenant')::uuid
      and status='pending'
  )<>1 then
    raise exception 'Baja did not create one linked checkout card';
  end if;
  if not exists(
    select 1 from public.occupancies_v2
    where id=current_setting('wf04.occupancy')::uuid and status='archived'
  ) or not exists(
    select 1 from public.user_roles
    where user_id=current_setting('wf04.tenant_user')::uuid
      and role='tenant' and revoked_at is not null
  ) then
    raise exception 'Baja failed to preserve history and revoke access';
  end if;
end;
$checkout_materialized$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.tenant_user'),'role','authenticated'
)::text,true);
do $offboarded_access_denied$
begin
  if public.has_current_platform_access_v1() then
    raise exception 'offboarded tenant retained platform access';
  end if;
end;
$offboarded_access_denied$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.staff'),'role','authenticated'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf04.checkout_task')::uuid,'accept','wf04-checkout-accept',null
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf04.checkout_task')::uuid,'key_delivery','wf04-key-delivery',null
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf04.checkout_task')::uuid,'check_out','wf04-check-out',null
);
reset role;

do $checkout_finished$
begin
  if not exists(
    select 1 from public.tenant_tasks_v2 t
    join public.workflow_executions_v2 e on e.id=t.source_id
    where t.id=current_setting('wf04.checkout_task')::uuid
      and t.status='completed' and e.status='completed'
  ) or not exists(
    select 1 from public.occupancies_v2
    where id=current_setting('wf04.occupancy')::uuid and status='archived'
  ) or (
    select count(*) from public.workflow_execution_events_v2 ev
    join public.workflow_executions_v2 e on e.id=ev.execution_id
    where e.application_id=current_setting('wf04.checkout_app')::uuid
      and ev.event_type='wf04_domain_action'
      and ev.details->>'action_key'='key_delivery'
  )<>1 then
    raise exception 'checkout/key delivery was not idempotent or changed lifecycle';
  end if;
end;
$checkout_finished$;

-- Una ocupación futura permite organizar llaves pero no confirmar Entrada ni
-- habilita acceso del inquilino antes de starts_on.
insert into public.occupancies_v2(
  id,organization_id,tenant_id,property_id,room_id,occupant_email,
  starts_on,ends_on,status,user_id
) values (
  current_setting('wf04.future_occupancy')::uuid,current_setting('wf04.org')::uuid,
  current_setting('wf04.future_tenant')::uuid,current_setting('wf04.property')::uuid,
  current_setting('wf04.future_room')::uuid,'wf04-future@example.invalid',
  current_date+5,null,'active',current_setting('wf04.future_user')::uuid
);
select private.process_pending_workflow_events_v1(50);
select set_config('wf04.future_task',(
  select t.id::text from public.tenant_tasks_v2 t
  join public.workflow_executions_v2 e on e.id=t.source_id
  join public.workflow_event_outbox_v2 o on o.id=e.source_event_id
  where e.application_id=current_setting('wf04.checkin_app')::uuid
    and o.source_id=current_setting('wf04.future_occupancy')::uuid
),true);

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.staff'),'role','authenticated'
)::text,true);
do $reject_requires_note$
begin
  begin
    perform * from public.apply_workflow_task_action_v1(
      current_setting('wf04.future_task')::uuid,'reject','wf04-future-reject',null
    );
    raise exception 'WF04 rejection without note was accepted';
  exception when invalid_parameter_value then
    if sqlerrm<>'workflow_action_note_required' then raise; end if;
  end;
end;
$reject_requires_note$;
select * from public.apply_workflow_task_action_v1(
  current_setting('wf04.future_task')::uuid,'accept','wf04-future-accept',null
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf04.future_task')::uuid,'key_pickup','wf04-future-key',null
);
do $future_checkin_denied$
begin
  begin
    perform * from public.apply_workflow_task_action_v1(
      current_setting('wf04.future_task')::uuid,'check_in','wf04-future-checkin',null
    );
    raise exception 'future check-in was confirmed early';
  exception when object_not_in_prerequisite_state then
    if sqlerrm<>'workflow_wf04_checkin_not_current' then raise; end if;
  end;
end;
$future_checkin_denied$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.future_user'),'role','authenticated'
)::text,true);
do $future_access_denied$
begin
  if public.has_current_platform_access_v1() then
    raise exception 'future key pickup enabled tenant access';
  end if;
end;
$future_access_denied$;
reset role;

-- Las tarjetas legacy permanecen en su ruta y no son convertidas.
select set_config('wf04.legacy_task',gen_random_uuid()::text,true);
insert into public.tenant_tasks_v2(
  id,organization_id,tenant_id,property_id,room_id,task_type,
  origin,title,status,created_by
) values (
  current_setting('wf04.legacy_task')::uuid,current_setting('wf04.org')::uuid,
  current_setting('wf04.future_tenant')::uuid,
  current_setting('wf04.property')::uuid,
  current_setting('wf04.future_room')::uuid,'check_in',
  'manual','WF04 legacy check-in','scheduled',current_setting('wf04.root')::uuid
);
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf04.root'),'role','authenticated','aal','aal2'
)::text,true);
select public.apply_tenant_task_action_v2(
  current_setting('wf04.legacy_task')::uuid,'confirm',null
);
reset role;

do $legacy_unchanged$
begin
  if not exists(
    select 1 from public.tenant_tasks_v2
    where id=current_setting('wf04.legacy_task')::uuid
      and task_type='check_in' and source_kind is null and status='completed'
  ) then
    raise exception 'legacy check-in compatibility changed';
  end if;
end;
$legacy_unchanged$;

rollback;
