-- WF-05 · núcleo de expediente, RLS y apertura idempotente.
begin;

select set_config('wf05.org','11111111-1111-4111-8111-111111111111',true);
select set_config('wf05.root','22222222-2222-4222-8222-222222222222',true);
select set_config('wf05.owner_user',gen_random_uuid()::text,true);
select set_config('wf05.owner',gen_random_uuid()::text,true);
select set_config('wf05.property',gen_random_uuid()::text,true);
select set_config('wf05.other_property',gen_random_uuid()::text,true);
select set_config('wf05.room',gen_random_uuid()::text,true);
select set_config('wf05.other_room',gen_random_uuid()::text,true);
select set_config('wf05.staff',gen_random_uuid()::text,true);
select set_config('wf05.readonly_staff',gen_random_uuid()::text,true);
select set_config('wf05.outsider',gen_random_uuid()::text,true);
select set_config('wf05.tenant_user',gen_random_uuid()::text,true);
select set_config('wf05.other_tenant_user',gen_random_uuid()::text,true);
select set_config('wf05.tenant',gen_random_uuid()::text,true);
select set_config('wf05.other_tenant',gen_random_uuid()::text,true);
select set_config('wf05.occupancy',gen_random_uuid()::text,true);
select set_config('wf05.other_occupancy',gen_random_uuid()::text,true);

insert into auth.users(id) values
  (current_setting('wf05.owner_user')::uuid),
  (current_setting('wf05.staff')::uuid),
  (current_setting('wf05.readonly_staff')::uuid),
  (current_setting('wf05.outsider')::uuid),
  (current_setting('wf05.tenant_user')::uuid),
  (current_setting('wf05.other_tenant_user')::uuid);

insert into public.profiles(user_id,organization_id,display_name,status) values
  (current_setting('wf05.owner_user')::uuid,current_setting('wf05.org')::uuid,'WF05 owner','active'),
  (current_setting('wf05.staff')::uuid,current_setting('wf05.org')::uuid,'WF05 staff','active'),
  (current_setting('wf05.readonly_staff')::uuid,current_setting('wf05.org')::uuid,'WF05 readonly','active'),
  (current_setting('wf05.outsider')::uuid,current_setting('wf05.org')::uuid,'WF05 outsider','active');

insert into public.profiles(user_id,organization_id,display_name,status)
values (
  current_setting('wf05.root')::uuid,current_setting('wf05.org')::uuid,
  'WF05 ROOT','active'
)
on conflict(user_id) do update
set organization_id=excluded.organization_id,status='active',archived_at=null;

insert into public.user_roles(user_id,organization_id,role) values
  (current_setting('wf05.owner_user')::uuid,current_setting('wf05.org')::uuid,'owner'),
  (current_setting('wf05.staff')::uuid,current_setting('wf05.org')::uuid,'employee'),
  (current_setting('wf05.readonly_staff')::uuid,current_setting('wf05.org')::uuid,'employee'),
  (current_setting('wf05.outsider')::uuid,current_setting('wf05.org')::uuid,'employee'),
  (current_setting('wf05.tenant_user')::uuid,current_setting('wf05.org')::uuid,'tenant'),
  (current_setting('wf05.other_tenant_user')::uuid,current_setting('wf05.org')::uuid,'tenant');

insert into public.owners(id,organization_id,user_id,full_name,status)
values(
  current_setting('wf05.owner')::uuid,current_setting('wf05.org')::uuid,
  current_setting('wf05.owner_user')::uuid,'WF05 owner','active'
);
insert into public.properties_v2(
  id,organization_id,owner_id,name,address_line,status
) values
  (
    current_setting('wf05.property')::uuid,current_setting('wf05.org')::uuid,
    current_setting('wf05.owner')::uuid,'WF05 property','Regression','active'
  ),
  (
    current_setting('wf05.other_property')::uuid,current_setting('wf05.org')::uuid,
    current_setting('wf05.owner')::uuid,'WF05 other property','Regression','active'
  );
insert into public.rooms_v2(id,property_id,label,status) values
  (current_setting('wf05.room')::uuid,current_setting('wf05.property')::uuid,'WF05 room','active'),
  (current_setting('wf05.other_room')::uuid,current_setting('wf05.other_property')::uuid,'WF05 other room','active');

insert into public.property_staff_access_v3(
  organization_id,property_id,employee_user_id,assignment_type,can_write,granted_by
) values
  (
    current_setting('wf05.org')::uuid,current_setting('wf05.property')::uuid,
    current_setting('wf05.staff')::uuid,'responsible',true,current_setting('wf05.root')::uuid
  ),
  (
    current_setting('wf05.org')::uuid,current_setting('wf05.property')::uuid,
    current_setting('wf05.readonly_staff')::uuid,'access',false,current_setting('wf05.root')::uuid
  );

insert into public.tenants_v2(
  id,organization_id,user_id,full_name,document_type,document_number,email,status
) values
  (
    current_setting('wf05.tenant')::uuid,current_setting('wf05.org')::uuid,
    current_setting('wf05.tenant_user')::uuid,'WF05 tenant','other','WF05-TENANT',
    'wf05-tenant@example.invalid','active'
  ),
  (
    current_setting('wf05.other_tenant')::uuid,current_setting('wf05.org')::uuid,
    current_setting('wf05.other_tenant_user')::uuid,'WF05 other tenant','other','WF05-OTHER',
    'wf05-other@example.invalid','active'
  );

insert into public.occupancies_v2(
  id,organization_id,tenant_id,property_id,room_id,occupant_email,
  starts_on,ends_on,status,user_id
) values
  (
    current_setting('wf05.occupancy')::uuid,current_setting('wf05.org')::uuid,
    current_setting('wf05.tenant')::uuid,current_setting('wf05.property')::uuid,
    current_setting('wf05.room')::uuid,'wf05-tenant@example.invalid',
    current_date-1,null,'active',current_setting('wf05.tenant_user')::uuid
  ),
  (
    current_setting('wf05.other_occupancy')::uuid,current_setting('wf05.org')::uuid,
    current_setting('wf05.other_tenant')::uuid,current_setting('wf05.other_property')::uuid,
    current_setting('wf05.other_room')::uuid,'wf05-other@example.invalid',
    current_date-1,null,'active',current_setting('wf05.other_tenant_user')::uuid
  );

select set_config('wf05.photo_pattern',gen_random_uuid()::text,true);
insert into public.photo_patterns_v2(
  id,organization_id,property_id,name,target_type,target_key,
  reference_storage_path,contour_data,version,active,created_by
) values (
  current_setting('wf05.photo_pattern')::uuid,
  current_setting('wf05.org')::uuid,
  current_setting('wf05.property')::uuid,
  'WF05 inspección','zone','Reparación',
  current_setting('wf05.org')||'/patterns/wf05/reference.jpg',
  jsonb_build_object(
    'image',jsonb_build_object('width',1200,'height',900),
    'strokes',jsonb_build_array(jsonb_build_object(
      'kind','rect','raw_points',jsonb_build_array(
        jsonb_build_array(0.10,0.10),jsonb_build_array(0.80,0.80)
      )
    ))
  ),1,true,current_setting('wf05.root')::uuid
);

create function pg_temp.wf05_spec(p_flow text)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'authoringVersion',2,
    'flowName',case p_flow when 'maintenance' then 'WF05 gestión'
      else 'WF05 inspección posterior' end,
    'flowType',p_flow,'flowDescription','WF05 regression only',
    'scopeType','property','triggerType','event',
    'eventType',case p_flow when 'maintenance' then 'incident.created'
      else 'incident.resolved' end,
    'recurrence','','scheduledAt','','scheduledTimezone','','scheduledAtUtc','',
    'customEvery','','customUnit','',
    'assignmentType',case p_flow when 'maintenance' then 'role'
      else 'property_responsible' end,
    'assignmentUserId','',
    'assignmentRole',case p_flow when 'maintenance' then 'employee' else '' end,
    'steps',case p_flow
      when 'maintenance' then jsonb_build_object(
        'accept',true,'photo',false,'checklist',false,'document',false
      )
      else jsonb_build_object(
        'accept',true,'photo',true,'checklist',true,'document',true
      ) end,
    'checklistItems',case p_flow
      when 'inspection' then jsonb_build_array(
        jsonb_build_object('key','repair_ok','text','Reparación correcta','required',true)
      )
      else '[]'::jsonb end,
    'closeType',case p_flow when 'maintenance' then 'domain_adapter' else 'auto' end,
    'notifications',jsonb_build_object('onCreate',false,'onClose',true)
  );
$$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.root'),'role','authenticated','aal','aal2'
)::text,true);
select set_config('wf05.maintenance_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf05_spec('maintenance'),
    current_setting('wf05.property')::uuid,
    null,null,'{}'::uuid[],false,'wf05-maintenance-ready',null,null
  ) limit 1
),true);
select set_config('wf05.inspection_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf05_spec('inspection'),
    current_setting('wf05.property')::uuid,
    null,null,array[current_setting('wf05.photo_pattern')::uuid],
    false,'wf05-inspection-ready',null,null
  ) limit 1
),true);

do $single_management_application$
begin
  begin
    perform *
    from public.publish_workflow_ready_v1(
      pg_temp.wf05_spec('maintenance') || jsonb_build_object(
        'flowName','WF05 gestión duplicada'
      ),
      current_setting('wf05.property')::uuid,
      null,null,'{}'::uuid[],false,
      'wf05-maintenance-duplicate',null,null
    );
    raise exception 'WF05 allowed a second overlapping maintenance manager';
  exception when sqlstate '55000' then
    if sqlerrm<>'workflow_wf05_management_application_conflict' then
      raise;
    end if;
  end;
end;
$single_management_application$;
reset role;

do $single_management_application_count$
begin
  if (
    select count(*)
    from public.workflow_applications_v2 a
    join public.workflow_definition_versions_v2 wv
      on wv.id=a.definition_version_id
     and wv.definition_id=a.definition_id
     and wv.organization_id=a.organization_id
    where a.organization_id=current_setting('wf05.org')::uuid
      and a.status='configured'
      and a.property_id=current_setting('wf05.property')::uuid
      and wv.spec->>'triggerType'='event'
      and wv.spec->>'eventType'='incident.created'
      and wv.spec->>'flowType'='maintenance'
      and wv.spec->>'closeType'='domain_adapter'
  )<>1 then
    raise exception 'WF05 management application uniqueness is inconsistent';
  end if;
end;
$single_management_application_count$;

do $authoring_contract$
begin
  if public.workflow_authoring_complete_v1(
    pg_temp.wf05_spec('maintenance') || jsonb_build_object(
      'eventType','incident.resolved'
    )
  ) then
    raise exception 'WF05 accepted maintenance on incident.resolved';
  end if;
  if public.workflow_authoring_complete_v1(
    pg_temp.wf05_spec('inspection') || jsonb_build_object(
      'steps',jsonb_build_object(
        'accept',true,'photo',false,'checklist',false,'document',false
      ),
      'checklistItems','[]'::jsonb
    )
  ) then
    raise exception 'WF05 accepted inspection without reusable evidence';
  end if;
end;
$authoring_contract$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.tenant_user'),'role','authenticated','aal','aal1'
)::text,true);
select set_config('wf05.incident',(
  select incident_id::text
  from public.open_workflow_incident_v1(
    current_setting('wf05.property')::uuid,
    current_setting('wf05.room')::uuid,
    'maintenance','Fontanería','Fuga bajo el fregadero','high','wf05-open-1'
  )
),true);
reset role;

do $opened_once$
begin
  if (
    select count(*) from public.incidents_v2
    where id=current_setting('wf05.incident')::uuid
      and incident_kind='maintenance'
      and status='reported'
      and opened_occupancy_id=current_setting('wf05.occupancy')::uuid
  )<>1 then
    raise exception 'WF05 opening did not create the expected dossier';
  end if;
  if (
    select count(*) from public.workflow_event_outbox_v2
    where event_type='incident.created'
      and source_kind='incident'
      and source_id=current_setting('wf05.incident')::uuid
      and event_key='created'
  )<>1 then
    raise exception 'WF05 opening did not enqueue exactly one incident.created';
  end if;
  if exists(
    select 1 from public.workflow_executions_v2
    where incident_id=current_setting('wf05.incident')::uuid
  ) then
    raise exception 'WF05 opening synchronously created an execution';
  end if;
end;
$opened_once$;

select private.process_pending_workflow_events_v1(50);
select private.process_pending_workflow_events_v1(50);

select set_config('wf05.execution',(
  select id::text
  from public.workflow_executions_v2
  where application_id=current_setting('wf05.maintenance_app')::uuid
    and incident_id=current_setting('wf05.incident')::uuid
),true);
select set_config('wf05.task',(
  select id::text
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf05.execution')::uuid
),true);

do $dispatched_once$
declare
  v_actual jsonb;
begin
  if (
    select count(*) from public.workflow_executions_v2
    where application_id=current_setting('wf05.maintenance_app')::uuid
      and incident_id=current_setting('wf05.incident')::uuid
      and source_event_id is not null
      and assigned_user_id=current_setting('wf05.staff')::uuid
  )<>1 then
    select jsonb_build_object(
      'executions',coalesce((select jsonb_agg(jsonb_build_object(
        'id',x.id,'incident_id',x.incident_id,'source_event_id',x.source_event_id,
        'assigned_user_id',x.assigned_user_id,'status',x.status
      )) from public.workflow_executions_v2 x
        where x.application_id=current_setting('wf05.maintenance_app')::uuid),'[]'::jsonb),
      'dispatches',coalesce((select jsonb_agg(jsonb_build_object(
        'status',d.status,'error_code',d.error_code,'error_key',d.error_key
      )) from public.workflow_event_dispatches_v2 d
        join public.workflow_event_outbox_v2 ev on ev.id=d.event_id
        where d.application_id=current_setting('wf05.maintenance_app')::uuid
          and ev.source_id=current_setting('wf05.incident')::uuid),'[]'::jsonb)
    )
    into v_actual
    ;
    raise exception 'WF05 incident did not dispatch one linked writable execution: %',v_actual;
  end if;
  if (
    select count(*) from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('wf05.execution')::uuid
      and task_type='workflow'
      and assigned_user_id=current_setting('wf05.staff')::uuid
  )<>1 then
    raise exception 'WF05 incident did not materialize one transversal card';
  end if;
  if exists(
    select 1 from public.workflow_executions_v2
    where application_id=current_setting('wf05.inspection_app')::uuid
      and incident_id=current_setting('wf05.incident')::uuid
  ) then
    raise exception 'WF05 created-event incorrectly activated inspection';
  end if;
  if (
    select count(*) from public.workflow_event_dispatches_v2 d
    join public.workflow_event_outbox_v2 e on e.id=d.event_id
    where e.source_id=current_setting('wf05.incident')::uuid
      and e.event_type='incident.created'
      and d.application_id=current_setting('wf05.maintenance_app')::uuid
      and d.status='executed'
  )<>1 then
    raise exception 'WF05 dispatcher receipt is not unique';
  end if;
end;
$dispatched_once$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.staff'),'role','authenticated','aal','aal1'
)::text,true);
do $actor_current$
begin
  if not public.workflow_execution_actor_current_v1(
    current_setting('wf05.execution')::uuid
  ) then
    raise exception 'WF05 writable assignee was not current';
  end if;
end;
$actor_current$;
reset role;

-- Cambiar el rol del asignado no debe conservar su capacidad de actuar solo
-- porque todavía tenga write access al piso.
update public.user_roles
set role='admin'
where user_id=current_setting('wf05.staff')::uuid
  and organization_id=current_setting('wf05.org')::uuid
  and revoked_at is null;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.staff'),'role','authenticated','aal','aal2'
)::text,true);
do $assignment_rule_revalidated$
begin
  if public.workflow_execution_actor_current_v1(
    current_setting('wf05.execution')::uuid
  ) then
    raise exception 'WF05 former role assignee remained current through write access';
  end if;
  begin
    perform public.apply_workflow_task_action_v1(
      current_setting('wf05.task')::uuid,'accept','wf05-role-changed',null
    );
    raise exception 'WF05 former role assignee was allowed to act';
  exception when sqlstate '42501' then
    null;
  end;
end;
$assignment_rule_revalidated$;
reset role;

update public.user_roles
set role='employee'
where user_id=current_setting('wf05.staff')::uuid
  and organization_id=current_setting('wf05.org')::uuid
  and revoked_at is null;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.staff'),'role','authenticated','aal','aal1'
)::text,true);
do $assignment_rule_recovers$
begin
  if not public.workflow_execution_actor_current_v1(
    current_setting('wf05.execution')::uuid
  ) then
    raise exception 'WF05 original role assignment did not recover';
  end if;
end;
$assignment_rule_recovers$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.tenant_user'),'role','authenticated','aal','aal1'
)::text,true);
do $retry$
declare v_result record;
begin
  select * into v_result
  from public.open_workflow_incident_v1(
    current_setting('wf05.property')::uuid,
    current_setting('wf05.room')::uuid,
    'maintenance','Fontanería','Fuga bajo el fregadero','high','wf05-open-1'
  );
  if v_result.incident_id<>current_setting('wf05.incident')::uuid
    or v_result.created_new then
    raise exception 'WF05 opening retry did not recover the same dossier';
  end if;
end;
$retry$;

do $conflict$
begin
  begin
    perform public.open_workflow_incident_v1(
      current_setting('wf05.property')::uuid,
      current_setting('wf05.room')::uuid,
      'maintenance','Fontanería','Payload distinto','high','wf05-open-1'
    );
    raise exception 'WF05 conflicting opening retry was accepted';
  exception when sqlstate '55000' then
    if sqlerrm<>'incident_request_key_conflict' then raise; end if;
  end;
end;
$conflict$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.other_tenant_user'),'role','authenticated','aal','aal1'
)::text,true);
do $tenant_scope$
begin
  if exists(
    select 1 from public.incidents_v2
    where id=current_setting('wf05.incident')::uuid
  ) then
    raise exception 'out-of-scope tenant read WF05 incident';
  end if;
  begin
    perform public.open_workflow_incident_v1(
      current_setting('wf05.property')::uuid,
      current_setting('wf05.room')::uuid,
      'incident','Otro','Fuera de alcance','normal','wf05-out-of-scope'
    );
    raise exception 'out-of-scope tenant opened WF05 incident';
  exception when sqlstate '42501' then
    if sqlerrm<>'incident_open_forbidden' then raise; end if;
  end;
end;
$tenant_scope$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.readonly_staff'),'role','authenticated','aal','aal1'
)::text,true);
do $readonly_staff$
begin
  if (
    select count(*) from public.incidents_v2
    where id=current_setting('wf05.incident')::uuid
  )<>1 then
    raise exception 'read-only scoped employee could not read WF05 incident';
  end if;
  begin
    perform public.open_workflow_incident_v1(
      current_setting('wf05.property')::uuid,
      current_setting('wf05.room')::uuid,
      'incident','Otro','Sin escritura','normal','wf05-readonly'
    );
    raise exception 'read-only employee opened WF05 incident';
  exception when sqlstate '42501' then
    if sqlerrm<>'incident_open_forbidden' then raise; end if;
  end;
end;
$readonly_staff$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.outsider'),'role','authenticated','aal','aal1'
)::text,true);
do $outsider_rls$
begin
  if exists(
    select 1 from public.incidents_v2
    where id=current_setting('wf05.incident')::uuid
  ) then
    raise exception 'out-of-scope employee read WF05 incident';
  end if;
  begin
    insert into public.incidents_v2(
      organization_id,property_id,created_by,category,description
    ) values (
      current_setting('wf05.org')::uuid,current_setting('wf05.property')::uuid,
      current_setting('wf05.outsider')::uuid,'Bypass','Direct insert'
    );
    raise exception 'authenticated direct incident insert was accepted';
  exception when insufficient_privilege then null;
  end;
end;
$outsider_rls$;
reset role;

-- La autorización se revalida en cada acción, no solo al asignar.
update public.property_staff_access_v3
set revoked_at=clock_timestamp()
where property_id=current_setting('wf05.property')::uuid
  and employee_user_id=current_setting('wf05.staff')::uuid;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.staff'),'role','authenticated','aal','aal1'
)::text,true);
do $revoked_assignee$
begin
  begin
    perform public.apply_workflow_task_action_v1(
      current_setting('wf05.task')::uuid,'accept','wf05-revoked',null
    );
    raise exception 'revoked WF05 assignee accepted management';
  exception when sqlstate '42501' then
    if sqlerrm<>'workflow_assignee_access_revoked' then raise; end if;
  end;
end;
$revoked_assignee$;
reset role;

update public.property_staff_access_v3
set revoked_at=null
where property_id=current_setting('wf05.property')::uuid
  and employee_user_id=current_setting('wf05.staff')::uuid;

-- El expediente deja de ser accionable si su destino ya no coincide con el
-- evento y la ejecución que lo originaron.
update public.incidents_v2
set property_id=current_setting('wf05.other_property')::uuid
where id=current_setting('wf05.incident')::uuid;
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.staff'),'role','authenticated','aal','aal1'
)::text,true);
do $destination_revalidated$
begin
  begin
    perform public.apply_workflow_task_action_v1(
      current_setting('wf05.task')::uuid,'accept','wf05-wrong-destination',null
    );
    raise exception 'WF05 accepted an incident outside the bound destination';
  exception when sqlstate '42501' then
    if sqlerrm<>'workflow_assignee_access_revoked' then raise; end if;
  end;
end;
$destination_revalidated$;
reset role;
update public.incidents_v2
set property_id=current_setting('wf05.property')::uuid
where id=current_setting('wf05.incident')::uuid;

-- ADMIN conserva el requisito de MFA cuando también cumple la regla de
-- asignación congelada. Se usa el mismo actor para no saltarse la revalidación.
update public.user_roles
set role='admin'
where user_id=current_setting('wf05.staff')::uuid
  and organization_id=current_setting('wf05.org')::uuid
  and revoked_at is null;
update public.workflow_executions_v2
set spec_snapshot=jsonb_set(
  spec_snapshot,'{assignmentRole}',to_jsonb('admin'::text),true
)
where id=current_setting('wf05.execution')::uuid;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.staff'),'role','authenticated','aal','aal1'
)::text,true);
do $privileged_mfa$
begin
  begin
    perform public.apply_workflow_task_action_v1(
      current_setting('wf05.task')::uuid,'accept','wf05-admin-aal1',null
    );
    raise exception 'WF05 privileged action without MFA was accepted';
  exception when sqlstate '42501' then
    if sqlerrm<>'workflow_wf05_mfa_required' then raise; end if;
  end;
end;
$privileged_mfa$;
reset role;

update public.user_roles
set role='employee'
where user_id=current_setting('wf05.staff')::uuid
  and organization_id=current_setting('wf05.org')::uuid
  and revoked_at is null;
update public.workflow_executions_v2
set spec_snapshot=jsonb_set(
  spec_snapshot,'{assignmentRole}',to_jsonb('employee'::text),true
)
where id=current_setting('wf05.execution')::uuid;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.staff'),'role','authenticated','aal','aal1'
)::text,true);
do $accept_management$
declare v_first record; v_retry record;
begin
  select * into v_first from public.apply_workflow_task_action_v1(
    current_setting('wf05.task')::uuid,'accept','wf05-accept',null
  );
  select * into v_retry from public.apply_workflow_task_action_v1(
    current_setting('wf05.task')::uuid,'accept','wf05-accept',null
  );
  if not v_first.applied_new or v_retry.applied_new
    or v_first.execution_id<>current_setting('wf05.execution')::uuid then
    raise exception 'WF05 accept retry is not idempotent';
  end if;
  if not exists(
    select 1 from public.incidents_v2 i
    where i.id=current_setting('wf05.incident')::uuid
      and i.status='in_progress'
      and i.assigned_to=current_setting('wf05.staff')::uuid
  ) or not exists(
    select 1 from public.tenant_tasks_v2 t
    join public.workflow_executions_v2 e on e.id=t.source_id
    where t.id=current_setting('wf05.task')::uuid
      and t.status='active' and e.status='active'
  ) then
    raise exception 'WF05 accept did not synchronize dossier/task/execution';
  end if;
end;
$accept_management$;

do $request_information$
declare v_result record;
begin
  select * into v_result from public.apply_workflow_task_action_v1(
    current_setting('wf05.task')::uuid,'request_info','wf05-request-info',
    'Confirma si la llave de paso está cerrada.'
  );
  if not v_result.applied_new
    or v_result.task_status<>'waiting_info'
    or v_result.execution_status<>'waiting_info'
    or (select status from public.incidents_v2
        where id=current_setting('wf05.incident')::uuid)<>'waiting_info' then
    raise exception 'WF05 information request is not a synchronized non-terminal state';
  end if;
  begin
    perform public.apply_workflow_task_action_v1(
      current_setting('wf05.task')::uuid,'continue','wf05-continue-too-soon',null
    );
    raise exception 'WF05 continued without an information response';
  exception when sqlstate '55000' then
    if sqlerrm<>'workflow_wf05_information_response_required' then raise; end if;
  end;
end;
$request_information$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.tenant_user'),'role','authenticated','aal','aal1'
)::text,true);
do $information$
declare v_first record; v_retry record;
begin
  select * into v_first from public.submit_incident_information_v1(
    current_setting('wf05.incident')::uuid,'wf05-info-1','El agua está cerrada.'
  );
  select * into v_retry from public.submit_incident_information_v1(
    current_setting('wf05.incident')::uuid,'wf05-info-1','El agua está cerrada.'
  );
  if not v_first.applied_new or v_retry.applied_new
    or v_first.update_id<>v_retry.update_id then
    raise exception 'WF05 information response is not idempotent';
  end if;
end;
$information$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.staff'),'role','authenticated','aal','aal1'
)::text,true);
do $continue_same_execution$
declare v_result record;
begin
  select * into v_result from public.apply_workflow_task_action_v1(
    current_setting('wf05.task')::uuid,'continue','wf05-continue',null
  );
  if not v_result.applied_new
    or v_result.execution_id<>current_setting('wf05.execution')::uuid
    or v_result.task_status<>'active'
    or (select status from public.incidents_v2
        where id=current_setting('wf05.incident')::uuid)<>'in_progress'
    or (select count(*) from public.workflow_executions_v2
        where incident_id=current_setting('wf05.incident')::uuid
          and spec_snapshot->>'flowType'='maintenance')<>1 then
    raise exception 'WF05 continue did not recover the same execution';
  end if;
end;
$continue_same_execution$;

do $resolve_management$
declare v_result record;
begin
  select * into v_result from public.apply_workflow_task_action_v1(
    current_setting('wf05.task')::uuid,'resolve','wf05-resolve',
    'Fuga reparada y zona seca.'
  );
  if not v_result.applied_new
    or v_result.task_status<>'completed'
    or v_result.execution_status<>'completed'
    or not exists(
      select 1 from public.incidents_v2
      where id=current_setting('wf05.incident')::uuid
        and status='resolved' and resolved_at is not null
    ) then
    raise exception 'WF05 resolve did not close all authorities coherently';
  end if;
end;
$resolve_management$;
reset role;

do $resolved_event_once$
begin
  if (
    select count(*) from public.workflow_event_outbox_v2
    where source_id=current_setting('wf05.incident')::uuid
      and event_type='incident.resolved' and event_key='resolved'
  )<>1 then
    raise exception 'WF05 resolve did not enqueue exactly one downstream event';
  end if;
end;
$resolved_event_once$;

select private.process_pending_workflow_events_v1(50);
select private.process_pending_workflow_events_v1(50);

select set_config('wf05.inspection_execution',(
  select id::text from public.workflow_executions_v2
  where application_id=current_setting('wf05.inspection_app')::uuid
    and incident_id=current_setting('wf05.incident')::uuid
),true);

do $downstream_inspection$
declare v_execution public.workflow_executions_v2;
begin
  select * into v_execution from public.workflow_executions_v2
  where id=current_setting('wf05.inspection_execution')::uuid;
  if v_execution.id is null
    or v_execution.source_event_id is null
    or v_execution.spec_snapshot#>>'{steps,photo}'<>'true'
    or v_execution.spec_snapshot#>>'{steps,checklist}'<>'true'
    or v_execution.spec_snapshot#>>'{steps,document}'<>'true'
    or jsonb_array_length(v_execution.checklist_state)<>1
    or (select count(*) from public.workflow_execution_photo_resources_v2 r
        where r.execution_id=v_execution.id)<>1
    or (select count(*) from public.tenant_tasks_v2 t
        where t.source_kind='workflow_execution'
          and t.source_id=v_execution.id)<>1
    or (select count(*) from public.workflow_executions_v2 e
        where e.application_id=current_setting('wf05.inspection_app')::uuid
          and e.incident_id=current_setting('wf05.incident')::uuid)<>1 then
    raise exception 'WF05 downstream inspection did not reuse generic evidence/contracts exactly once';
  end if;
  if not exists(
    select 1 from public.workflow_event_dispatches_v2 d
    join public.workflow_event_outbox_v2 ev on ev.id=d.event_id
    where ev.source_id=current_setting('wf05.incident')::uuid
      and ev.event_type='incident.resolved'
      and d.application_id=current_setting('wf05.inspection_app')::uuid
      and d.execution_id=v_execution.id
      and d.status='executed'
  ) then
    raise exception 'WF05 downstream inspection has no common dispatcher receipt';
  end if;
end;
$downstream_inspection$;

-- Una incidencia abierta por personal interno también puede pedir información
-- a su creador y continuar sobre la misma ejecución.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.root'),'role','authenticated','aal','aal2'
)::text,true);
select set_config('wf05.internal_incident',(
  select incident_id::text
  from public.open_workflow_incident_v1(
    current_setting('wf05.property')::uuid,
    null,
    'incident',
    'Revisión interna',
    'Confirmar detalle aportado por la gestoría.',
    'normal',
    'wf05-internal-open'
  )
),true);
reset role;

select private.process_pending_workflow_events_v1(50);
select set_config('wf05.internal_execution',(
  select id::text
  from public.workflow_executions_v2
  where application_id=current_setting('wf05.maintenance_app')::uuid
    and incident_id=current_setting('wf05.internal_incident')::uuid
),true);
select set_config('wf05.internal_task',(
  select id::text
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf05.internal_execution')::uuid
),true);

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.staff'),'role','authenticated','aal','aal1'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf05.internal_task')::uuid,
  'accept',
  'wf05-internal-accept',
  null
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf05.internal_task')::uuid,
  'request_info',
  'wf05-internal-request-info',
  'Confirma el detalle interno antes de continuar.'
);
reset role;

do $internal_request_visible_only_internal$
begin
  if not exists(
    select 1
    from public.incident_updates_v2
    where incident_id=current_setting('wf05.internal_incident')::uuid
      and update_kind='request_info'
      and request_key='wf05-internal-request-info'
      and visibility='internal'
  ) then
    raise exception 'WF05 internal information request was not stored as internal';
  end if;
end;
$internal_request_visible_only_internal$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.root'),'role','authenticated','aal','aal2'
)::text,true);
select * from public.submit_incident_information_v1(
  current_setting('wf05.internal_incident')::uuid,
  'wf05-internal-info',
  'Detalle interno confirmado.'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.staff'),'role','authenticated','aal','aal1'
)::text,true);
do $internal_continue_same_execution$
declare v_result record;
begin
  select * into v_result
  from public.apply_workflow_task_action_v1(
    current_setting('wf05.internal_task')::uuid,
    'continue',
    'wf05-internal-continue',
    null
  );
  if not v_result.applied_new
    or v_result.execution_id<>current_setting('wf05.internal_execution')::uuid
    or v_result.task_status<>'active'
    or (select status from public.incidents_v2
        where id=current_setting('wf05.internal_incident')::uuid)<>'in_progress'
    or (select count(*) from public.workflow_executions_v2
        where incident_id=current_setting('wf05.internal_incident')::uuid
          and spec_snapshot->>'flowType'='maintenance')<>1 then
    raise exception 'WF05 internal reporter did not continue on the same execution';
  end if;
end;
$internal_continue_same_execution$;
reset role;

do $final_counts$
begin
  if (select count(*) from public.incidents_v2
      where created_by=current_setting('wf05.tenant_user')::uuid
        and open_request_key='wf05-open-1')<>1
    or (select count(*) from public.incident_updates_v2
        where incident_id=current_setting('wf05.incident')::uuid
          and update_kind='request_info'
          and request_key='wf05-request-info')<>1
    or (select count(*) from public.incident_updates_v2
        where incident_id=current_setting('wf05.incident')::uuid
          and update_kind='information_response'
          and request_key='wf05-info-1')<>1
    or (select count(*) from public.workflow_execution_events_v2
        where execution_id=current_setting('wf05.execution')::uuid
          and event_type='wf05_domain_action')<>4 then
    raise exception 'WF05 idempotency counts are inconsistent';
  end if;
  if not exists(
    select 1 from public.audit_log_v2
    where entity_type='incident'
      and entity_id=current_setting('wf05.incident')
      and action='incident_opened'
  ) or not exists(
    select 1 from public.audit_log_v2
    where entity_type='incident'
      and entity_id=current_setting('wf05.incident')
      and action='incident_information_submitted'
  ) or (select count(*) from public.audit_log_v2
        where entity_type='workflow_execution'
          and entity_id=current_setting('wf05.execution')
          and action='workflow_wf05_action_applied')<>4 then
    raise exception 'WF05 audit trail is incomplete';
  end if;
  if not exists(
    select 1 from public.notifications_v2
    where source_kind='incident'
      and source_id=current_setting('wf05.incident')::uuid
      and event_key='information_requested:wf05-request-info'
      and recipient_user_id=current_setting('wf05.tenant_user')::uuid
  ) or not exists(
    select 1 from public.notifications_v2
    where source_kind='incident'
      and source_id=current_setting('wf05.incident')::uuid
      and event_key='resolved'
      and recipient_user_id=current_setting('wf05.tenant_user')::uuid
  ) then
    raise exception 'WF05 notifications are incomplete';
  end if;
end;
$final_counts$;

rollback;
