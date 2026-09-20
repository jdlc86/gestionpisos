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

select set_config('wf03.cleaning_task',(
  select id::text
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf03.cleaning_execution')::uuid
),true);

do $cleaning_actions_seeded$
begin
  if not exists(
    select 1
    from public.tenant_task_actions_v2
    where task_id=current_setting('wf03.cleaning_task')::uuid
      and action_key='accept'
      and from_status='pending'
      and to_status='active'
      and actor='assignee'
      and active=true
  ) then
    raise exception 'cleaning workflow did not seed accept -> active';
  end if;

  if not exists(
    select 1
    from public.tenant_task_actions_v2
    where task_id=current_setting('wf03.cleaning_task')::uuid
      and action_key='reject'
      and from_status='pending'
      and to_status='rejected'
      and actor='assignee'
      and active=true
  ) then
    raise exception 'cleaning workflow did not seed reject action';
  end if;
end;
$cleaning_actions_seeded$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf03.tenant_user'),
  'role','authenticated',
  'aal','aal1'
)::text,true);

do $accept_cleaning$
declare
  v_result record;
begin
  select * into v_result
  from public.apply_workflow_task_action_v1(
    current_setting('wf03.cleaning_task')::uuid,
    'accept',
    'wf03-cleaning-accept',
    null
  )
  limit 1;

  if v_result.task_status<>'active'
    or v_result.execution_status<>'active'
    or v_result.applied_new is distinct from true then
    raise exception 'cleaning accept did not activate workflow atomically';
  end if;
end;
$accept_cleaning$;

reset role;

do $accepted_domain_state$
begin
  if not exists(
    select 1
    from public.workflow_executions_v2
    where id=current_setting('wf03.cleaning_execution')::uuid
      and status='active'
  ) or not exists(
    select 1
    from public.tenant_tasks_v2
    where id=current_setting('wf03.cleaning_task')::uuid
      and status='active'
  ) or not exists(
    select 1
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
      and status='accepted'
  ) then
    raise exception 'accepted cleaning state diverged between workflow and domain';
  end if;

  if (select count(*)
      from public.workflow_execution_events_v2
      where execution_id=current_setting('wf03.cleaning_execution')::uuid
        and event_type='domain_adapter_state_changed'
        and details->>'action_key'='accept')<>1 then
    raise exception 'cleaning accept domain event missing or duplicated';
  end if;
end;
$accepted_domain_state$;

-- Same request key must be a pure retry and must not duplicate domain history.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf03.tenant_user'),
  'role','authenticated',
  'aal','aal1'
)::text,true);

do $accept_retry$
declare
  v_result record;
begin
  select * into v_result
  from public.apply_workflow_task_action_v1(
    current_setting('wf03.cleaning_task')::uuid,
    'accept',
    'wf03-cleaning-accept',
    null
  )
  limit 1;

  if v_result.applied_new is distinct from false
    or v_result.task_status<>'active'
    or v_result.execution_status<>'active' then
    raise exception 'cleaning accept retry was not idempotent';
  end if;
end;
$accept_retry$;

reset role;

do $accept_retry_no_duplicate$
begin
  if (select count(*)
      from public.workflow_execution_events_v2
      where execution_id=current_setting('wf03.cleaning_execution')::uuid
        and event_type='domain_adapter_state_changed'
        and details->>'action_key'='accept')<>1 then
    raise exception 'cleaning accept retry duplicated domain history';
  end if;
end;
$accept_retry_no_duplicate$;

-- Dos patrones activos fuerzan un checklist congelado de dos fotos.
select set_config('wf03.pattern_a',gen_random_uuid()::text,true);
select set_config('wf03.pattern_b',gen_random_uuid()::text,true);

insert into public.photo_patterns_v2(
  id,organization_id,property_id,name,target_type,reference_storage_path,contour_data
) values
(
  current_setting('wf03.pattern_a')::uuid,
  current_setting('wf03.org')::uuid,
  current_setting('wf03.property')::uuid,
  'WF03 cleaning pattern A',
  'zone',
  'wf03/pattern-a.webp',
  '{"shapes":[]}'::jsonb
),
(
  current_setting('wf03.pattern_b')::uuid,
  current_setting('wf03.org')::uuid,
  current_setting('wf03.property')::uuid,
  'WF03 cleaning pattern B',
  'zone',
  'wf03/pattern-b.webp',
  '{"shapes":[]}'::jsonb
);

select *
from private.ensure_cleaning_photo_requests_v2(
  (
    select id
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
  )
);

select set_config('wf03.request_1',(
  select id::text
  from public.cleaning_photo_requests_v2
  where cleaning_task_id=(
    select id
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
  )
  order by ordinal
  limit 1
),true);
select set_config('wf03.request_2',(
  select id::text
  from public.cleaning_photo_requests_v2
  where cleaning_task_id=(
    select id
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
  )
  order by ordinal
  offset 1
  limit 1
),true);
select set_config('wf03.request_pattern_1',(
  select pattern_id::text
  from public.cleaning_photo_requests_v2
  where id=current_setting('wf03.request_1')::uuid
),true);
select set_config('wf03.request_pattern_2',(
  select pattern_id::text
  from public.cleaning_photo_requests_v2
  where id=current_setting('wf03.request_2')::uuid
),true);

do $two_photo_requests_frozen$
begin
  if (select count(*)
      from public.cleaning_photo_requests_v2
      where cleaning_task_id=(
        select id
        from public.cleaning_tasks_v2
        where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
      )
        and request_kind='cleaning')<>2 then
    raise exception 'cleaning checklist did not freeze exactly two photo requests';
  end if;
end;
$two_photo_requests_frozen$;

-- Primera foto: completa solo su request, pasa el expediente a in_progress
-- y NO puede crear todavía auditoría.
select set_config('wf03.run_1',gen_random_uuid()::text,true);
select set_config('wf03.item_1',gen_random_uuid()::text,true);

insert into public.photo_verification_runs_v2(
  id,organization_id,property_id,actor_user_id,source_type,source_id,
  verification_mode,purpose,cleaning_task_id,status
) values (
  current_setting('wf03.run_1')::uuid,
  current_setting('wf03.org')::uuid,
  current_setting('wf03.property')::uuid,
  current_setting('wf03.tenant_user')::uuid,
  'cleaning_task',
  (
    select id
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
  ),
  'manual',
  'cleaning',
  (
    select id
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
  ),
  'capturing'
);

insert into public.photo_verification_items_v2(
  id,run_id,pattern_id,storage_path
) values (
  current_setting('wf03.item_1')::uuid,
  current_setting('wf03.run_1')::uuid,
  current_setting('wf03.request_pattern_1')::uuid,
  current_setting('wf03.org')||'/'||
    current_setting('wf03.run_1')||'/'||
    current_setting('wf03.item_1')||'.jpg'
);

update public.photo_verification_runs_v2
set status='submitted',
    submitted_at=now()
where id=current_setting('wf03.run_1')::uuid;

do $first_photo_progress$
declare
  v_audit public.cleaning_audits_v2;
begin
  if not exists(
    select 1
    from public.cleaning_photo_requests_v2
    where id=current_setting('wf03.request_1')::uuid
      and completed_run_id=current_setting('wf03.run_1')::uuid
      and completed_at is not null
  ) then
    raise exception 'first cleaning photo request was not completed by submitted run';
  end if;

  if exists(
    select 1
    from public.cleaning_photo_requests_v2
    where id=current_setting('wf03.request_2')::uuid
      and completed_run_id is not null
  ) then
    raise exception 'first photo incorrectly completed another request';
  end if;

  if not exists(
    select 1
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
      and status='in_progress'
      and submitted_at is null
  ) then
    raise exception 'first cleaning photo did not move domain task to in_progress';
  end if;

  select * into v_audit
  from private.select_cleaning_audit_v2(
    (
      select id
      from public.cleaning_tasks_v2
      where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
    ),
    current_setting('wf03.run_1')::uuid,
    0.0,
    now()
  );

  if v_audit.id is not null
    or exists(
      select 1
      from public.cleaning_audits_v2
      where cleaning_task_id=(
        select id
        from public.cleaning_tasks_v2
        where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
      )
    ) then
    raise exception 'cleaning audit was selected before all requested photos completed';
  end if;
end;
$first_photo_progress$;

-- Segunda foto: ahora sí termina el checklist y el expediente pasa a submitted.
select set_config('wf03.run_2',gen_random_uuid()::text,true);
select set_config('wf03.item_2',gen_random_uuid()::text,true);

insert into public.photo_verification_runs_v2(
  id,organization_id,property_id,actor_user_id,source_type,source_id,
  verification_mode,purpose,cleaning_task_id,status
) values (
  current_setting('wf03.run_2')::uuid,
  current_setting('wf03.org')::uuid,
  current_setting('wf03.property')::uuid,
  current_setting('wf03.tenant_user')::uuid,
  'cleaning_task',
  (
    select id
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
  ),
  'manual',
  'cleaning',
  (
    select id
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
  ),
  'capturing'
);

insert into public.photo_verification_items_v2(
  id,run_id,pattern_id,storage_path
) values (
  current_setting('wf03.item_2')::uuid,
  current_setting('wf03.run_2')::uuid,
  current_setting('wf03.request_pattern_2')::uuid,
  current_setting('wf03.org')||'/'||
    current_setting('wf03.run_2')||'/'||
    current_setting('wf03.item_2')||'.jpg'
);

update public.photo_verification_runs_v2
set status='submitted',
    submitted_at=now()
where id=current_setting('wf03.run_2')::uuid;

do $second_photo_and_audit$
declare
  v_audit public.cleaning_audits_v2;
begin
  if exists(
    select 1
    from public.cleaning_photo_requests_v2
    where cleaning_task_id=(
      select id
      from public.cleaning_tasks_v2
      where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
    )
      and completed_run_id is null
  ) then
    raise exception 'cleaning checklist still has incomplete photo requests';
  end if;

  if not exists(
    select 1
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
      and status='submitted'
      and submitted_at is not null
  ) then
    raise exception 'all cleaning photos did not move domain task to submitted';
  end if;

  -- El workflow sigue activo: el cierre lo resolverá el adaptador de auditoría.
  if not exists(
    select 1
    from public.workflow_executions_v2
    where id=current_setting('wf03.cleaning_execution')::uuid
      and status='active'
  ) or not exists(
    select 1
    from public.tenant_tasks_v2
    where id=current_setting('wf03.cleaning_task')::uuid
      and status='active'
  ) then
    raise exception 'photo submission closed workflow before cleaning audit decision';
  end if;

  select * into v_audit
  from private.select_cleaning_audit_v2(
    (
      select id
      from public.cleaning_tasks_v2
      where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
    ),
    current_setting('wf03.run_2')::uuid,
    0.0,
    now()
  );

  if v_audit.id is null
    or v_audit.selected_for_review is distinct from true
    or v_audit.status<>'open' then
    raise exception 'completed cleaning did not create selected audit';
  end if;

  if (select count(*)
      from public.cleaning_audit_items_v2
      where audit_id=v_audit.id)<>2 then
    raise exception 'cleaning audit did not aggregate both submitted photo runs';
  end if;

  if not exists(
    select 1
    from public.cleaning_audit_items_v2
    where audit_id=v_audit.id
      and photo_item_id=current_setting('wf03.item_1')::uuid
  ) or not exists(
    select 1
    from public.cleaning_audit_items_v2
    where audit_id=v_audit.id
      and photo_item_id=current_setting('wf03.item_2')::uuid
  ) then
    raise exception 'cleaning audit lost one of the requested photo items';
  end if;
end;
$second_photo_and_audit$;

do $selected_audit_waits_for_review$
begin
  if not exists(
    select 1
    from public.workflow_executions_v2
    where id=current_setting('wf03.cleaning_execution')::uuid
      and status='waiting_review'
  ) or not exists(
    select 1
    from public.tenant_tasks_v2
    where id=current_setting('wf03.cleaning_task')::uuid
      and status='waiting_review'
  ) or not exists(
    select 1
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
      and status='submitted'
  ) then
    raise exception 'selected cleaning audit did not project waiting_review atomically';
  end if;

  if (
    select count(*)
    from public.workflow_execution_events_v2
    where execution_id=current_setting('wf03.cleaning_execution')::uuid
      and event_type='domain_adapter_review_selected'
  )<>1 then
    raise exception 'cleaning review selection event missing or duplicated';
  end if;

  if exists(
    select 1
    from public.workflow_execution_events_v2
    where execution_id=current_setting('wf03.cleaning_execution')::uuid
      and event_type='domain_adapter_review_selected'
      and actor_user_id is not null
  ) then
    raise exception 'automatic cleaning audit selection was attributed to a human actor';
  end if;
end;
$selected_audit_waits_for_review$;

-- Revisión humana por fotografía: la primera decisión no cierra el workflow.
do $review_first_photo$
declare
  v_result jsonb;
begin
  v_result:=public.apply_workflow_cleaning_photo_review_v1(
    current_setting('wf03.run_1')::uuid,
    current_setting('wf03.root')::uuid,
    'approved',
    null
  );

  if v_result->>'run_status'<>'approved'
    or v_result->>'audit_status'<>'open'
    or v_result->>'cleaning_status'<>'submitted'
    or v_result->>'task_status'<>'waiting_review'
    or v_result->>'execution_status'<>'waiting_review'
    or coalesce((v_result->>'all_reviewed')::boolean,false) then
    raise exception 'first cleaning audit item incorrectly closed the workflow';
  end if;

  if not exists(
    select 1
    from public.cleaning_audit_items_v2 i
    join public.cleaning_audits_v2 a on a.id=i.audit_id
    where a.cleaning_task_id=(
      select id
      from public.cleaning_tasks_v2
      where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
    )
      and i.photo_item_id=current_setting('wf03.item_1')::uuid
      and i.result='approved'
      and i.reviewed_by=current_setting('wf03.root')::uuid
  ) then
    raise exception 'first cleaning audit item did not persist human approval';
  end if;
end;
$review_first_photo$;

-- La última decisión cierra auditoría + expediente + workflow + tarjeta común
-- en la misma transacción. Un rechazo explícito domina sobre aprobaciones previas.
do $review_second_photo_rejects$
declare
  v_result jsonb;
begin
  v_result:=public.apply_workflow_cleaning_photo_review_v1(
    current_setting('wf03.run_2')::uuid,
    current_setting('wf03.root')::uuid,
    'rejected',
    'La evidencia final requiere repetir la limpieza.'
  );

  if v_result->>'run_status'<>'rejected'
    or v_result->>'audit_status'<>'closed'
    or v_result->>'cleaning_status'<>'rejected'
    or v_result->>'task_status'<>'rejected'
    or v_result->>'execution_status'<>'rejected'
    or coalesce((v_result->>'all_reviewed')::boolean,false) is distinct from true then
    raise exception 'last cleaning audit item did not reject all linked states atomically';
  end if;

  if not exists(
    select 1
    from public.cleaning_audits_v2
    where cleaning_task_id=(
      select id
      from public.cleaning_tasks_v2
      where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
    )
      and status='closed'
      and report_status='ready'
      and closed_at is not null
  ) then
    raise exception 'closed cleaning audit was not left ready for its single final report';
  end if;

  if not exists(
    select 1
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.cleaning_execution')::uuid
      and status='rejected'
      and reviewed_by=current_setting('wf03.root')::uuid
      and reviewed_at is not null
  ) then
    raise exception 'cleaning domain did not record the human reviewer on final close';
  end if;

  if (
    select count(*)
    from public.workflow_execution_events_v2
    where execution_id=current_setting('wf03.cleaning_execution')::uuid
      and event_type='domain_adapter_review_closed'
  )<>1 then
    raise exception 'cleaning audit close event missing or duplicated';
  end if;
end;
$review_second_photo_rejects$;

-- Mismo resultado final + misma foto: reintento puro, sin segundo cierre.
do $review_retry_is_idempotent$
declare
  v_result jsonb;
begin
  v_result:=public.apply_workflow_cleaning_photo_review_v1(
    current_setting('wf03.run_2')::uuid,
    current_setting('wf03.root')::uuid,
    'rejected',
    'La evidencia final requiere repetir la limpieza.'
  );

  if coalesce((v_result->>'applied_new')::boolean,true)
    or v_result->>'execution_status'<>'rejected'
    or v_result->>'cleaning_status'<>'rejected' then
    raise exception 'cleaning human review retry was not idempotent';
  end if;

  if (
    select count(*)
    from public.workflow_execution_events_v2
    where execution_id=current_setting('wf03.cleaning_execution')::uuid
      and event_type='domain_adapter_review_closed'
  )<>1 then
    raise exception 'cleaning human review retry duplicated final history';
  end if;
end;
$review_retry_is_idempotent$;

-- A second execution of the same cleaning application exercises explicit rejection.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf03.root'),
  'role','authenticated',
  'aal','aal2'
)::text,true);

do $create_reject_execution$
declare
  v_result record;
begin
  select * into v_result
  from public.execute_workflow_application_now_v1(
    current_setting('wf03.cleaning_app')::uuid,
    'wf03-cleaning-reject-execution',
    null
  )
  limit 1;

  if v_result.execution_id is null then
    raise exception 'second cleaning execution was not created';
  end if;

  perform set_config('wf03.reject_execution',v_result.execution_id::text,true);
end;
$create_reject_execution$;

reset role;

select set_config('wf03.reject_task',(
  select id::text
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf03.reject_execution')::uuid
),true);

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf03.tenant_user'),
  'role','authenticated',
  'aal','aal1'
)::text,true);

do $reject_cleaning$
declare
  v_result record;
begin
  select * into v_result
  from public.apply_workflow_task_action_v1(
    current_setting('wf03.reject_task')::uuid,
    'reject',
    'wf03-cleaning-reject',
    'No puedo realizar esta limpieza.'
  )
  limit 1;

  if v_result.task_status<>'rejected'
    or v_result.execution_status<>'rejected'
    or v_result.applied_new is distinct from true then
    raise exception 'cleaning reject did not close workflow as rejected';
  end if;
end;
$reject_cleaning$;

reset role;

do $rejected_domain_state$
begin
  if not exists(
    select 1
    from public.cleaning_tasks_v2
    where workflow_execution_id=current_setting('wf03.reject_execution')::uuid
      and status='rejected'
  ) then
    raise exception 'cleaning domain state did not follow workflow rejection';
  end if;

  if (select count(*)
      from public.workflow_execution_events_v2
      where execution_id=current_setting('wf03.reject_execution')::uuid
        and event_type='domain_adapter_state_changed'
        and details->>'action_key'='reject')<>1 then
    raise exception 'cleaning reject domain event missing or duplicated';
  end if;
end;
$rejected_domain_state$;

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

  if has_function_privilege(
    'authenticated',
    'private.workflow_apply_cleaning_decision_v1(uuid,text,uuid)',
    'EXECUTE'
  ) then
    raise exception 'authenticated client gained direct cleaning decision adapter execution';
  end if;

  if has_function_privilege(
    'authenticated',
    'private.workflow_capture_cleaning_photo_submission_v1()',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'private.select_cleaning_audit_v2(uuid,uuid,double precision,timestamp with time zone)',
    'EXECUTE'
  ) then
    raise exception 'authenticated client gained direct cleaning photo/audit adapter execution';
  end if;

  if has_function_privilege(
    'authenticated',
    'private.workflow_sync_cleaning_audit_selection_v1(uuid,uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'private.workflow_finalize_cleaning_audit_v1(uuid,uuid,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'public.apply_workflow_cleaning_photo_review_v1(uuid,uuid,text,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated client gained direct cleaning audit/workflow execution';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.apply_workflow_cleaning_photo_review_v1(uuid,uuid,text,text)',
    'EXECUTE'
  ) then
    raise exception 'service_role lost cleaning audit review bridge execution';
  end if;
end;
$private_adapter_privilege$;

rollback;
