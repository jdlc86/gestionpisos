-- Flujos · regresión de autoría temporal.
-- PostgreSQL desechable. Todo se revierte al finalizar.

begin;

do $sanitize_valid$
declare
  v_spec jsonb;
begin
  v_spec:=private.workflow_sanitize_authoring_spec_v2(
    jsonb_build_object(
      'authoringVersion',2,
      'flowName','Recurrente válido',
      'flowType','custom',
      'flowDescription','',
      'scopeType','property',
      'triggerType','recurring',
      'recurrence','weekly',
      'scheduledAt','2026-10-01T09:30',
      'scheduleTimeZone','Europe/Madrid',
      'customEvery','',
      'customUnit','',
      'assignmentType','property_responsible',
      'steps',jsonb_build_object(
        'accept',true,
        'photo',false,
        'checklist',false,
        'document',false
      ),
      'checklistItems','[]'::jsonb,
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',false,'onClose',false)
    )
  );

  if v_spec->>'scheduledAt'<>'2026-10-01T09:30'
    or v_spec->>'scheduleTimeZone'<>'Europe/Madrid'
    or v_spec->>'triggerType'<>'recurring' then
    raise exception 'temporal sanitizer lost recurring anchor/timezone';
  end if;

  if not public.workflow_authoring_complete_v1(v_spec) then
    raise exception 'valid recurring temporal authoring was not complete';
  end if;
end;
$sanitize_valid$;

do $recurring_missing_anchor$
declare
  v_spec jsonb;
begin
  v_spec:=private.workflow_sanitize_authoring_spec_v2(
    jsonb_build_object(
      'authoringVersion',2,
      'flowName','Recurrente sin inicio',
      'flowType','custom',
      'flowDescription','',
      'scopeType','property',
      'triggerType','recurring',
      'recurrence','weekly',
      'scheduledAt','',
      'scheduleTimeZone','Europe/Madrid',
      'customEvery','',
      'customUnit','',
      'assignmentType','property_responsible',
      'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
      'checklistItems','[]'::jsonb,
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',false,'onClose',false)
    )
  );

  if public.workflow_authoring_complete_v1(v_spec) then
    raise exception 'recurring without first execution was considered complete';
  end if;
end;
$recurring_missing_anchor$;

do $recurring_missing_timezone$
declare
  v_spec jsonb;
begin
  v_spec:=private.workflow_sanitize_authoring_spec_v2(
    jsonb_build_object(
      'authoringVersion',2,
      'flowName','Recurrente sin zona',
      'flowType','custom',
      'flowDescription','',
      'scopeType','property',
      'triggerType','recurring',
      'recurrence','monthly',
      'scheduledAt','2026-10-01T09:30',
      'scheduleTimeZone','',
      'customEvery','',
      'customUnit','',
      'assignmentType','property_responsible',
      'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
      'checklistItems','[]'::jsonb,
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',false,'onClose',false)
    )
  );

  if public.workflow_authoring_complete_v1(v_spec) then
    raise exception 'recurring without timezone was considered complete';
  end if;
end;
$recurring_missing_timezone$;

do $manual_assignment_not_automatic$
declare
  v_spec jsonb;
begin
  v_spec:=private.workflow_sanitize_authoring_spec_v2(
    jsonb_build_object(
      'authoringVersion',2,
      'flowName','Recurrente manual',
      'flowType','custom',
      'flowDescription','',
      'scopeType','property',
      'triggerType','recurring',
      'recurrence','biweekly',
      'scheduledAt','2026-10-01T09:30',
      'scheduleTimeZone','Europe/Madrid',
      'customEvery','',
      'customUnit','',
      'assignmentType','manual',
      'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
      'checklistItems','[]'::jsonb,
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',false,'onClose',false)
    )
  );

  if public.workflow_authoring_complete_v1(v_spec) then
    raise exception 'automatic temporal workflow accepted manual assignment';
  end if;
end;
$manual_assignment_not_automatic$;

do $organization_scope_not_automatic$
declare
  v_spec jsonb;
begin
  v_spec:=private.workflow_sanitize_authoring_spec_v2(
    jsonb_build_object(
      'authoringVersion',2,
      'flowName','Temporal organización',
      'flowType','custom',
      'flowDescription','',
      'scopeType','organization',
      'triggerType','scheduled_once',
      'recurrence','',
      'scheduledAt','2026-10-03T18:00',
      'scheduleTimeZone','Europe/Madrid',
      'customEvery','',
      'customUnit','',
      'assignmentType','property_responsible',
      'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
      'checklistItems','[]'::jsonb,
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',false,'onClose',false)
    )
  );

  if public.workflow_authoring_complete_v1(v_spec) then
    raise exception 'automatic temporal workflow accepted organization scope';
  end if;
end;
$organization_scope_not_automatic$;

do $scheduled_once_valid$
declare
  v_spec jsonb;
begin
  v_spec:=private.workflow_sanitize_authoring_spec_v2(
    jsonb_build_object(
      'authoringVersion',2,
      'flowName','Fecha concreta válida',
      'flowType','custom',
      'flowDescription','',
      'scopeType','room',
      'triggerType','scheduled_once',
      'recurrence','should-clear',
      'scheduledAt','2026-10-03T18:00',
      'scheduleTimeZone','Europe/Madrid',
      'customEvery','3',
      'customUnit','day',
      'assignmentType','property_responsible',
      'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
      'checklistItems','[]'::jsonb,
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',false,'onClose',false)
    )
  );

  if v_spec->>'recurrence'<>'' or v_spec->>'customEvery'<>'' or v_spec->>'customUnit'<>'' then
    raise exception 'scheduled_once retained recurrence-only fields';
  end if;

  if not public.workflow_authoring_complete_v1(v_spec) then
    raise exception 'valid scheduled_once temporal authoring was not complete';
  end if;
end;
$scheduled_once_valid$;

do $invalid_timezone$
begin
  perform private.workflow_sanitize_authoring_spec_v2(
    jsonb_build_object(
      'authoringVersion',2,
      'flowName','Zona inválida',
      'flowType','custom',
      'flowDescription','',
      'scopeType','property',
      'triggerType','scheduled_once',
      'recurrence','',
      'scheduledAt','2026-10-03T18:00',
      'scheduleTimeZone','Europe/NoExiste-Allaiso',
      'customEvery','',
      'customUnit','',
      'assignmentType','property_responsible',
      'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
      'checklistItems','[]'::jsonb,
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',false,'onClose',false)
    )
  );
  raise exception 'invalid timezone was accepted';
exception
  when sqlstate '22023' then
    if sqlerrm<>'workflow_schedule_timezone_invalid' then
      raise;
    end if;
end;
$invalid_timezone$;

do $non_temporal_clears_schedule$
declare
  v_spec jsonb;
begin
  v_spec:=private.workflow_sanitize_authoring_spec_v2(
    jsonb_build_object(
      'authoringVersion',2,
      'flowName','Manual limpio',
      'flowType','custom',
      'flowDescription','',
      'scopeType','organization',
      'triggerType','manual',
      'recurrence','weekly',
      'scheduledAt','2026-10-03T18:00',
      'scheduleTimeZone','Europe/Madrid',
      'customEvery','2',
      'customUnit','week',
      'assignmentType','manual',
      'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
      'checklistItems','[]'::jsonb,
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',false,'onClose',false)
    )
  );

  if v_spec->>'scheduledAt'<>'' or v_spec->>'scheduleTimeZone'<>'' or v_spec->>'recurrence'<>'' then
    raise exception 'manual workflow retained temporal fields';
  end if;
end;
$non_temporal_clears_schedule$;

rollback;
