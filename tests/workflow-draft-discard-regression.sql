-- Flujos · regresión del descarte seguro de borradores.
-- PostgreSQL desechable; todo se revierte al finalizar.

begin;

do $privileges$
begin
  if has_function_privilege('anon','public.discard_workflow_definition_draft_v1(uuid,bigint)','EXECUTE') then
    raise exception 'anon can discard initial workflow draft';
  end if;
  if has_function_privilege('anon','public.discard_workflow_definition_revision_draft_v1(uuid,bigint)','EXECUTE') then
    raise exception 'anon can discard workflow revision draft';
  end if;
  if not has_function_privilege('authenticated','public.discard_workflow_definition_draft_v1(uuid,bigint)','EXECUTE') then
    raise exception 'authenticated cannot invoke initial draft discard RPC';
  end if;
  if not has_function_privilege('authenticated','public.discard_workflow_definition_revision_draft_v1(uuid,bigint)','EXECUTE') then
    raise exception 'authenticated cannot invoke revision draft discard RPC';
  end if;
end;
$privileges$;

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
  'gestionpisos.discard_initial_id',
  (
    select definition_id::text
    from public.save_workflow_definition_draft_v2(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Borrador eliminable',
        'flowType','custom',
        'flowDescription','Regresión descarte',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      )
    )
    limit 1
  ),
  true
);

do $discard_initial$
declare
  v_revision bigint;
begin
  select revision into v_revision
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.discard_initial_id')::uuid;

  perform *
  from public.discard_workflow_definition_draft_v1(
    current_setting('gestionpisos.discard_initial_id')::uuid,
    v_revision
  );

  if exists(
    select 1 from public.workflow_definitions_v2
    where id=current_setting('gestionpisos.discard_initial_id')::uuid
  ) then
    raise exception 'initial workflow draft was not deleted';
  end if;

  if not exists(
    select 1 from public.audit_log_v2
    where action='workflow_definition_draft_discarded'
      and entity_id=current_setting('gestionpisos.discard_initial_id')
  ) then
    raise exception 'initial workflow draft discard was not audited';
  end if;
end;
$discard_initial$;

select set_config(
  'gestionpisos.discard_published_id',
  (
    select definition_id::text
    from public.save_workflow_definition_draft_v2(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Publicado con revisión descartable',
        'flowType','custom',
        'flowDescription','Regresión descarte de nueva versión',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      )
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.discard_published_version_id',
  (
    select version_id::text
    from public.publish_workflow_definition_v1(
      current_setting('gestionpisos.discard_published_id')::uuid,
      1
    )
    limit 1
  ),
  true
);

select *
from public.start_workflow_definition_revision_v1(
  current_setting('gestionpisos.discard_published_id')::uuid
);

do $discard_revision$
declare
  v_revision bigint;
  v_base_version integer;
begin
  select revision,base_version
  into v_revision,v_base_version
  from public.workflow_definition_revision_drafts_v2
  where definition_id=current_setting('gestionpisos.discard_published_id')::uuid
    and published_at is null;

  perform *
  from public.discard_workflow_definition_revision_draft_v1(
    current_setting('gestionpisos.discard_published_id')::uuid,
    v_revision
  );

  if exists(
    select 1
    from public.workflow_definition_revision_drafts_v2
    where definition_id=current_setting('gestionpisos.discard_published_id')::uuid
      and published_at is null
  ) then
    raise exception 'workflow revision draft was not deleted';
  end if;

  if not exists(
    select 1
    from public.workflow_definitions_v2
    where id=current_setting('gestionpisos.discard_published_id')::uuid
      and status='published'
  ) then
    raise exception 'published definition was damaged while discarding revision draft';
  end if;

  if not exists(
    select 1
    from public.workflow_definition_versions_v2
    where id=current_setting('gestionpisos.discard_published_version_id')::uuid
      and definition_id=current_setting('gestionpisos.discard_published_id')::uuid
      and version=v_base_version
  ) then
    raise exception 'published version was damaged while discarding revision draft';
  end if;

  if not exists(
    select 1 from public.audit_log_v2
    where action='workflow_definition_revision_draft_discarded'
      and entity_id=current_setting('gestionpisos.discard_published_id')
  ) then
    raise exception 'revision draft discard was not audited';
  end if;
end;
$discard_revision$;

-- Un borrado con revisión obsoleta no puede destruir cambios nuevos.
select set_config(
  'gestionpisos.discard_conflict_id',
  (
    select definition_id::text
    from public.save_workflow_definition_draft_v2(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Borrador con conflicto',
        'flowType','custom',
        'flowDescription','',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      )
    )
    limit 1
  ),
  true
);

select *
from public.save_workflow_definition_draft_v2(
  jsonb_build_object(
    'authoringVersion',2,
    'flowName','Borrador con conflicto actualizado',
    'flowType','custom',
    'flowDescription','',
    'scopeType','organization',
    'triggerType','manual',
    'recurrence','',
    'scheduledAt','',
    'customEvery','',
    'customUnit','',
    'assignmentType','manual',
    'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
    'checklistItems','[]'::jsonb,
    'closeType','auto',
    'notifications',jsonb_build_object('onCreate',false,'onClose',false)
  ),
  current_setting('gestionpisos.discard_conflict_id')::uuid,
  1
);

do $stale_delete$
begin
  begin
    perform *
    from public.discard_workflow_definition_draft_v1(
      current_setting('gestionpisos.discard_conflict_id')::uuid,
      1
    );
    raise exception 'stale draft discard unexpectedly succeeded';
  exception when serialization_failure then
    null;
  end;

  if not exists(
    select 1 from public.workflow_definitions_v2
    where id=current_setting('gestionpisos.discard_conflict_id')::uuid
      and revision=2
  ) then
    raise exception 'stale discard damaged newer workflow draft';
  end if;
end;
$stale_delete$;

rollback;
