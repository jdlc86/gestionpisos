-- WF-02 · Disparador genérico por evento. Base PostgreSQL desechable; rollback total.
begin;

select set_config('wf02.org',(
  select organization_id::text
  from public.user_roles
  where role='root' and revoked_at is null
  limit 1
),true);
select set_config('wf02.root',(
  select user_id::text
  from public.user_roles
  where role='root' and revoked_at is null
  limit 1
),true);
select set_config('wf02.owner',gen_random_uuid()::text,true);
select set_config('wf02.property',gen_random_uuid()::text,true);
select set_config('wf02.room',gen_random_uuid()::text,true);
select set_config('wf02.employee',gen_random_uuid()::text,true);
select set_config('wf02.bad_user',gen_random_uuid()::text,true);
select set_config('wf02.delete_user',gen_random_uuid()::text,true);
select set_config('wf02.occupancy',gen_random_uuid()::text,true);

insert into auth.users(id)
values(current_setting('wf02.employee')::uuid);

insert into public.profiles(user_id,organization_id,display_name,status)
values(
  current_setting('wf02.employee')::uuid,
  current_setting('wf02.org')::uuid,
  'WF02 empleado',
  'active'
);

insert into public.user_roles(user_id,organization_id,role)
values(
  current_setting('wf02.employee')::uuid,
  current_setting('wf02.org')::uuid,
  'employee'
);

insert into public.owners(id,organization_id,full_name,status)
values(
  current_setting('wf02.owner')::uuid,
  current_setting('wf02.org')::uuid,
  'WF02 owner',
  'active'
);

insert into public.properties_v2(
  id,organization_id,owner_id,name,address_line,status
) values (
  current_setting('wf02.property')::uuid,
  current_setting('wf02.org')::uuid,
  current_setting('wf02.owner')::uuid,
  'WF02 property',
  'Regression only',
  'active'
);

insert into public.rooms_v2(id,property_id,label,status)
values(
  current_setting('wf02.room')::uuid,
  current_setting('wf02.property')::uuid,
  'WF02 room',
  'active'
);

insert into public.property_staff_access_v3(
  organization_id,property_id,employee_user_id,assignment_type,can_write,granted_by
) values (
  current_setting('wf02.org')::uuid,
  current_setting('wf02.property')::uuid,
  current_setting('wf02.employee')::uuid,
  'access',
  false,
  current_setting('wf02.root')::uuid
);

create function pg_temp.wf02_spec(
  p_name text,
  p_fixed uuid,
  p_event_type text default 'occupancy.created'
)
returns jsonb
language sql
stable
as $spec$
  select jsonb_build_object(
    'authoringVersion',2,
    'flowName',p_name,
    'flowType','custom',
    'flowDescription','WF02 regression only',
    'scopeType','property',
    'triggerType','event',
    'eventType',coalesce(p_event_type,''),
    'recurrence','',
    'scheduledAt','',
    'scheduledTimezone','',
    'scheduledAtUtc','',
    'customEvery','',
    'customUnit','',
    'assignmentType','fixed_person',
    'assignmentUserId',p_fixed::text,
    'assignmentRole','',
    'steps',jsonb_build_object(
      'accept',true,'photo',false,'checklist',false,'document',false
    ),
    'checklistItems','[]'::jsonb,
    'closeType','auto',
    'notifications',jsonb_build_object('onCreate',false,'onClose',false)
  );
$spec$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf02.root'),
  'role','authenticated',
  'aal','aal2'
)::text,true);

do $authoring_validation$
declare
  v_missing jsonb;
  v_manual jsonb;
begin
  v_missing:=pg_temp.wf02_spec(
    'WF02 missing event',
    current_setting('wf02.employee')::uuid,
    null
  );
  if public.workflow_authoring_complete_v1(v_missing) then
    raise exception 'event workflow without eventType was accepted';
  end if;

  v_manual:=pg_temp.wf02_spec(
    'WF02 manual event',
    current_setting('wf02.employee')::uuid
  ) || jsonb_build_object(
    'assignmentType','manual',
    'assignmentUserId',''
  );
  if public.workflow_authoring_complete_v1(v_manual) then
    raise exception 'event workflow with manual assignment was accepted';
  end if;

  if public.workflow_authoring_complete_v1(
    pg_temp.wf02_spec(
      'WF02 impossible occupancy event',
      current_setting('wf02.employee')::uuid
    ) || jsonb_build_object('scopeType','occupancy')
  ) then
    raise exception 'occupancy.created accepted an already-existing occupancy scope';
  end if;

  if public.workflow_authoring_complete_v1(
    pg_temp.wf02_spec(
      'WF04 offboarding event',
      current_setting('wf02.employee')::uuid,
      'occupancy.offboarded'
    )
  ) is distinct from true then
    raise exception 'occupancy.offboarded was rejected as an event trigger';
  end if;
end;
$authoring_validation$;

select set_config('wf02.good_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf02_spec(
      'WF02 good event',
      current_setting('wf02.employee')::uuid
    ),
    current_setting('wf02.property')::uuid,
    null,null,'{}'::uuid[],
    false,
    'wf02-good-ready',
    null,null
  )
  limit 1
),true);

select set_config('wf02.bad_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf02_spec(
      'WF02 bad event',
      current_setting('wf02.bad_user')::uuid
    ),
    current_setting('wf02.property')::uuid,
    null,null,'{}'::uuid[],
    false,
    'wf02-bad-ready',
    null,null
  )
  limit 1
),true);

do $create_deletable_failed_flow$
declare
  v_ready record;
begin
  select * into v_ready
  from public.publish_workflow_ready_v1(
    pg_temp.wf02_spec(
      'WF02 deletable failed event',
      current_setting('wf02.delete_user')::uuid
    ),
    current_setting('wf02.property')::uuid,
    null,null,'{}'::uuid[],
    false,
    'wf02-delete-ready',
    null,null
  )
  limit 1;

  perform set_config('wf02.delete_definition',v_ready.definition_id::text,true);
  perform set_config('wf02.delete_app',v_ready.application_id::text,true);
end;
$create_deletable_failed_flow$;

do $manual_execution_forbidden$
begin
  begin
    perform *
    from public.execute_workflow_application_now_v1(
      current_setting('wf02.good_app')::uuid,
      'wf02-manual-forbidden',
      null
    );
    raise exception 'event workflow was executed manually';
  exception when object_not_in_prerequisite_state then
    if sqlerrm<>'workflow_event_manual_execution_forbidden' then
      raise;
    end if;
  end;
end;
$manual_execution_forbidden$;

reset role;

insert into public.occupancies_v2(
  id,organization_id,property_id,room_id,occupant_email,
  starts_on,ends_on,status,user_id,tenant_id
) values (
  current_setting('wf02.occupancy')::uuid,
  current_setting('wf02.org')::uuid,
  current_setting('wf02.property')::uuid,
  current_setting('wf02.room')::uuid,
  'wf02-occupant@example.invalid',
  current_date,
  null,
  'active',
  null,
  null
);

do $outbox_decoupling$
declare
  v_event public.workflow_event_outbox_v2;
begin
  select * into v_event
  from public.workflow_event_outbox_v2
  where source_id=current_setting('wf02.occupancy')::uuid
    and event_type='occupancy.created';

  if v_event.id is null
    or v_event.status<>'pending'
    or v_event.property_id is distinct from current_setting('wf02.property')::uuid
    or v_event.room_id is distinct from current_setting('wf02.room')::uuid
    or v_event.occupancy_id is distinct from current_setting('wf02.occupancy')::uuid then
    raise exception 'occupancy.created was not captured correctly';
  end if;

  if v_event.payload ? 'email' or v_event.payload ? 'occupant_email' then
    raise exception 'event outbox persisted unnecessary PII';
  end if;

  if exists(
    select 1
    from public.workflow_executions_v2 e
    where e.application_id in (
      current_setting('wf02.good_app')::uuid,
      current_setting('wf02.bad_app')::uuid,
      current_setting('wf02.delete_app')::uuid
    )
  ) then
    raise exception 'business insert synchronously executed a workflow';
  end if;
end;
$outbox_decoupling$;

select private.process_pending_workflow_events_v1(50);

do $dispatch_results$
declare
  v_event_id uuid;
  v_good_execution uuid;
begin
  select id into v_event_id
  from public.workflow_event_outbox_v2
  where source_id=current_setting('wf02.occupancy')::uuid
    and event_type='occupancy.created';

  if not exists(
    select 1
    from public.workflow_event_outbox_v2 e
    where e.id=v_event_id
      and e.status='pending'
      and e.processed_at is null
  ) then
    raise exception 'event with one failed application was not left pending for retry';
  end if;

  select e.id into v_good_execution
  from public.workflow_executions_v2 e
  where e.application_id=current_setting('wf02.good_app')::uuid
    and e.trigger_kind='event'
    and e.idempotency_key='event:'||v_event_id::text;

  if v_good_execution is null then
    raise exception 'event did not create the expected workflow execution';
  end if;

  if not exists(
    select 1
    from public.tenant_tasks_v2 t
    where t.source_kind='workflow_execution'
      and t.source_id=v_good_execution
      and t.assigned_user_id=current_setting('wf02.employee')::uuid
  ) then
    raise exception 'event execution did not materialize its task';
  end if;

  if not exists(
    select 1
    from public.workflow_event_dispatches_v2 d
    where d.event_id=v_event_id
      and d.application_id=current_setting('wf02.good_app')::uuid
      and d.execution_id=v_good_execution
      and d.status='executed'
  ) then
    raise exception 'successful event dispatch receipt is missing';
  end if;

  if not exists(
    select 1
    from public.workflow_event_dispatches_v2 d
    where d.event_id=v_event_id
      and d.application_id=current_setting('wf02.bad_app')::uuid
      and d.execution_id is null
      and d.status='failed'
      and d.error_code is not null
  ) then
    raise exception 'failed event dispatch receipt is missing';
  end if;

  if not exists(
    select 1
    from public.workflow_event_dispatches_v2 d
    where d.event_id=v_event_id
      and d.application_id=current_setting('wf02.delete_app')::uuid
      and d.execution_id is null
      and d.status='failed'
      and d.error_code is not null
  ) then
    raise exception 'deletable failed dispatch receipt is missing';
  end if;

  if not exists(
    select 1
    from public.occupancies_v2 o
    where o.id=current_setting('wf02.occupancy')::uuid
      and o.status='active'
  ) then
    raise exception 'workflow dispatch failure rolled back the business event';
  end if;
end;
$dispatch_results$;

-- Un recibo fallido no debe convertir un flujo sin ejecuciones en histórico ni
-- bloquear su eliminación. El recibo queda como snapshot técnico del intento.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf02.root'),
  'role','authenticated',
  'aal','aal2'
)::text,true);

select public.delete_unexecuted_workflow_v1(
  current_setting('wf02.delete_definition')::uuid
);

reset role;

do $failed_receipt_does_not_block_delete$
begin
  if exists(
    select 1
    from public.workflow_definitions_v2 d
    where d.id=current_setting('wf02.delete_definition')::uuid
  ) or exists(
    select 1
    from public.workflow_applications_v2 a
    where a.id=current_setting('wf02.delete_app')::uuid
  ) then
    raise exception 'failed event receipt blocked deletion of an unexecuted workflow';
  end if;

  if not exists(
    select 1
    from public.workflow_event_dispatches_v2 d
    where d.application_id=current_setting('wf02.delete_app')::uuid
      and d.status='failed'
  ) then
    raise exception 'failed dispatch snapshot was lost when deleting unexecuted workflow';
  end if;
end;
$failed_receipt_does_not_block_delete$;

-- Una aplicación publicada después del evento no puede capturarlo de forma
-- retroactiva aunque el outbox siga pendiente por otro fallo.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf02.root'),
  'role','authenticated',
  'aal','aal2'
)::text,true);

do $create_late_flow$
declare
  v_ready record;
begin
  select * into v_ready
  from public.publish_workflow_ready_v1(
    pg_temp.wf02_spec(
      'WF02 late event flow',
      current_setting('wf02.employee')::uuid
    ),
    current_setting('wf02.property')::uuid,
    null,null,'{}'::uuid[],
    false,
    'wf02-late-ready',
    null,null
  )
  limit 1;

  perform set_config('wf02.late_definition',v_ready.definition_id::text,true);
  perform set_config('wf02.late_version',v_ready.version_id::text,true);
  perform set_config('wf02.late_app',v_ready.application_id::text,true);
end;
$create_late_flow$;

reset role;

update public.workflow_applications_v2 a
set created_at=(
  select e.occurred_at + interval '1 minute'
  from public.workflow_event_outbox_v2 e
  where e.source_id=current_setting('wf02.occupancy')::uuid
    and e.event_type='occupancy.created'
)
where a.id=current_setting('wf02.late_app')::uuid;

update public.workflow_definition_versions_v2 v
set published_at=(
  select e.occurred_at + interval '1 minute'
  from public.workflow_event_outbox_v2 e
  where e.source_id=current_setting('wf02.occupancy')::uuid
    and e.event_type='occupancy.created'
)
where v.id=current_setting('wf02.late_version')::uuid;

-- El fallo original se vuelve elegible después. El siguiente intento debe crear
-- solo la ejecución que faltaba, conservar la ya creada y omitir el flujo tardío.
insert into auth.users(id)
values(current_setting('wf02.bad_user')::uuid);

insert into public.profiles(user_id,organization_id,display_name,status)
values(
  current_setting('wf02.bad_user')::uuid,
  current_setting('wf02.org')::uuid,
  'WF02 retry employee',
  'active'
);

insert into public.user_roles(user_id,organization_id,role)
values(
  current_setting('wf02.bad_user')::uuid,
  current_setting('wf02.org')::uuid,
  'employee'
);

insert into public.property_staff_access_v3(
  organization_id,property_id,employee_user_id,assignment_type,can_write,granted_by
) values (
  current_setting('wf02.org')::uuid,
  current_setting('wf02.property')::uuid,
  current_setting('wf02.bad_user')::uuid,
  'access',
  false,
  current_setting('wf02.root')::uuid
);

select private.process_pending_workflow_events_v1(50);

do $retry_and_idempotency$
declare
  v_event_id uuid;
  v_same_event uuid;
  v_good_count integer;
  v_bad_count integer;
begin
  select id into v_event_id
  from public.workflow_event_outbox_v2
  where source_id=current_setting('wf02.occupancy')::uuid
    and event_type='occupancy.created';

  if not exists(
    select 1
    from public.workflow_event_outbox_v2 e
    where e.id=v_event_id
      and e.status='processed'
      and e.processed_at is not null
  ) then
    raise exception 'retried event did not converge to processed';
  end if;

  if not exists(
    select 1
    from public.workflow_event_dispatches_v2 d
    where d.event_id=v_event_id
      and d.application_id=current_setting('wf02.bad_app')::uuid
      and d.execution_id is not null
      and d.status='executed'
      and d.error_code is null
  ) then
    raise exception 'failed dispatch did not recover on retry';
  end if;

  v_same_event:=private.workflow_enqueue_event_v1(
    current_setting('wf02.org')::uuid,
    'occupancy.created',
    'occupancy',
    current_setting('wf02.occupancy')::uuid,
    'created',
    current_setting('wf02.property')::uuid,
    current_setting('wf02.room')::uuid,
    current_setting('wf02.occupancy')::uuid,
    '{}'::jsonb,
    null,
    now()
  );

  if v_same_event is distinct from v_event_id then
    raise exception 'duplicate source event produced another outbox identity';
  end if;

  if private.process_pending_workflow_events_v1(50)<>0 then
    raise exception 'already processed event was dispatched twice';
  end if;

  select count(*) into v_good_count
  from public.workflow_executions_v2 e
  where e.application_id=current_setting('wf02.good_app')::uuid
    and e.idempotency_key='event:'||v_event_id::text;

  select count(*) into v_bad_count
  from public.workflow_executions_v2 e
  where e.application_id=current_setting('wf02.bad_app')::uuid
    and e.idempotency_key='event:'||v_event_id::text;

  if v_good_count<>1 or v_bad_count<>1 then
    raise exception 'event retry duplicated or missed an execution';
  end if;

  if exists(
    select 1
    from public.workflow_executions_v2 e
    where e.application_id=current_setting('wf02.late_app')::uuid
  ) or exists(
    select 1
    from public.workflow_event_dispatches_v2 d
    where d.event_id=v_event_id
      and d.application_id=current_setting('wf02.late_app')::uuid
  ) then
    raise exception 'workflow created after source event consumed it retroactively';
  end if;
end;
$retry_and_idempotency$;

do $privileges$
begin
  if has_table_privilege('authenticated','public.workflow_event_outbox_v2','INSERT')
    or has_table_privilege('authenticated','public.workflow_event_dispatches_v2','INSERT')
    or has_function_privilege(
      'authenticated',
      'private.workflow_enqueue_event_v1(uuid,text,text,uuid,text,uuid,uuid,uuid,jsonb,uuid,timestamptz)',
      'EXECUTE'
    )
    or has_function_privilege(
      'authenticated',
      'private.process_pending_workflow_events_v1(integer)',
      'EXECUTE'
    ) then
    raise exception 'client gained direct event-dispatch privileges';
  end if;
end;
$privileges$;

rollback;
