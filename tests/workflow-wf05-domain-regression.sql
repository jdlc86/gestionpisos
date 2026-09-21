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
        'accept',true,'photo',false,'checklist',true,'document',false
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
    null,null,'{}'::uuid[],false,'wf05-inspection-ready',null,null
  ) limit 1
),true);
reset role;

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

-- Simula la solicitud de información; las acciones WF-05 se añaden en el
-- siguiente bloque. La RPC de respuesta ya debe ser segura e idempotente.
update public.incidents_v2
set status='waiting_info',updated_at=now()
where id=current_setting('wf05.incident')::uuid;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf05.tenant_user'),'role','authenticated','aal','aal1'
)::text,true);
do $information$
declare v_first record; v_retry record;
begin
  select * into v_first
  from public.submit_incident_information_v1(
    current_setting('wf05.incident')::uuid,'wf05-info-1','El agua está cerrada.'
  );
  select * into v_retry
  from public.submit_incident_information_v1(
    current_setting('wf05.incident')::uuid,'wf05-info-1','El agua está cerrada.'
  );
  if not v_first.applied_new or v_retry.applied_new
    or v_first.update_id<>v_retry.update_id then
    raise exception 'WF05 information response is not idempotent';
  end if;
end;
$information$;
reset role;

do $core_counts$
begin
  if (
    select count(*) from public.incidents_v2
    where created_by=current_setting('wf05.tenant_user')::uuid
      and open_request_key='wf05-open-1'
  )<>1 then
    raise exception 'WF05 opening retry duplicated the dossier';
  end if;
  if (
    select count(*) from public.incident_updates_v2
    where incident_id=current_setting('wf05.incident')::uuid
      and update_kind='information_response'
      and request_key='wf05-info-1'
  )<>1 then
    raise exception 'WF05 information retry duplicated the update';
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
  ) then
    raise exception 'WF05 core audit trail is incomplete';
  end if;
end;
$core_counts$;

rollback;
