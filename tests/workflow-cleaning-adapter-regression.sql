-- WF-03 · Primer adaptador Limpieza. Base PostgreSQL desechable; rollback total.
begin;

select set_config('wf03.org',(
  select organization_id::text
  from public.user_roles
  where role='root' and revoked_at is null
  limit 1
),true);
select set_config('wf03.root',(
  select user_id::text
  from public.user_roles
  where role='root' and revoked_at is null
  limit 1
),true);
select set_config('wf03.owner',gen_random_uuid()::text,true);
select set_config('wf03.property',gen_random_uuid()::text,true);
select set_config('wf03.room',gen_random_uuid()::text,true);
select set_config('wf03.tenant_user',gen_random_uuid()::text,true);
select set_config('wf03.tenant',gen_random_uuid()::text,true);
select set_config('wf03.occupancy',gen_random_uuid()::text,true);

insert into auth.users(id)
values(current_setting('wf03.tenant_user')::uuid);

insert into public.user_roles(user_id,organization_id,role)
values(
  current_setting('wf03.tenant_user')::uuid,
  current_setting('wf03.org')::uuid,
  'tenant'
);

insert into public.owners(id,organization_id,full_name,status)
values(
  current_setting('wf03.owner')::uuid,
  current_setting('wf03.org')::uuid,
  'WF03 owner',
  'active'
);

insert into public.properties_v2(
  id,organization_id,owner_id,name,address_line,status
) values (
  current_setting('wf03.property')::uuid,
  current_setting('wf03.org')::uuid,
  current_setting('wf03.owner')::uuid,
  'WF03 property',
  'Regression only',
  'active'
);

insert into public.rooms_v2(id,property_id,label,status)
values(
  current_setting('wf03.room')::uuid,
  current_setting('wf03.property')::uuid,
  'WF03 room',
  'active'
);

insert into public.tenants_v2(
  id,organization_id,user_id,full_name,document_type,document_number,email,status
) values (
  current_setting('wf03.tenant')::uuid,
  current_setting('wf03.org')::uuid,
  current_setting('wf03.tenant_user')::uuid,
  'WF03 tenant',
  'other',
  'WF03-TENANT',
  'wf03-tenant@example.invalid',
  'active'
);

insert into public.occupancies_v2(
  id,organization_id,property_id,room_id,occupant_email,
  starts_on,ends_on,status,user_id,tenant_id
) values (
  current_setting('wf03.occupancy')::uuid,
  current_setting('wf03.org')::uuid,
  current_setting('wf03.property')::uuid,
  current_setting('wf03.room')::uuid,
  'wf03-tenant@example.invalid',
  current_date-2,
  null,
  'active',
  current_setting('wf03.tenant_user')::uuid,
  current_setting('wf03.tenant')::uuid
);

create function pg_temp.wf03_spec(
  p_flow_type text,
  p_name text
)
returns jsonb
language sql
stable
as $spec$
  select jsonb_build_object(
    'authoringVersion',2,
    'flowName',p_name,
    'flowType',p_flow_type,
    'flowDescription','WF03 regression only',
    'scopeType','property',
    'triggerType','manual',
    'eventType','',
    'recurrence','',
    'scheduledAt','',
    'scheduledTimezone','',
    'scheduledAtUtc','',
    'customEvery','',
    'customUnit','',
    'assignmentType','fixed_person',
    'assignmentUserId',current_setting('wf03.tenant_user'),
    'assignmentRole','',
    'steps',jsonb_build_object(
      'accept',true,'photo',false,'checklist',false,'document',false
    ),
    'checklistItems','[]'::jsonb,
    'closeType',case when p_flow_type='cleaning' then 'domain_adapter' else 'auto' end,
    'notifications',jsonb_build_object('onCreate',false,'onClose',false)
  );
$spec$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf03.root'),
  'role','authenticated',
  'aal','aal2'
)::text,true);

do $create_cleaning_execution$
declare
  v_ready record;
begin
  select * into v_ready
  from public.publish_workflow_ready_v1(
    pg_temp.wf03_spec('cleaning','WF03 cleaning'),
    current_setting('wf03.property')::uuid,
    null,
    null,
    '{}'::uuid[],
    true,
    'wf03-cleaning-ready',
    'wf03-cleaning-execution',
    null
  )
  limit 1;

  if v_ready.execution_id is null then
    raise exception 'cleaning workflow did not create execution';
  end if;

  perform set_config('wf03.cleaning_definition',v_ready.definition_id::text,true);
  perform set_config('wf03.cleaning_app',v_ready.application_id::text,true);
  perform set_config('wf03.cleaning_execution',v_ready.execution_id::text,true);
end;
$create_cleaning_execution$;

reset role;

do $linked_once$
declare
  v_domain public.cleaning_tasks_v2;
  v_task public.tenant_tasks_v2;
begin
  select * into v_domain
  from public.cleaning_tasks_v2
  where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid;

  if v_domain.id is null then
    raise exception 'cleaning domain task was not linked';
  end if;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf03.cleaning_execution')::uuid;

  if v_task.id is null then
    raise exception 'generic workflow task was not materialized';
  end if;

  if v_domain.assigned_user_id is distinct from current_setting('wf03.tenant_user')::uuid
    or v_domain.property_id is distinct from current_setting('wf03.property')::uuid
    or v_domain.tenant_id is distinct from current_setting('wf03.tenant')::uuid
    or v_domain.plan_id is not null
    or v_domain.status<>'pending' then
    raise exception 'cleaning domain task did not freeze expected execution context';
  end if;

  if v_task.assigned_user_id is distinct from v_domain.assigned_user_id
    or v_task.property_id is distinct from v_domain.property_id then
    raise exception 'generic task and cleaning domain task diverged at materialization';
  end if;

  if (select count(*) from public.tenant_tasks_v2
      where source_kind='workflow_execution'
        and source_id=current_setting('wf03.cleaning_execution')::uuid)<>1
    or (select count(*) from public.cleaning_tasks_v2
        where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid)<>1 then
    raise exception 'cleaning execution materialized duplicate rows';
  end if;
end;
$linked_once$;

-- Re-materialization must be a pure retry: same generic card, same domain envelope.
select public.workflow_materialize_execution_task_internal_v1(
  current_setting('wf03.cleaning_execution')::uuid,
  current_setting('wf03.root')::uuid
);

do $materializer_retry$
begin
  if (select count(*) from public.tenant_tasks_v2
      where source_kind='workflow_execution'
        and source_id=current_setting('wf03.cleaning_execution')::uuid)<>1
    or (select count(*) from public.cleaning_tasks_v2
        where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid)<>1 then
    raise exception 'materializer retry duplicated cleaning state';
  end if;

  if (select count(*) from public.workflow_execution_events_v2
      where execution_id=current_setting('wf03.cleaning_execution')::uuid
        and event_type='domain_adapter_linked')<>1 then
    raise exception 'domain adapter linkage audit was duplicated';
  end if;
end;
$materializer_retry$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf03.root'),
  'role','authenticated',
  'aal','aal2'
)::text,true);

do $non_cleaning_execution$
declare
  v_ready record;
begin
  select * into v_ready
  from public.publish_workflow_ready_v1(
    pg_temp.wf03_spec('custom','WF03 non cleaning'),
    current_setting('wf03.property')::uuid,
    null,
    null,
    '{}'::uuid[],
    true,
    'wf03-custom-ready',
    'wf03-custom-execution',
    null
  )
  limit 1;

  if v_ready.execution_id is null then
    raise exception 'control workflow did not create execution';
  end if;

  perform set_config('wf03.custom_execution',v_ready.execution_id::text,true);
end;
$non_cleaning_execution$;

reset role;

do $non_cleaning_no_domain_row$
begin
  if exists(
    select 1
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.custom_execution')::uuid
  ) then
    raise exception 'non-cleaning workflow created cleaning domain state';
  end if;
end;
$non_cleaning_no_domain_row$;

do $private_adapter_privilege$
begin
  if has_function_privilege(
    'authenticated',
    'private.workflow_ensure_cleaning_domain_task_v1(uuid,uuid)',
    'EXECUTE'
  ) then
    raise exception 'authenticated client gained direct cleaning adapter execution';
  end if;
end;
$private_adapter_privilege$;

rollback;
