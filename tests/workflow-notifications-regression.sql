-- Flujos · regresión de notificaciones operativas.
-- PostgreSQL desechable. Todo se revierte al finalizar.

begin;

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

-- onCreate + onClose: crear avisa solo al asignado; completar avisa creador + asignado.
select set_config(
  'gestionpisos.notify.execution',
  (
    select execution_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Notificación completa',
        'flowType','custom',
        'flowDescription','Regresión de notificaciones',
        'scopeType','organization',
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
        'notifications',jsonb_build_object(
          'onCreate',true,
          'onClose',true
        )
      ),
      null,null,null,'{}'::uuid[],true,
      'regression-workflow-notify-complete',
      'regression-workflow-notify-complete-execution',
      '33333333-3333-4333-8333-333333333333'::uuid
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.notify.task',
  (
    select id::text
    from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('gestionpisos.notify.execution')::uuid
  ),
  true
);

reset role;

do $create_notification$
declare
  v_execution uuid:=current_setting('gestionpisos.notify.execution')::uuid;
begin
  if (
    select count(*)
    from public.notifications_v2
    where source_kind='workflow_execution'
      and source_id=v_execution
      and event_key='created'
      and event_type='workflow_task_created'
      and recipient_user_id='33333333-3333-4333-8333-333333333333'::uuid
      and status='pending'
      and channel_in_app=true
      and channel_email=false
  )<>1 then
    raise exception 'workflow onCreate notification contract failed';
  end if;

  if exists(
    select 1
    from public.notifications_v2
    where source_kind='workflow_execution'
      and source_id=v_execution
      and event_key='created'
      and recipient_user_id<>'33333333-3333-4333-8333-333333333333'::uuid
  ) then
    raise exception 'workflow onCreate notified someone other than the assignee';
  end if;
end;
$create_notification$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','33333333-3333-4333-8333-333333333333',
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

select *
from public.apply_workflow_task_action_v1(
  current_setting('gestionpisos.notify.task')::uuid,
  'accept',
  null,
  'regression-workflow-notify-accept'
);

reset role;

do $completed_notifications$
declare
  v_execution uuid:=current_setting('gestionpisos.notify.execution')::uuid;
begin
  if (
    select count(*)
    from public.notifications_v2
    where source_kind='workflow_execution'
      and source_id=v_execution
      and event_key='completed'
      and event_type='workflow_completed'
  )<>2 then
    raise exception 'workflow onClose completed must notify creator and assignee exactly once';
  end if;

  if (
    select count(distinct recipient_user_id)
    from public.notifications_v2
    where source_kind='workflow_execution'
      and source_id=v_execution
      and event_key='completed'
  )<>2 then
    raise exception 'workflow completed recipient dedupe failed';
  end if;

  if exists(
    select 1
    from public.notifications_v2
    where source_kind='workflow_execution'
      and source_id=v_execution
      and channel_email=true
  ) then
    raise exception 'workflow notification enabled email without authoring support';
  end if;
end;
$completed_notifications$;

-- Reintento idempotente de la misma acción: no duplica cierre.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','33333333-3333-4333-8333-333333333333',
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

select *
from public.apply_workflow_task_action_v1(
  current_setting('gestionpisos.notify.task')::uuid,
  'accept',
  null,
  'regression-workflow-notify-accept'
);

reset role;

do $completed_retry$
begin
  if (
    select count(*)
    from public.notifications_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('gestionpisos.notify.execution')::uuid
      and event_key='completed'
  )<>2 then
    raise exception 'workflow completed retry duplicated notifications';
  end if;
end;
$completed_retry$;

-- Rechazo: onClose avisa creador + asignado y usa event_type específico.
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
  'gestionpisos.reject.execution',
  (
    select execution_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Notificación rechazo',
        'flowType','custom',
        'flowDescription','Regresión rechazo',
        'scopeType','organization',
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
        'notifications',jsonb_build_object(
          'onCreate',false,
          'onClose',true
        )
      ),
      null,null,null,'{}'::uuid[],true,
      'regression-workflow-notify-reject',
      'regression-workflow-notify-reject-execution',
      '33333333-3333-4333-8333-333333333333'::uuid
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.reject.task',
  (
    select id::text
    from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('gestionpisos.reject.execution')::uuid
  ),
  true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','33333333-3333-4333-8333-333333333333',
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

select *
from public.apply_workflow_task_action_v1(
  current_setting('gestionpisos.reject.task')::uuid,
  'reject',
  'No se puede realizar',
  'regression-workflow-notify-reject-action'
);

reset role;

do $rejected_notifications$
declare
  v_execution uuid:=current_setting('gestionpisos.reject.execution')::uuid;
begin
  if exists(
    select 1 from public.notifications_v2
    where source_kind='workflow_execution'
      and source_id=v_execution
      and event_key='created'
  ) then
    raise exception 'workflow onCreate=false emitted a notification';
  end if;

  if (
    select count(*)
    from public.notifications_v2
    where source_kind='workflow_execution'
      and source_id=v_execution
      and event_key='rejected'
      and event_type='workflow_rejected'
  )<>2 then
    raise exception 'workflow rejected must notify creator and assignee exactly once';
  end if;
end;
$rejected_notifications$;

-- Ambos flags desactivados: no se emite nada.
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
  'gestionpisos.silent.execution',
  (
    select execution_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Flujo silencioso',
        'flowType','custom',
        'flowDescription','Sin notificaciones',
        'scopeType','organization',
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
        'notifications',jsonb_build_object(
          'onCreate',false,
          'onClose',false
        )
      ),
      null,null,null,'{}'::uuid[],true,
      'regression-workflow-notify-silent',
      'regression-workflow-notify-silent-execution',
      '33333333-3333-4333-8333-333333333333'::uuid
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.silent.task',
  (
    select id::text
    from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('gestionpisos.silent.execution')::uuid
  ),
  true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','33333333-3333-4333-8333-333333333333',
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

select *
from public.apply_workflow_task_action_v1(
  current_setting('gestionpisos.silent.task')::uuid,
  'accept',
  null,
  'regression-workflow-notify-silent-action'
);

reset role;

do $silent_notifications$
begin
  if exists(
    select 1
    from public.notifications_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('gestionpisos.silent.execution')::uuid
  ) then
    raise exception 'disabled workflow notifications emitted rows';
  end if;
end;
$silent_notifications$;

rollback;
