-- Flujos · regresión de ejecución recurrente.
-- PostgreSQL desechable. Todo se revierte al finalizar.

begin;

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

-- 1. Recurrente semanal + asignación manual fijada al programar.
select set_config(
  'gestionpisos.recurring.weekly_app',
  (
    select application_id::text
    from public.publish_workflow_ready_v2(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Recurrente semanal',
        'flowType','custom',
        'flowDescription','Regresión recurring semanal',
        'scopeType','organization',
        'triggerType','recurring',
        'recurrence','weekly',
        'scheduledAt',to_char(date_trunc('minute',now()+interval '10 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI'),
        'scheduledTimezone','UTC',
        'scheduledAtUtc',to_char(date_trunc('minute',now()+interval '10 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
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
      'regression-recurring-weekly',
      null,
      null,
      'UTC',
      '22222222-2222-4222-8222-222222222222'::uuid
    )
    limit 1
  ),
  true
);

do $weekly_initial$
declare
  v_app uuid:=current_setting('gestionpisos.recurring.weekly_app')::uuid;
begin
  if exists(select 1 from public.workflow_executions_v2 where application_id=v_app) then
    raise exception 'recurring workflow created execution before first due time';
  end if;

  if not exists(
    select 1
    from public.workflow_application_schedules_v2 s
    join public.workflow_applications_v2 a on a.id=s.application_id
    join public.workflow_definition_versions_v2 v on v.id=a.definition_version_id
    where s.application_id=v_app
      and s.schedule_kind='recurring'
      and s.status='active'
      and s.next_occurrence_index=0
      and s.execution_count=0
      and s.scheduled_assigned_user_id='22222222-2222-4222-8222-222222222222'::uuid
      and v.spec->>'triggerType'='recurring'
      and v.spec->>'scheduledTimezone'='UTC'
      and nullif(v.spec->>'scheduledAtUtc','') is not null
  ) then
    raise exception 'recurring schedule binding missing';
  end if;
end;
$weekly_initial$;

-- No puede saltarse la programación con ejecución manual.
do $weekly_manual_forbidden$
begin
  perform *
  from public.execute_workflow_application_now_v1(
    current_setting('gestionpisos.recurring.weekly_app')::uuid,
    'regression-recurring-manual-override',
    '22222222-2222-4222-8222-222222222222'::uuid
  );
  raise exception 'recurring workflow unexpectedly allowed manual execution';
exception
  when sqlstate '55000' then
    if sqlerrm<>'workflow_recurring_manual_execution_forbidden' then
      raise;
    end if;
end;
$weekly_manual_forbidden$;

reset role;

-- Primera ocurrencia: una ejecución/tarea y schedule sigue activo.
do $weekly_first$
declare
  v_app uuid:=current_setting('gestionpisos.recurring.weekly_app')::uuid;
  v_due timestamptz;
  v_next timestamptz;
begin
  select next_run_at into v_due
  from public.workflow_application_schedules_v2
  where application_id=v_app;

  if private.process_due_workflow_schedules_v1(v_due+interval '1 minute')<>1 then
    raise exception 'recurring first occurrence was not processed exactly once';
  end if;

  if (
    select count(*)
    from public.workflow_executions_v2 e
    join public.tenant_tasks_v2 t
      on t.source_kind='workflow_execution' and t.source_id=e.id
    where e.application_id=v_app
      and e.trigger_kind='recurring'
      and e.assigned_user_id='22222222-2222-4222-8222-222222222222'::uuid
      and t.assigned_user_id=e.assigned_user_id
  )<>1 then
    raise exception 'recurring first occurrence did not materialize one canonical task';
  end if;

  select next_run_at into v_next
  from public.workflow_application_schedules_v2
  where application_id=v_app
    and status='active'
    and execution_count=1
    and next_occurrence_index=1
    and last_scheduled_for=v_due;

  if v_next is null or v_next<=v_due then
    raise exception 'recurring schedule did not advance after first occurrence';
  end if;

  if private.process_due_workflow_schedules_v1(v_due+interval '2 minutes')<>0 then
    raise exception 'recurring first occurrence was duplicated';
  end if;
end;
$weekly_first$;

-- Segunda ocurrencia: vuelve a materializar una tarea y conserva la programación.
do $weekly_second$
declare
  v_app uuid:=current_setting('gestionpisos.recurring.weekly_app')::uuid;
  v_due timestamptz;
begin
  select next_run_at into v_due
  from public.workflow_application_schedules_v2
  where application_id=v_app;

  if private.process_due_workflow_schedules_v1(v_due+interval '1 minute')<>1 then
    raise exception 'recurring second occurrence was not processed';
  end if;

  if (select count(*) from public.workflow_executions_v2 where application_id=v_app)<>2 then
    raise exception 'recurring second occurrence did not create exactly a second execution';
  end if;

  if not exists(
    select 1
    from public.workflow_application_schedules_v2
    where application_id=v_app
      and status='active'
      and execution_count=2
      and next_occurrence_index=2
      and next_run_at>v_due
  ) then
    raise exception 'recurring schedule did not remain active after second occurrence';
  end if;
end;
$weekly_second$;

-- 2. Tras una interrupción larga no hay tormenta de catch-up:
-- se crea una sola tarea y se avanza a la primera fecha futura.
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
  'gestionpisos.recurring.catchup_app',
  (
    select application_id::text
    from public.publish_workflow_ready_v2(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Recurrente catchup',
        'flowType','custom',
        'flowDescription','Salta ocurrencias vencidas',
        'scopeType','organization',
        'triggerType','recurring',
        'recurrence','custom',
        'scheduledAt',to_char(date_trunc('minute',now()+interval '20 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI'),
        'scheduledTimezone','UTC',
        'scheduledAtUtc',to_char(date_trunc('minute',now()+interval '20 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'customEvery','1',
        'customUnit','day',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      null,null,null,'{}'::uuid[],
      false,
      'regression-recurring-catchup',
      null,
      null,
      'UTC',
      '22222222-2222-4222-8222-222222222222'::uuid
    )
    limit 1
  ),
  true
);

reset role;

do $catchup$
declare
  v_app uuid:=current_setting('gestionpisos.recurring.catchup_app')::uuid;
  v_due timestamptz;
  v_now timestamptz;
begin
  select next_run_at into v_due
  from public.workflow_application_schedules_v2
  where application_id=v_app;

  v_now:=v_due+interval '3 days 1 minute';
  perform private.process_due_workflow_schedules_v1(v_now);

  if (select count(*) from public.workflow_executions_v2 where application_id=v_app)<>1 then
    raise exception 'catch-up created more than one execution';
  end if;

  if not exists(
    select 1
    from public.workflow_application_schedules_v2
    where application_id=v_app
      and status='active'
      and execution_count=1
      and next_occurrence_index=4
      and next_run_at>v_now
  ) then
    raise exception 'catch-up did not advance to first future occurrence';
  end if;

  if not exists(
    select 1
    from public.audit_log_v2
    where entity_type='workflow_application'
      and entity_id=v_app::text
      and action='workflow_recurring_occurrences_skipped'
      and (details->>'skipped_count')::integer=3
  ) then
    raise exception 'catch-up did not audit skipped occurrences';
  end if;
end;
$catchup$;

-- 3. Calendario mensual anclado: 31 ene -> último día feb -> 31 mar.
do $monthly_anchor$
declare
  v_spec jsonb:=jsonb_build_object(
    'triggerType','recurring',
    'recurrence','monthly',
    'scheduledAt','2099-01-31T10:00',
    'scheduledTimezone','UTC',
    'scheduledAtUtc','2099-01-31T10:00:00Z',
    'customEvery','',
    'customUnit',''
  );
  v_feb timestamptz;
  v_mar timestamptz;
begin
  v_feb:=private.workflow_recurring_occurrence_v1(v_spec,1);
  v_mar:=private.workflow_recurring_occurrence_v1(v_spec,2);

  if v_feb<>'2099-02-28T10:00:00Z'::timestamptz then
    raise exception 'monthly recurrence did not clamp January 31 to February last day';
  end if;
  if v_mar<>'2099-03-31T10:00:00Z'::timestamptz then
    raise exception 'monthly recurrence drifted after February clamp';
  end if;
end;
$monthly_anchor$;

-- 4. Si la próxima ocurrencia cae en una hora DST ambigua, la tarea actual
-- se conserva y solo el futuro de la programación queda bloqueado.
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
  'gestionpisos.recurring.dst_app',
  (
    select application_id::text
    from public.publish_workflow_ready_v2(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Recurrente DST futura',
        'flowType','custom',
        'flowDescription','Próxima ocurrencia ambigua',
        'scopeType','organization',
        'triggerType','recurring',
        'recurrence','weekly',
        'scheduledAt','2099-10-18T02:30',
        'scheduledTimezone','Europe/Madrid',
        'scheduledAtUtc','2099-10-18T00:30:00Z',
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
      'regression-recurring-dst',
      null,
      null,
      'Europe/Madrid',
      '22222222-2222-4222-8222-222222222222'::uuid
    )
    limit 1
  ),
  true
);

reset role;

do $dst_future_block$
declare
  v_app uuid:=current_setting('gestionpisos.recurring.dst_app')::uuid;
  v_due timestamptz;
begin
  select next_run_at into v_due
  from public.workflow_application_schedules_v2
  where application_id=v_app;

  perform private.process_due_workflow_schedules_v1(v_due+interval '1 minute');

  if (select count(*) from public.workflow_executions_v2 where application_id=v_app)<>1 then
    raise exception 'DST future block rolled back the valid current occurrence';
  end if;

  if not exists(
    select 1
    from public.workflow_application_schedules_v2
    where application_id=v_app
      and status='blocked'
      and execution_count=1
      and last_execution_id is not null
      and last_error_code='22023'
  ) then
    raise exception 'DST ambiguous future occurrence did not block only the schedule future';
  end if;

  if not exists(
    select 1
    from public.notifications_v2
    where source_kind='workflow_schedule'
      and source_id=v_app
      and event_type='workflow_schedule_blocked'
      and event_key='blocked-next:1'
  ) then
    raise exception 'DST future block did not notify creator';
  end if;
end;
$dst_future_block$;

-- 5. RPC v1 tampoco puede publicar recurring sin fila operativa.
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

do $recurring_v1_bypass$
begin
  begin
    perform *
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Recurring bypass v1',
        'flowType','custom',
        'flowDescription','Debe exigir schedule operativo',
        'scopeType','organization',
        'triggerType','recurring',
        'recurrence','weekly',
        'scheduledAt','2099-01-01T10:00',
        'scheduledTimezone','UTC',
        'scheduledAtUtc','2099-01-01T10:00:00Z',
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
      'regression-recurring-v1-bypass',
      null,
      null
    );
    set constraints workflow_scheduled_application_requires_schedule_v1 immediate;
    raise exception 'recurring v1 bypass unexpectedly committed application';
  exception
    when sqlstate '55000' then
      if sqlerrm<>'workflow_scheduled_configuration_required' then
        raise;
      end if;
  end;
end;
$recurring_v1_bypass$;

set constraints workflow_scheduled_application_requires_schedule_v1 deferred;
reset role;

-- 6. Responsable operativo se resuelve de nuevo en cada ocurrencia.
insert into auth.users(id)
values
  ('33333333-3333-4333-8333-333333333333'),
  ('77777777-7777-4777-8777-777777777777')
on conflict(id) do nothing;

insert into public.user_roles(user_id,organization_id,role)
values
  (
    '33333333-3333-4333-8333-333333333333',
    '11111111-1111-4111-8111-111111111111',
    'employee'
  ),
  (
    '77777777-7777-4777-8777-777777777777',
    '11111111-1111-4111-8111-111111111111',
    'employee'
  )
on conflict do nothing;

insert into public.owners(
  id,organization_id,full_name,email,status
) values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '11111111-1111-4111-8111-111111111111',
  'Owner recurring responsible',
  'owner-recurring-responsible@example.invalid',
  'active'
);

insert into public.properties_v2(
  id,organization_id,owner_id,name,address_line,status
) values (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '11111111-1111-4111-8111-111111111111',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'Piso recurring responsible',
  'Calle Recurrente 1',
  'active'
);

insert into public.property_staff_access_v3(
  organization_id,property_id,employee_user_id,assignment_type,
  can_write,valid_from,valid_until,granted_by,revoked_at
) values (
  '11111111-1111-4111-8111-111111111111',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '33333333-3333-4333-8333-333333333333',
  'responsible',
  true,
  now(),
  null,
  '22222222-2222-4222-8222-222222222222',
  null
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
  'gestionpisos.recurring.responsible_app',
  (
    select application_id::text
    from public.publish_workflow_ready_v2(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Recurrente responsable dinámico',
        'flowType','custom',
        'flowDescription','Resuelve responsable en cada ocurrencia',
        'scopeType','property',
        'triggerType','recurring',
        'recurrence','weekly',
        'scheduledAt',to_char(date_trunc('minute',now()+interval '40 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI'),
        'scheduledTimezone','UTC',
        'scheduledAtUtc',to_char(date_trunc('minute',now()+interval '40 minutes') at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'customEvery','',
        'customUnit','',
        'assignmentType','property_responsible',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
      null,null,'{}'::uuid[],
      false,
      'regression-recurring-responsible',
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

do $recurring_responsible_first$
declare
  v_app uuid:=current_setting('gestionpisos.recurring.responsible_app')::uuid;
  v_due timestamptz;
begin
  if not exists(
    select 1
    from public.workflow_application_schedules_v2
    where application_id=v_app
      and schedule_kind='recurring'
      and scheduled_assigned_user_id is null
  ) then
    raise exception 'recurring property responsible was frozen at programming time';
  end if;

  select next_run_at into v_due
  from public.workflow_application_schedules_v2
  where application_id=v_app;

  perform private.process_due_workflow_schedules_v1(v_due+interval '1 minute');

  if not exists(
    select 1
    from public.workflow_executions_v2
    where application_id=v_app
      and trigger_kind='recurring'
      and assigned_user_id='33333333-3333-4333-8333-333333333333'::uuid
  ) then
    raise exception 'first recurring occurrence did not resolve the current responsible';
  end if;
end;
$recurring_responsible_first$;

update public.property_staff_access_v3
set revoked_at=now()
where property_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid
  and assignment_type='responsible'
  and revoked_at is null;

insert into public.property_staff_access_v3(
  organization_id,property_id,employee_user_id,assignment_type,
  can_write,valid_from,valid_until,granted_by,revoked_at
) values (
  '11111111-1111-4111-8111-111111111111',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '77777777-7777-4777-8777-777777777777',
  'responsible',
  true,
  now(),
  null,
  '22222222-2222-4222-8222-222222222222',
  null
);

do $recurrence_calendar_variants$
declare
  v_base jsonb:=jsonb_build_object(
    'scheduledTimezone','UTC',
    'scheduledAt','2026-01-05T09:30',
    'scheduledAtUtc','2026-01-05T09:30:00Z'
  );
  v_actual timestamptz;
begin
  v_actual:=private.workflow_recurring_occurrence_v1(
    v_base||jsonb_build_object(
      'recurrence','biweekly',
      'customEvery','',
      'customUnit',''
    ),
    2
  );
  if v_actual is distinct from '2026-02-02T09:30:00Z'::timestamptz then
    raise exception 'biweekly recurrence calculation drifted: %',v_actual;
  end if;

  v_actual:=private.workflow_recurring_occurrence_v1(
    v_base||jsonb_build_object(
      'recurrence','custom',
      'customEvery','3',
      'customUnit','week'
    ),
    2
  );
  if v_actual is distinct from '2026-02-16T09:30:00Z'::timestamptz then
    raise exception 'custom weekly recurrence calculation drifted: %',v_actual;
  end if;

  v_actual:=private.workflow_recurring_occurrence_v1(
    v_base||jsonb_build_object(
      'recurrence','custom',
      'customEvery','2',
      'customUnit','month'
    ),
    2
  );
  if v_actual is distinct from '2026-05-05T09:30:00Z'::timestamptz then
    raise exception 'custom monthly recurrence calculation drifted: %',v_actual;
  end if;
end;
$recurrence_calendar_variants$;

do $recurring_responsible_second$
declare
  v_app uuid:=current_setting('gestionpisos.recurring.responsible_app')::uuid;
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
      and trigger_kind='recurring'
      and assigned_user_id='77777777-7777-4777-8777-777777777777'::uuid
  ) then
    raise exception 'second recurring occurrence did not resolve the changed responsible';
  end if;

  if (
    select count(*)
    from public.workflow_executions_v2
    where application_id=v_app
      and trigger_kind='recurring'
  )<>2 then
    raise exception 'responsible recurring flow did not create exactly two executions';
  end if;
end;
$recurring_responsible_second$;

rollback;
