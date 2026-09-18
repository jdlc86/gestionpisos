-- Flujos de Trabajo · separación Creador / Mis Flujos y versionado seguro.
-- PostgreSQL desechable. Demuestra que una v2 en autoría no altera v1 ni sus aplicaciones.

begin;

do $privileges$
begin
  if has_function_privilege('anon','public.start_workflow_definition_revision_v1(uuid)','EXECUTE') then
    raise exception 'anon can start workflow revision draft';
  end if;
  if has_function_privilege('anon','public.save_workflow_definition_revision_draft_v1(uuid,jsonb,bigint)','EXECUTE') then
    raise exception 'anon can save workflow revision draft';
  end if;
  if has_function_privilege('anon','public.publish_workflow_definition_revision_v1(uuid,bigint)','EXECUTE') then
    raise exception 'anon can publish workflow revision';
  end if;
  if not has_function_privilege('authenticated','public.start_workflow_definition_revision_v1(uuid)','EXECUTE')
    or not has_function_privilege('authenticated','public.save_workflow_definition_revision_draft_v1(uuid,jsonb,bigint)','EXECUTE')
    or not has_function_privilege('authenticated','public.publish_workflow_definition_revision_v1(uuid,bigint)','EXECUTE') then
    raise exception 'authenticated missing workflow revision authoring RPC';
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
  'gestionpisos.authoring_definition',
  (
    select definition_id::text
    from public.save_workflow_definition_draft_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Flujo autoría v1',
        'flowType','inspection',
        'flowDescription','Versión inicial',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      )
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.authoring_v1',
  (
    select version_id::text
    from public.publish_workflow_definition_v1(
      current_setting('gestionpisos.authoring_definition')::uuid,
      1
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.authoring_application',
  (
    select application_id::text
    from public.create_workflow_application_v1(
      current_setting('gestionpisos.authoring_v1')::uuid
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.authoring_draft_revision',
  (
    select revision::text
    from public.start_workflow_definition_revision_v1(
      current_setting('gestionpisos.authoring_definition')::uuid
    )
    limit 1
  ),
  true
);

do $start_is_idempotent$
declare
  v_created_new boolean;
  v_drafts integer;
begin
  select created_new into v_created_new
  from public.start_workflow_definition_revision_v1(
    current_setting('gestionpisos.authoring_definition')::uuid
  )
  limit 1;

  select count(*) into v_drafts
  from public.workflow_definition_revision_drafts_v2
  where definition_id=current_setting('gestionpisos.authoring_definition')::uuid;

  if v_created_new or v_drafts<>1 then
    raise exception 'starting the same version draft is not idempotent';
  end if;
end;
$start_is_idempotent$;

select set_config(
  'gestionpisos.authoring_draft_revision',
  (
    select revision::text
    from public.save_workflow_definition_revision_draft_v1(
      current_setting('gestionpisos.authoring_definition')::uuid,
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Flujo autoría v2',
        'flowType','inspection',
        'flowDescription','Segunda versión en autoría',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'closeType','human_review',
        'notifications',jsonb_build_object('onCreate',false,'onClose',true)
      ),
      current_setting('gestionpisos.authoring_draft_revision')::bigint
    )
    limit 1
  ),
  true
);

do $draft_isolated_from_operation$
declare
  v_versions integer;
  v_application_version uuid;
  v_v1_name text;
  v_canonical_name text;
  v_draft_name text;
begin
  select count(*) into v_versions
  from public.workflow_definition_versions_v2
  where definition_id=current_setting('gestionpisos.authoring_definition')::uuid;

  select definition_version_id into v_application_version
  from public.workflow_applications_v2
  where id=current_setting('gestionpisos.authoring_application')::uuid;

  select spec->>'flowName' into v_v1_name
  from public.workflow_definition_versions_v2
  where id=current_setting('gestionpisos.authoring_v1')::uuid;

  select name into v_canonical_name
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.authoring_definition')::uuid;

  select draft_spec->>'flowName' into v_draft_name
  from public.workflow_definition_revision_drafts_v2
  where definition_id=current_setting('gestionpisos.authoring_definition')::uuid;

  if v_versions<>1 then
    raise exception 'editing v2 draft changed published version count';
  end if;
  if v_application_version<>current_setting('gestionpisos.authoring_v1')::uuid then
    raise exception 'editing v2 draft moved existing v1 application';
  end if;
  if v_v1_name<>'Flujo autoría v1' or v_canonical_name<>'Flujo autoría v1' then
    raise exception 'v2 draft leaked into published v1 metadata';
  end if;
  if v_draft_name<>'Flujo autoría v2' then
    raise exception 'v2 draft content was not saved';
  end if;
end;
$draft_isolated_from_operation$;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','22222222-2222-4222-8222-222222222222',
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

do $publish_requires_aal2$
begin
  begin
    perform * from public.publish_workflow_definition_revision_v1(
      current_setting('gestionpisos.authoring_definition')::uuid,
      current_setting('gestionpisos.authoring_draft_revision')::bigint
    );
    raise exception 'v2 publication without aal2 unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$publish_requires_aal2$;

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
  'gestionpisos.authoring_v2',
  (
    select version_id::text
    from public.publish_workflow_definition_revision_v1(
      current_setting('gestionpisos.authoring_definition')::uuid,
      current_setting('gestionpisos.authoring_draft_revision')::bigint
    )
    limit 1
  ),
  true
);

do $published_v2_preserves_v1_application$
declare
  v_versions integer;
  v_max_version integer;
  v_v1_name text;
  v_v2_name text;
  v_application_version uuid;
  v_drafts integer;
  v_canonical_name text;
begin
  select count(*),max(version)
  into v_versions,v_max_version
  from public.workflow_definition_versions_v2
  where definition_id=current_setting('gestionpisos.authoring_definition')::uuid;

  select spec->>'flowName' into v_v1_name
  from public.workflow_definition_versions_v2
  where id=current_setting('gestionpisos.authoring_v1')::uuid;

  select spec->>'flowName' into v_v2_name
  from public.workflow_definition_versions_v2
  where id=current_setting('gestionpisos.authoring_v2')::uuid;

  select definition_version_id into v_application_version
  from public.workflow_applications_v2
  where id=current_setting('gestionpisos.authoring_application')::uuid;

  select count(*) into v_drafts
  from public.workflow_definition_revision_drafts_v2
  where definition_id=current_setting('gestionpisos.authoring_definition')::uuid
    and published_at is null;

  select name into v_canonical_name
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.authoring_definition')::uuid;

  if v_versions<>2 or v_max_version<>2 then
    raise exception 'publishing v2 did not append exactly one immutable version';
  end if;
  if v_v1_name<>'Flujo autoría v1' or v_v2_name<>'Flujo autoría v2' then
    raise exception 'published version history was rewritten';
  end if;
  if v_application_version<>current_setting('gestionpisos.authoring_v1')::uuid then
    raise exception 'publishing v2 silently migrated existing v1 application';
  end if;
  if v_drafts<>0 then
    raise exception 'published v2 still appears as active authoring draft';
  end if;
  if not exists(
    select 1
    from public.workflow_definition_revision_drafts_v2
    where definition_id=current_setting('gestionpisos.authoring_definition')::uuid
      and published_version_id=current_setting('gestionpisos.authoring_v2')::uuid
      and published_at is not null
  ) then
    raise exception 'published v2 receipt is missing';
  end if;
  if v_canonical_name<>'Flujo autoría v2' then
    raise exception 'definition metadata was not advanced to published v2';
  end if;
end;
$published_v2_preserves_v1_application$;

do $workflow_revision_publish_retry$
declare
  v_version_id uuid;
  v_version integer;
  v_versions integer;
begin
  select version_id,version
  into v_version_id,v_version
  from public.publish_workflow_definition_revision_v1(
    current_setting('gestionpisos.authoring_definition')::uuid,
    current_setting('gestionpisos.authoring_draft_revision')::bigint
  )
  limit 1;

  select count(*) into v_versions
  from public.workflow_definition_versions_v2
  where definition_id=current_setting('gestionpisos.authoring_definition')::uuid;

  if v_version_id<>current_setting('gestionpisos.authoring_v2')::uuid
    or v_version<>2
    or v_versions<>2 then
    raise exception 'workflow revision publication retry was not idempotent';
  end if;
end;
$workflow_revision_publish_retry$;

do $audit_exists$
declare
  v_started integer;
  v_updated integer;
  v_published integer;
begin
  select count(*) filter(where action='workflow_revision_draft_started'),
         count(*) filter(where action='workflow_revision_draft_updated'),
         count(*) filter(where action='workflow_definition_revision_published')
  into v_started,v_updated,v_published
  from public.audit_log_v2
  where entity_type='workflow_definition'
    and entity_id=current_setting('gestionpisos.authoring_definition');

  if v_started<>1 or v_updated<>1 or v_published<>1 then
    raise exception 'workflow revision authoring audit trail is incomplete';
  end if;
end;
$audit_exists$;

rollback;
