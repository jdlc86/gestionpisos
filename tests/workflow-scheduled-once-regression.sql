-- Flujos · regresión Fecha concreta.
-- PostgreSQL desechable. Todo se revierte al finalizar.

begin;

-- Actor ROOT del fixture.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','22222222-2222-4222-8222-222222222222',
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

-- 1. Fecha concreta + asignación manual fijada al programar.
select set_config(
  'gestionpisos.schedule.manual_app',
  (
    select application_id::text
    from public.publish_workflow_ready_v2(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Programada manual',
        'flowType','custom',
        'flowDescription','Regresión scheduled once',
        'scopeType','organization',
        'triggerType','scheduled_once',
        'recurrence','',
        'scheduledAt',to_char((now()+interval '10 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI'),
        'scheduledTimezone','UTC',
        'scheduledAtUtc',to_char((now()+interval '10 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',true,'onClose',false)
      ),
      null,null,null,'{}'::uuid[],
      false,
      'regression-scheduled-manual',
      null,
      null,
      'UTC',
      '22222222-2222-4222-8222-222222222222'::uuid
    )
    limit 1
  ),
  true
);

do $scheduled_initial$
declare
  v_app uuid:=current_setting('gestionpisos.schedule.manual_app')::uuid;
begin
  if exists(
    select 1 from public.workflow_executions_v2 where application_id=v_app
  ) then
    raise exception 'scheduled workflow created execution before due time';
  end if;

  if exists(
    select 1 from public.tenant_tasks_v2 t
    join public.workflow_executions_v2 e on e.id=t.source_id
    where t.source_kind='workflow_execution'
      and e.application_id=v_app
  ) then
    raise exception 'scheduled workflow created task before due time';
  end if;

  if not exists(
    select 1
    from public.workflow_application_schedules_v2 s
    join public.workflow_applications_v2 a on a.id=s.application_id
    join public.workflow_definition_versions_v2 v on v.id=a.definition_version_id
    where s.application_id=v_app
      and s.status='active'
      and s.schedule_kind='scheduled_once'
      and s.schedule_timezone='UTC'
      and s.scheduled_assigned_user_id='22222222-2222-4222-8222-222222222222'::uuid
      and s.next_run_at>now()
      and v.spec->>'scheduledTimezone'='UTC'
      and nullif(v.spec->>'scheduledAtUtc','') is not null
  ) then
    raise exception 'scheduled workflow did not persist exact schedule binding';
  end if;
end;
$scheduled_initial$;

-- 1b. Antes de la primera ejecución, editar/reprogramar conserva la misma
-- definición/version y sustituye la aplicación operativa sin crear tarea.
select set_config(
  'gestionpisos.schedule.manual_definition',
  (
    select definition_id::text
    from public.workflow_applications_v2
    where id=current_setting('gestionpisos.schedule.manual_app')::uuid
  ),
  true
);

select set_config(
  'gestionpisos.schedule.manual_version',
  (
    select definition_version_id::text
    from public.workflow_applications_v2
    where id=current_setting('gestionpisos.schedule.manual_app')::uuid
  ),
  true
);

select set_config(
  'gestionpisos.schedule.manual_app',
  (
    select application_id::text
    from public.update_unexecuted_workflow_v2(
      current_setting('gestionpisos.schedule.manual_definition')::uuid,
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Programada manual editada',
        'flowType','custom',
        'flowDescription','Reprogramada antes de ejecutar',
        'scopeType','organization',
        'triggerType','scheduled_once',
        'recurrence','',
        'scheduledAt',to_char((now()+interval '15 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI'),
        'scheduledTimezone','UTC',
        'scheduledAtUtc',to_char((now()+interval '15 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',true,'onClose',false)
      ),
      null,null,null,'{}'::uuid[],
      (
        select revision
        from public.workflow_definitions_v2
        where id=current_setting('gestionpisos.schedule.manual_definition')::uuid
      ),
      false,
      null,
      null,
      'UTC',
      '22222222-2222-4222-8222-222222222222'::uuid
    )
    limit 1
  ),
  true
);

do $scheduled_reprogrammed$
declare
  v_app uuid:=current_setting('gestionpisos.schedule.manual_app')::uuid;
  v_definition uuid:=current_setting('gestionpisos.schedule.manual_definition')::uuid;
  v_version uuid:=current_setting('gestionpisos.schedule.manual_version')::uuid;
begin
  if exists(
    select 1
    from public.workflow_executions_v2 e
    join public.workflow_applications_v2 a on a.id=e.application_id
    where a.definition_id=v_definition
  ) then
    raise exception 'reprogramming created an execution before due time';
  end if;

  if not exists(
    select 1
    from public.workflow_applications_v2 a
    join public.workflow_definition_versions_v2 v on v.id=a.definition_version_id
    join public.workflow_application_schedules_v2 s on s.application_id=a.id
    where a.id=v_app
      and a.definition_id=v_definition
      and a.definition_version_id=v_version
      and v.version=1
      and v.spec->>'scheduledTimezone'='UTC'
      and nullif(v.spec->>'scheduledAtUtc','') is not null
      and s.status='active'
      and s.schedule_timezone='UTC'
      and s.scheduled_assigned_user_id='22222222-2222-4222-8222-222222222222'::uuid
      and s.next_run_at>now()
  ) then
    raise exception 'reprogramming did not preserve version and exact schedule';
  end if;

  if (
    select count(*)
    from public.workflow_applications_v2
    where definition_id=v_definition
      and status='configured'
  )<>1 then
    raise exception 'reprogramming left multiple configured applications';
  end if;
end;
$scheduled_reprogrammed$;

-- Un Fecha concreta no puede crearse por el endpoint manual.
do $manual_forbidden$
begin
  perform *
  from public.execute_workflow_application_now_v1(
    current_setting('gestionpisos.schedule.manual_app')::uuid,
    'regression-manual-override',
    '22222222-2222-4222-8222-222222222222'::uuid
  );
  raise exception 'scheduled workflow unexpectedly allowed manual execution';
exception
  when sqlstate '55000' then
    if sqlerrm<>'workflow_scheduled_manual_execution_forbidden' then
      raise;
    end if;
end;
$manual_forbidden$;

reset role;

-- Disparo automático al llegar la hora.
do $run_manual_schedule$
declare
  v_app uuid:=current_setting('gestionpisos.schedule.manual_app')::uuid;
  v_due timestamptz;
  v_count integer;
begin
  select next_run_at into v_due
  from public.workflow_application_schedules_v2
  where application_id=v_app;

  select private.process_due_workflow_schedules_v1(v_due+interval '1 minute')
  into v_count;

  if v_count<>1 then
    raise exception 'scheduled processor did not process exactly one due application';
  end if;

  if not exists(
    select 1
    from public.workflow_executions_v2 e
    join public.tenant_tasks_v2 t
      on t.source_kind='workflow_execution'
     and t.source_id=e.id
    where e.application_id=v_app
      and e.trigger_kind='scheduled_once'
      and e.assigned_user_id='22222222-2222-4222-8222-222222222222'::uuid
      and e.status='pending'
      and t.assigned_user_id=e.assigned_user_id
      and t.status=e.status
      and e.spec_snapshot->>'scheduledTimezone'='UTC'
      and nullif(e.spec_snapshot->>'scheduledAtUtc','') is not null
  ) then
    raise exception 'scheduled processor did not materialize the canonical execution/task';
  end if;

  if not exists(
    select 1
    from public.workflow_application_schedules_v2
    where application_id=v_app
      and status='completed'
      and last_execution_id is not null
  ) then
    raise exception 'scheduled row did not become completed';
  end if;

  if private.process_due_workflow_schedules_v1(v_due+interval '2 minutes')<>0 then
    raise exception 'completed scheduled workflow was processed twice';
  end if;

  if (
    select count(*)
    from public.workflow_executions_v2
    where application_id=v_app
  )<>1 then
    raise exception 'scheduled workflow duplicated its execution';
  end if;
end;
$run_manual_schedule$;

-- 2. Responsable operativo: puede programarse sin responsable hoy; se resuelve al disparar.
insert into auth.users(id)
values ('33333333-3333-4333-8333-333333333333')
on conflict(id) do nothing;

insert into public.user_roles(user_id,organization_id,role)
values (
  '33333333-3333-4333-8333-333333333333',
  '11111111-1111-4111-8111-111111111111',
  'employee'
)
on conflict do nothing;

insert into public.owners(
  id,organization_id,full_name,email,status
) values (
  '44444444-4444-4444-8444-444444444444',
  '11111111-1111-4111-8111-111111111111',
  'Owner scheduled test',
  'owner-scheduled@example.invalid',
  'active'
);

insert into public.properties_v2(
  id,organization_id,owner_id,name,address_line,status
) values (
  '55555555-5555-4555-8555-555555555555',
  '11111111-1111-4111-8111-111111111111',
  '44444444-4444-4444-8444-444444444444',
  'Piso scheduled',
  'Calle Test 1',
  'active'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','22222222-2222-4222-8222-222222222222',
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

select set_config(
  'gestionpisos.schedule.responsible_app',
  (
    select application_id::text
    from public.publish_workflow_ready_v2(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Programada responsable',
        'flowType','custom',
        'flowDescription','Responsable dinámico',
        'scopeType','property',
        'triggerType','scheduled_once',
        'recurrence','',
        'scheduledAt',to_char((now()+interval '20 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI'),
        'scheduledTimezone','UTC',
        'scheduledAtUtc',to_char((now()+interval '20 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'customEvery','',
        'customUnit','',
        'assignmentType','property_responsible',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      '55555555-5555-4555-8555-555555555555'::uuid,
      null,null,'{}'::uuid[],
      false,
      'regression-scheduled-responsible',
      null,
      null,
      'UTC',
      null
    )
    limit 1
  ),
  true
);

reset role;

do $responsible_not_frozen$
begin
  if not exists(
    select 1
    from public.workflow_application_schedules_v2
    where application_id=current_setting('gestionpisos.schedule.responsible_app')::uuid
      and status='active'
      and scheduled_assigned_user_id is null
  ) then
    raise exception 'property responsible schedule froze an assignee at programming time';
  end if;
end;
$responsible_not_frozen$;

-- El responsable aparece después de programar, antes del disparo.
insert into public.property_staff_access_v3(
  organization_id,property_id,employee_user_id,assignment_type,
  can_write,valid_from,valid_until,granted_by,revoked_at
) values (
  '11111111-1111-4111-8111-111111111111',
  '55555555-5555-4555-8555-555555555555',
  '33333333-3333-4333-8333-333333333333',
  'responsible',
  true,
  now(),
  null,
  '22222222-2222-4222-8222-222222222222',
  null
);

do $run_responsible_schedule$
declare
  v_app uuid:=current_setting('gestionpisos.schedule.responsible_app')::uuid;
  v_due timestamptz;
begin
  select next_run_at into v_due
  from public.workflow_application_schedules_v2
  where application_id=v_app;

  perform private.process_due_workflow_schedules_v1(v_due+interval '1 minute');

  if not exists(
    select 1
    from public.workflow_executions_v2
    where application_id=v_app
      and trigger_kind='scheduled_once'
      and assigned_user_id='33333333-3333-4333-8333-333333333333'::uuid
  ) then
    raise exception 'property responsible was not resolved at scheduled execution time';
  end if;
end;
$run_responsible_schedule$;

-- 3. Sin responsable al llegar la hora: queda blocked y avisa al creador.
insert into public.properties_v2(
  id,organization_id,owner_id,name,address_line,status
) values (
  '66666666-6666-4666-8666-666666666666',
  '11111111-1111-4111-8111-111111111111',
  '44444444-4444-4444-8444-444444444444',
  'Piso scheduled blocked',
  'Calle Test 2',
  'active'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','22222222-2222-4222-8222-222222222222',
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

select set_config(
  'gestionpisos.schedule.blocked_app',
  (
    select application_id::text
    from public.publish_workflow_ready_v2(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Programada bloqueada',
        'flowType','custom',
        'flowDescription','Sin responsable al disparar',
        'scopeType','property',
        'triggerType','scheduled_once',
        'recurrence','',
        'scheduledAt',to_char((now()+interval '30 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI'),
        'scheduledTimezone','UTC',
        'scheduledAtUtc',to_char((now()+interval '30 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'customEvery','',
        'customUnit','',
        'assignmentType','property_responsible',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      '66666666-6666-4666-8666-666666666666'::uuid,
      null,null,'{}'::uuid[],
      false,
      'regression-scheduled-blocked',
      null,
      null,
      'UTC',
      null
    )
    limit 1
  ),
  true
);

reset role;

do $blocked_schedule$
declare
  v_app uuid:=current_setting('gestionpisos.schedule.blocked_app')::uuid;
  v_due timestamptz;
begin
  select next_run_at into v_due
  from public.workflow_application_schedules_v2
  where application_id=v_app;

  perform private.process_due_workflow_schedules_v1(v_due+interval '1 minute');

  if not exists(
    select 1
    from public.workflow_application_schedules_v2
    where application_id=v_app
      and status='blocked'
      and last_error_code='55000'
      and last_error_at is not null
  ) then
    raise exception 'failed scheduled execution did not become safely blocked';
  end if;

  if exists(
    select 1 from public.workflow_executions_v2 where application_id=v_app
  ) then
    raise exception 'blocked scheduled execution left a partial execution';
  end if;

  if not exists(
    select 1
    from public.notifications_v2
    where source_kind='workflow_schedule'
      and source_id=v_app
      and event_type='workflow_schedule_blocked'
      and event_key like 'blocked:%'
      and recipient_user_id='22222222-2222-4222-8222-222222222222'::uuid
      and channel_in_app=true
      and channel_email=false
  ) then
    raise exception 'blocked schedule did not notify its creator';
  end if;
end;
$blocked_schedule$;

-- 4. Zona/UTC deben coincidir. El wrapper completo revierte la publicación si no coinciden.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','22222222-2222-4222-8222-222222222222',
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

do $timezone_mismatch$
begin
  perform *
  from public.publish_workflow_ready_v2(
    jsonb_build_object(
      'authoringVersion',2,
      'flowName','Programada inválida',
      'flowType','custom',
      'flowDescription','Mismatch timezone',
      'scopeType','organization',
      'triggerType','scheduled_once',
      'recurrence','',
      'scheduledAt','2099-01-01T10:00',
      'scheduledTimezone','UTC',
      'scheduledAtUtc','2099-01-01T11:00:00Z',
      'customEvery','',
      'customUnit','',
      'assignmentType','manual',
      'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
      'checklistItems','[]'::jsonb,
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',false,'onClose',false)
    ),
    null,null,null,'{}'::uuid[],
    false,
    'regression-scheduled-mismatch',
    null,
    null,
    'UTC',
    '22222222-2222-4222-8222-222222222222'::uuid
  );
  raise exception 'timezone mismatch unexpectedly published';
exception
  when sqlstate '22023' then
    if sqlerrm<>'workflow_schedule_time_mismatch' then
      raise;
    end if;
end;
$timezone_mismatch$;

reset role;

-- 5. Una hora local repetida por cambio DST no puede programarse silenciosamente.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','22222222-2222-4222-8222-222222222222',
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

do $ambiguous_dst$
begin
  perform *
  from public.publish_workflow_ready_v2(
    jsonb_build_object(
      'authoringVersion',2,
      'flowName','Programada DST ambigua',
      'flowType','custom',
      'flowDescription','Hora repetida Europe/Madrid',
      'scopeType','organization',
      'triggerType','scheduled_once',
      'recurrence','',
      'scheduledAt','2026-10-25T02:30',
      'scheduledTimezone','Europe/Madrid',
      'scheduledAtUtc','2026-10-25T00:30:00Z',
      'customEvery','',
      'customUnit','',
      'assignmentType','manual',
      'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
      'checklistItems','[]'::jsonb,
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',false,'onClose',false)
    ),
    null,null,null,'{}'::uuid[],
    false,
    'regression-scheduled-dst-ambiguous',
    null,
    null,
    'Europe/Madrid',
    '22222222-2222-4222-8222-222222222222'::uuid
  );
  raise exception 'ambiguous DST wall time unexpectedly published';
exception
  when sqlstate '22023' then
    if sqlerrm<>'workflow_schedule_local_time_ambiguous' then
      raise;
    end if;
end;
$ambiguous_dst$;

reset role;

rollback;
