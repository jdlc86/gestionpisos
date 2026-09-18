-- Flujos de Trabajo · regresión R3 de persistencia de borradores.
-- Se ejecuta únicamente contra PostgreSQL desechable y revierte todo.

begin;

-- Los RPC administrativos no se exponen al rol API anónimo.
do $$
begin
  if has_function_privilege('anon','public.save_workflow_definition_draft_v1(jsonb,uuid,bigint)','EXECUTE') then
    raise exception 'anon can execute workflow draft RPC';
  end if;
  if has_function_privilege('anon','public.workflow_can_read_definitions_v1(uuid)','EXECUTE') then
    raise exception 'anon can execute workflow read helper';
  end if;
  if not has_function_privilege('authenticated','public.save_workflow_definition_draft_v1(jsonb,uuid,bigint)','EXECUTE') then
    raise exception 'authenticated cannot execute workflow draft RPC';
  end if;
end;
$$;

select set_config('gestionpisos.workflow_org_1','11111111-1111-4111-8111-111111111111',true);
select set_config('gestionpisos.workflow_org_2','33333333-3333-4333-8333-333333333333',true);
select set_config('gestionpisos.workflow_root','22222222-2222-4222-8222-222222222222',true);
select set_config('gestionpisos.workflow_admin_1','44444444-4444-4444-8444-444444444444',true);
select set_config('gestionpisos.workflow_admin_2','55555555-5555-4555-8555-555555555555',true);
select set_config('gestionpisos.workflow_tenant','66666666-6666-4666-8666-666666666666',true);

insert into public.organizations(id,name)
values (current_setting('gestionpisos.workflow_org_2')::uuid,'Otra organización');

insert into auth.users(id) values
  (current_setting('gestionpisos.workflow_admin_1')::uuid),
  (current_setting('gestionpisos.workflow_admin_2')::uuid),
  (current_setting('gestionpisos.workflow_tenant')::uuid);

insert into public.user_roles(user_id,organization_id,role) values
  (current_setting('gestionpisos.workflow_admin_1')::uuid,current_setting('gestionpisos.workflow_org_1')::uuid,'admin'),
  (current_setting('gestionpisos.workflow_admin_2')::uuid,current_setting('gestionpisos.workflow_org_2')::uuid,'admin'),
  (current_setting('gestionpisos.workflow_tenant')::uuid,current_setting('gestionpisos.workflow_org_1')::uuid,'tenant');

set local role authenticated;

-- ROOT puede crear un borrador; la organización se resuelve server-side desde su rol.
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub',current_setting('gestionpisos.workflow_root'),'role','authenticated')::text,
  true
);

select set_config(
  'gestionpisos.workflow_definition_id',
  (select definition_id::text from public.save_workflow_definition_draft_v1(
    jsonb_build_object(
      'flowName','Limpieza semanal Piso A',
      'flowType','cleaning',
      'flowDescription','Regresión de flujo',
      'scopeType','property',
      'triggerType','manual',
      'recurrence','',
      'assignmentType','property_responsible',
      'steps',jsonb_build_object('accept',true,'photo',true,'checklist',false,'document',false),
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',true,'onClose',false)
    )
  ) limit 1),
  true
);

do $$
declare c integer;
begin
  select count(*) into c
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.workflow_definition_id')::uuid;
  if c<>1 then raise exception 'ROOT cannot read created workflow draft'; end if;
end;
$$;

-- Los clientes no escriben directamente, ni siquiera ROOT/ADMIN.
do $$
begin
  begin
    insert into public.workflow_definitions_v2(
      organization_id,name,flow_type,scope_type,trigger_type,assignment_type,close_type,draft_spec,created_by,updated_by
    ) values (
      current_setting('gestionpisos.workflow_org_1')::uuid,'Directo prohibido','custom','organization','manual','manual','auto','{}'::jsonb,
      current_setting('gestionpisos.workflow_root')::uuid,current_setting('gestionpisos.workflow_root')::uuid
    );
    raise exception 'direct workflow insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Optimistic concurrency: una revisión válida avanza y la revisión antigua se rechaza.
select * from public.save_workflow_definition_draft_v1(
  jsonb_build_object(
    'flowName','Limpieza semanal Piso A editada',
    'flowType','cleaning','flowDescription','Regresión de flujo','scopeType','property','triggerType','manual','recurrence','',
    'assignmentType','property_responsible','steps',jsonb_build_object('accept',true,'photo',true,'checklist',false,'document',false),
    'closeType','auto','notifications',jsonb_build_object('onCreate',true,'onClose',false)
  ),
  current_setting('gestionpisos.workflow_definition_id')::uuid,
  1
);

do $$
begin
  begin
    perform * from public.save_workflow_definition_draft_v1(
      jsonb_build_object(
        'flowName','Edición obsoleta','flowType','custom','flowDescription','','scopeType','organization','triggerType','manual','recurrence','',
        'assignmentType','manual','steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'closeType','auto','notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      current_setting('gestionpisos.workflow_definition_id')::uuid,
      1
    );
    raise exception 'stale workflow revision unexpectedly succeeded';
  exception when serialization_failure then null;
  end;
end;
$$;

-- ADMIN de la misma organización puede guardar borradores mediante RPC.
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub',current_setting('gestionpisos.workflow_admin_1'),'role','authenticated')::text,
  true
);

select * from public.save_workflow_definition_draft_v1(
  jsonb_build_object(
    'flowName','Inspección mensual','flowType','inspection','flowDescription','','scopeType','organization','triggerType','recurring','recurrence','monthly',
    'assignmentType','manual','steps',jsonb_build_object('accept',true,'photo',false,'checklist',true,'document',false),
    'closeType','human_review','notifications',jsonb_build_object('onCreate',true,'onClose',true)
  )
);

-- TENANT no puede crear borradores administrativos.
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub',current_setting('gestionpisos.workflow_tenant'),'role','authenticated')::text,
  true
);

do $$
begin
  begin
    perform * from public.save_workflow_definition_draft_v1(
      jsonb_build_object(
        'flowName','Intento tenant','flowType','custom','flowDescription','','scopeType','organization','triggerType','manual','recurrence','',
        'assignmentType','manual','steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
        'closeType','auto','notifications',jsonb_build_object('onCreate',false,'onClose',false)
      )
    );
    raise exception 'tenant workflow authoring unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- ADMIN de otra organización no puede leer borradores de la primera.
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub',current_setting('gestionpisos.workflow_admin_2'),'role','authenticated')::text,
  true
);

do $$
declare c integer;
begin
  select count(*) into c
  from public.workflow_definitions_v2
  where organization_id=current_setting('gestionpisos.workflow_org_1')::uuid;
  if c<>0 then raise exception 'cross-organization workflow read unexpectedly succeeded'; end if;
end;
$$;

-- La tabla de versiones ya existe pero no admite publicación directa desde cliente.
do $$
begin
  begin
    insert into public.workflow_definition_versions_v2(definition_id,organization_id,version,spec,published_by)
    values (
      current_setting('gestionpisos.workflow_definition_id')::uuid,
      current_setting('gestionpisos.workflow_org_1')::uuid,
      1,
      '{}'::jsonb,
      current_setting('gestionpisos.workflow_admin_2')::uuid
    );
    raise exception 'direct workflow version insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Los borradores parciales son válidos: solo el nombre es obligatorio para persistir.
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub',current_setting('gestionpisos.workflow_admin_1'),'role','authenticated')::text,
  true
);

select set_config(
  'gestionpisos.workflow_partial_id',
  (select definition_id::text
   from public.save_workflow_definition_draft_v1(
     jsonb_build_object(
       'authoringVersion',2,
       'flowName','Borrador parcial'
     )
   )
   limit 1),
  true
);

do $$
declare
  v_complete boolean;
  v_flow_type text;
  v_scope_type text;
begin
  select authoring_complete, flow_type, scope_type
  into v_complete, v_flow_type, v_scope_type
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.workflow_partial_id')::uuid;

  if v_complete then
    raise exception 'partial workflow unexpectedly marked complete';
  end if;
  if v_flow_type is not null or v_scope_type is not null then
    raise exception 'partial workflow received implicit business defaults';
  end if;
end;
$$;

-- Al completar explícitamente todos los apartados, el servidor marca la autoría como completa.
select * from public.save_workflow_definition_draft_v1(
  jsonb_build_object(
    'authoringVersion',2,
    'flowName','Borrador parcial',
    'flowType','inspection',
    'flowDescription','',
    'scopeType','organization',
    'triggerType','manual',
    'recurrence','',
    'assignmentType','manual',
    'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
    'closeType','auto',
    'notifications',jsonb_build_object('onCreate',false,'onClose',false)
  ),
  current_setting('gestionpisos.workflow_partial_id')::uuid,
  1
);

do $$
declare v_complete boolean;
begin
  select authoring_complete into v_complete
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.workflow_partial_id')::uuid;
  if not v_complete then
    raise exception 'explicitly configured workflow not marked complete';
  end if;
end;
$$;

-- Guardar exactamente la misma especificacion no fabrica una revision nueva.
do $$
declare
  v_before_revision bigint;
  v_after_revision bigint;
  v_before_updated_at timestamptz;
  v_after_updated_at timestamptz;
  v_before_audit integer;
  v_after_audit integer;
begin
  select revision, updated_at
  into v_before_revision, v_before_updated_at
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.workflow_partial_id')::uuid;

  select count(*)
  into v_before_audit
  from public.audit_log_v2
  where entity_type='workflow_definition'
    and entity_id=current_setting('gestionpisos.workflow_partial_id')
    and action='workflow_draft_updated';

  perform *
  from public.save_workflow_definition_draft_v1(
    jsonb_build_object(
      'authoringVersion',2,
      'flowName','Borrador parcial',
      'flowType','inspection',
      'flowDescription','',
      'scopeType','organization',
      'triggerType','manual',
      'recurrence','',
      'assignmentType','manual',
      'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
      'closeType','auto',
      'notifications',jsonb_build_object('onCreate',false,'onClose',false)
    ),
    current_setting('gestionpisos.workflow_partial_id')::uuid,
    v_before_revision
  );

  select revision, updated_at
  into v_after_revision, v_after_updated_at
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.workflow_partial_id')::uuid;

  select count(*)
  into v_after_audit
  from public.audit_log_v2
  where entity_type='workflow_definition'
    and entity_id=current_setting('gestionpisos.workflow_partial_id')
    and action='workflow_draft_updated';

  if v_after_revision <> v_before_revision then
    raise exception 'no-op workflow save incremented revision';
  end if;
  if v_after_updated_at is distinct from v_before_updated_at then
    raise exception 'no-op workflow save changed updated_at';
  end if;
  if v_after_audit <> v_before_audit then
    raise exception 'no-op workflow save created update audit event';
  end if;
end;
$$;

-- Un borrador creado por un cliente antiguo no se considera completo aunque sus defaults parezcan válidos.
select set_config(
  'gestionpisos.workflow_legacy_id',
  (select definition_id::text
   from public.save_workflow_definition_draft_v1(
     jsonb_build_object(
       'flowName','Borrador legacy',
       'flowType','cleaning',
       'flowDescription','',
       'scopeType','property',
       'triggerType','manual',
       'recurrence','',
       'assignmentType','property_responsible',
       'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
       'closeType','auto',
       'notifications',jsonb_build_object('onCreate',true,'onClose',false)
     )
   )
   limit 1),
  true
);

do $$
declare
  v_complete boolean;
  v_flow_type text;
  v_scope_type text;
begin
  select authoring_complete, flow_type, scope_type
  into v_complete, v_flow_type, v_scope_type
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.workflow_legacy_id')::uuid;

  if v_complete then
    raise exception 'legacy implicit-default workflow unexpectedly marked complete';
  end if;
  if v_flow_type is not null or v_scope_type is not null then
    raise exception 'legacy implicit defaults leaked into workflow metadata';
  end if;
end;
$$;

reset role;
rollback;
