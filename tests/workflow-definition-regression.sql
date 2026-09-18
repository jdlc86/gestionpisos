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
  if has_function_privilege('anon','public.publish_workflow_definition_v1(uuid,bigint)','EXECUTE') then
    raise exception 'anon can execute workflow publish RPC';
  end if;
  if has_function_privilege('anon','public.create_workflow_application_v1(uuid,uuid,uuid,uuid)','EXECUTE') then
    raise exception 'anon can execute workflow application RPC';
  end if;
  if has_function_privilege('anon','public.archive_workflow_application_v1(uuid)','EXECUTE') then
    raise exception 'anon can execute workflow archive RPC';
  end if;
  if not has_function_privilege('authenticated','public.publish_workflow_definition_v1(uuid,bigint)','EXECUTE') then
    raise exception 'authenticated cannot execute workflow publish RPC';
  end if;
  if has_function_privilege('anon','public.execute_workflow_application_now_v1(uuid,text,uuid)','EXECUTE') then
    raise exception 'anon can execute workflow execution RPC';
  end if;
  if not has_function_privilege('authenticated','public.execute_workflow_application_now_v1(uuid,text,uuid)','EXECUTE') then
    raise exception 'authenticated cannot execute workflow execution RPC';
  end if;
  if has_function_privilege('anon','public.materialize_workflow_execution_task_v1(uuid)','EXECUTE') then
    raise exception 'anon can execute workflow task materialization RPC';
  end if;
  if not has_function_privilege('authenticated','public.materialize_workflow_execution_task_v1(uuid)','EXECUTE') then
    raise exception 'authenticated cannot execute workflow task materialization RPC';
  end if;
  if has_function_privilege('anon','public.apply_workflow_task_action_v1(uuid,text,text,text)','EXECUTE') then
    raise exception 'anon can execute workflow task action RPC';
  end if;
  if not has_function_privilege('authenticated','public.apply_workflow_task_action_v1(uuid,text,text,text)','EXECUTE') then
    raise exception 'authenticated cannot execute workflow task action RPC';
  end if;
  if has_function_privilege('authenticated','public.workflow_seed_task_actions_internal_v1(uuid)','EXECUTE') then
    raise exception 'authenticated can execute internal workflow action seed helper';
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
reset role;
select set_config(
  'gestionpisos.workflow_partial_audit_before',
  (
    select count(*)::text
    from public.audit_log_v2
    where entity_type='workflow_definition'
      and entity_id=current_setting('gestionpisos.workflow_partial_id')
      and action='workflow_draft_updated'
  ),
  true
);
set local role authenticated;

do $$
declare
  v_before_revision bigint;
  v_after_revision bigint;
  v_before_updated_at timestamptz;
  v_after_updated_at timestamptz;
begin
  select revision, updated_at
  into v_before_revision, v_before_updated_at
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.workflow_partial_id')::uuid;

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

  if v_after_revision <> v_before_revision then
    raise exception 'no-op workflow save incremented revision';
  end if;
  if v_after_updated_at is distinct from v_before_updated_at then
    raise exception 'no-op workflow save changed updated_at';
  end if;
end;
$$;

reset role;
do $$
declare v_after_audit integer;
begin
  select count(*)
  into v_after_audit
  from public.audit_log_v2
  where entity_type='workflow_definition'
    and entity_id=current_setting('gestionpisos.workflow_partial_id')
    and action='workflow_draft_updated';

  if v_after_audit <> current_setting('gestionpisos.workflow_partial_audit_before')::integer then
    raise exception 'no-op workflow save created update audit event';
  end if;
end;
$$;
set local role authenticated;

-- Activacion condicional: fecha concreta conserva calendario/hora y no frecuencia.
select set_config(
  'gestionpisos.workflow_scheduled_id',
  (select definition_id::text
   from public.save_workflow_definition_draft_v1(
     jsonb_build_object(
       'authoringVersion',2,
       'flowName','Inspeccion puntual',
       'flowType','inspection',
       'flowDescription','',
       'scopeType','organization',
       'triggerType','scheduled_once',
       'recurrence','weekly',
       'scheduledAt','2026-10-20T10:30',
       'customEvery','9',
       'customUnit','day',
       'assignmentType','manual',
       'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
       'closeType','auto',
       'notifications',jsonb_build_object('onCreate',false,'onClose',false)
     )
   )
   limit 1),
  true
);

do $$
declare
  v_spec jsonb;
  v_complete boolean;
begin
  select draft_spec, authoring_complete
  into v_spec, v_complete
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.workflow_scheduled_id')::uuid;

  if not v_complete then
    raise exception 'scheduled workflow not marked complete';
  end if;
  if v_spec ->> 'scheduledAt' <> '2026-10-20T10:30' then
    raise exception 'scheduled workflow lost scheduledAt';
  end if;
  if coalesce(v_spec ->> 'recurrence','') <> ''
    or coalesce(v_spec ->> 'customEvery','') <> ''
    or coalesce(v_spec ->> 'customUnit','') <> '' then
    raise exception 'scheduled workflow retained irrelevant recurrence fields';
  end if;
end;
$$;

-- Recurrencia personalizada requiere valor y unidad; ambos quedan persistidos.
select set_config(
  'gestionpisos.workflow_custom_id',
  (select definition_id::text
   from public.save_workflow_definition_draft_v1(
     jsonb_build_object(
       'authoringVersion',2,
       'flowName','Limpieza personalizada',
       'flowType','cleaning',
       'flowDescription','',
       'scopeType','property',
       'triggerType','recurring',
       'recurrence','custom',
       'scheduledAt','2026-10-20T10:30',
       'customEvery','3',
       'customUnit','day',
       'assignmentType','property_responsible',
       'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
       'closeType','auto',
       'notifications',jsonb_build_object('onCreate',false,'onClose',false)
     )
   )
   limit 1),
  true
);

do $$
declare
  v_spec jsonb;
  v_complete boolean;
begin
  select draft_spec, authoring_complete
  into v_spec, v_complete
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.workflow_custom_id')::uuid;

  if not v_complete then
    raise exception 'custom recurring workflow not marked complete';
  end if;
  if v_spec ->> 'customEvery' <> '3' or v_spec ->> 'customUnit' <> 'day' then
    raise exception 'custom recurring workflow lost cadence';
  end if;
  if coalesce(v_spec ->> 'scheduledAt','') <> '' then
    raise exception 'custom recurring workflow retained irrelevant scheduledAt';
  end if;
end;
$$;

-- Manual ignora cualquier frecuencia o fecha residual enviada por el cliente.
select set_config(
  'gestionpisos.workflow_manual_trigger_id',
  (select definition_id::text
   from public.save_workflow_definition_draft_v1(
     jsonb_build_object(
       'authoringVersion',2,
       'flowName','Flujo manual saneado',
       'flowType','custom',
       'flowDescription','',
       'scopeType','organization',
       'triggerType','manual',
       'recurrence','monthly',
       'scheduledAt','2026-10-20T10:30',
       'customEvery','4',
       'customUnit','week',
       'assignmentType','manual',
       'steps',jsonb_build_object('accept',true,'photo',false,'checklist',false,'document',false),
       'closeType','auto',
       'notifications',jsonb_build_object('onCreate',false,'onClose',false)
     )
   )
   limit 1),
  true
);

do $$
declare v_spec jsonb;
begin
  select draft_spec into v_spec
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.workflow_manual_trigger_id')::uuid;

  if coalesce(v_spec ->> 'recurrence','') <> ''
    or coalesce(v_spec ->> 'scheduledAt','') <> ''
    or coalesce(v_spec ->> 'customEvery','') <> ''
    or coalesce(v_spec ->> 'customUnit','') <> '' then
    raise exception 'manual workflow retained irrelevant trigger fields';
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

-- Publicación y aplicaciones concretas: la receta no contiene el UUID del ámbito real.
-- Sin AAL2 no se permite publicar una definición completa.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.workflow_root'),
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

do $$
begin
  begin
    perform * from public.publish_workflow_definition_v1(
      current_setting('gestionpisos.workflow_manual_trigger_id')::uuid,
      1
    );
    raise exception 'workflow publish without aal2 unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Un TENANT con AAL2 tampoco adquiere capacidad administrativa.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.workflow_tenant'),
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

do $$
begin
  begin
    perform * from public.publish_workflow_definition_v1(
      current_setting('gestionpisos.workflow_manual_trigger_id')::uuid,
      1
    );
    raise exception 'tenant workflow publish unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- ROOT con AAL2 publica una sola versión inmutable; reintentar no duplica.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.workflow_root'),
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

select set_config(
  'gestionpisos.workflow_org_version_id',
  (
    select version_id::text
    from public.publish_workflow_definition_v1(
      current_setting('gestionpisos.workflow_manual_trigger_id')::uuid,
      1
    )
    limit 1
  ),
  true
);

do $$
declare
  v_versions integer;
  v_status text;
  v_scope text;
begin
  select count(*) into v_versions
  from public.workflow_definition_versions_v2
  where definition_id=current_setting('gestionpisos.workflow_manual_trigger_id')::uuid;

  if v_versions<>1 then
    raise exception 'workflow publication did not create exactly one version';
  end if;

  select status into v_status
  from public.workflow_definitions_v2
  where id=current_setting('gestionpisos.workflow_manual_trigger_id')::uuid;

  if v_status<>'published' then
    raise exception 'workflow definition not marked published';
  end if;

  select spec->>'scopeType' into v_scope
  from public.workflow_definition_versions_v2
  where id=current_setting('gestionpisos.workflow_org_version_id')::uuid;

  if v_scope<>'organization' then
    raise exception 'published version did not freeze logical scope type';
  end if;
end;
$$;

select * from public.publish_workflow_definition_v1(
  current_setting('gestionpisos.workflow_manual_trigger_id')::uuid,
  1
);

do $$
declare v_versions integer;
begin
  select count(*) into v_versions
  from public.workflow_definition_versions_v2
  where definition_id=current_setting('gestionpisos.workflow_manual_trigger_id')::uuid;
  if v_versions<>1 then
    raise exception 'idempotent workflow publication duplicated version';
  end if;
end;
$$;

-- Un borrador incompleto sigue sin ser publicable.
do $$
begin
  begin
    perform * from public.publish_workflow_definition_v1(
      current_setting('gestionpisos.workflow_legacy_id')::uuid,
      1
    );
    raise exception 'incomplete workflow unexpectedly published';
  exception when invalid_parameter_value then null;
  end;
end;
$$;

-- La aplicación a organización no necesita target concreto.
select set_config(
  'gestionpisos.workflow_org_application_id',
  (
    select application_id::text
    from public.create_workflow_application_v1(
      current_setting('gestionpisos.workflow_org_version_id')::uuid
    )
    limit 1
  ),
  true
);

-- Reintentar la misma aplicación es idempotente.
select * from public.create_workflow_application_v1(
  current_setting('gestionpisos.workflow_org_version_id')::uuid
);

do $$
declare v_count integer;
begin
  select count(*) into v_count
  from public.workflow_applications_v2
  where definition_id=current_setting('gestionpisos.workflow_manual_trigger_id')::uuid
    and status='configured';
  if v_count<>1 then
    raise exception 'organization workflow application duplicated';
  end if;
end;
$$;

-- Datos reales de ámbito para validar piso/habitación/ocupación.
reset role;

select set_config('gestionpisos.workflow_owner_1','77777777-7777-4777-8777-777777777777',true);
select set_config('gestionpisos.workflow_property_1','88888888-8888-4888-8888-888888888888',true);
select set_config('gestionpisos.workflow_room_1','99999999-9999-4999-8999-999999999999',true);
select set_config('gestionpisos.workflow_occupancy_1','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
select set_config('gestionpisos.workflow_owner_2','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
select set_config('gestionpisos.workflow_property_2','cccccccc-cccc-4ccc-8ccc-cccccccccccc',true);

insert into public.owners(id,organization_id,full_name,status)
values
  (current_setting('gestionpisos.workflow_owner_1')::uuid,current_setting('gestionpisos.workflow_org_1')::uuid,'Owner workflow','active'),
  (current_setting('gestionpisos.workflow_owner_2')::uuid,current_setting('gestionpisos.workflow_org_2')::uuid,'Owner otra org','active');

insert into public.properties_v2(id,organization_id,owner_id,name,address_line,status)
values
  (
    current_setting('gestionpisos.workflow_property_1')::uuid,
    current_setting('gestionpisos.workflow_org_1')::uuid,
    current_setting('gestionpisos.workflow_owner_1')::uuid,
    'Piso Workflow',
    'Calle Prueba 1',
    'active'
  ),
  (
    current_setting('gestionpisos.workflow_property_2')::uuid,
    current_setting('gestionpisos.workflow_org_2')::uuid,
    current_setting('gestionpisos.workflow_owner_2')::uuid,
    'Piso Otra Org',
    'Calle Ajena 2',
    'active'
  );

insert into public.rooms_v2(id,property_id,label,status)
values (
  current_setting('gestionpisos.workflow_room_1')::uuid,
  current_setting('gestionpisos.workflow_property_1')::uuid,
  'Habitación Workflow',
  'active'
);

insert into public.occupancies_v2(
  id,organization_id,property_id,room_id,occupant_email,starts_on,ends_on,status
) values (
  current_setting('gestionpisos.workflow_occupancy_1')::uuid,
  current_setting('gestionpisos.workflow_org_1')::uuid,
  current_setting('gestionpisos.workflow_property_1')::uuid,
  current_setting('gestionpisos.workflow_room_1')::uuid,
  'tenant-workflow@example.invalid',
  current_date-1,
  null,
  'active'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.workflow_root'),
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

-- Publicar la definición de ámbito piso ya creada en la regresión.
select set_config(
  'gestionpisos.workflow_property_version_id',
  (
    select version_id::text
    from public.publish_workflow_definition_v1(
      current_setting('gestionpisos.workflow_custom_id')::uuid,
      1
    )
    limit 1
  ),
  true
);

-- Otra organización nunca puede usarse como target de una aplicación.
do $$
begin
  begin
    perform * from public.create_workflow_application_v1(
      current_setting('gestionpisos.workflow_property_version_id')::uuid,
      current_setting('gestionpisos.workflow_property_2')::uuid
    );
    raise exception 'cross-organization workflow application unexpectedly succeeded';
  exception when invalid_parameter_value then null;
  end;
end;
$$;

select set_config(
  'gestionpisos.workflow_property_application_id',
  (
    select application_id::text
    from public.create_workflow_application_v1(
      current_setting('gestionpisos.workflow_property_version_id')::uuid,
      current_setting('gestionpisos.workflow_property_1')::uuid
    )
    limit 1
  ),
  true
);

-- Una habitación usa selector en cascada Piso -> Habitación y se valida server-side.
select set_config(
  'gestionpisos.workflow_room_definition_id',
  (
    select definition_id::text
    from public.save_workflow_definition_draft_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Inspección de habitación',
        'flowType','inspection',
        'flowDescription','',
        'scopeType','room',
        'triggerType','manual',
        'recurrence','',
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
  'gestionpisos.workflow_room_version_id',
  (
    select version_id::text
    from public.publish_workflow_definition_v1(
      current_setting('gestionpisos.workflow_room_definition_id')::uuid,
      1
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.workflow_room_application_id',
  (
    select application_id::text
    from public.create_workflow_application_v1(
      current_setting('gestionpisos.workflow_room_version_id')::uuid,
      current_setting('gestionpisos.workflow_property_1')::uuid,
      current_setting('gestionpisos.workflow_room_1')::uuid
    )
    limit 1
  ),
  true
);

-- Una ocupación real se vincula por UUID y debe estar vigente.
select set_config(
  'gestionpisos.workflow_occupancy_definition_id',
  (
    select definition_id::text
    from public.save_workflow_definition_draft_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Check-out ocupación',
        'flowType','checkout',
        'flowDescription','',
        'scopeType','occupancy',
        'triggerType','manual',
        'recurrence','',
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
  'gestionpisos.workflow_occupancy_version_id',
  (
    select version_id::text
    from public.publish_workflow_definition_v1(
      current_setting('gestionpisos.workflow_occupancy_definition_id')::uuid,
      1
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.workflow_occupancy_application_id',
  (
    select application_id::text
    from public.create_workflow_application_v1(
      current_setting('gestionpisos.workflow_occupancy_version_id')::uuid,
      current_setting('gestionpisos.workflow_property_1')::uuid,
      null,
      current_setting('gestionpisos.workflow_occupancy_1')::uuid
    )
    limit 1
  ),
  true
);

do $$
declare
  v_property uuid;
  v_room uuid;
  v_occupancy uuid;
begin
  select property_id into v_property
  from public.workflow_applications_v2
  where id=current_setting('gestionpisos.workflow_property_application_id')::uuid;
  if v_property<>current_setting('gestionpisos.workflow_property_1')::uuid then
    raise exception 'property workflow application lost target';
  end if;

  select room_id into v_room
  from public.workflow_applications_v2
  where id=current_setting('gestionpisos.workflow_room_application_id')::uuid;
  if v_room<>current_setting('gestionpisos.workflow_room_1')::uuid then
    raise exception 'room workflow application lost target';
  end if;

  select occupancy_id into v_occupancy
  from public.workflow_applications_v2
  where id=current_setting('gestionpisos.workflow_occupancy_application_id')::uuid;
  if v_occupancy<>current_setting('gestionpisos.workflow_occupancy_1')::uuid then
    raise exception 'occupancy workflow application lost target';
  end if;
end;
$$;

-- Ejecución manual: TENANT no puede lanzar aunque conozca el application_id.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.workflow_tenant'),
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

do $$
begin
  begin
    perform * from public.execute_workflow_application_now_v1(
      current_setting('gestionpisos.workflow_room_application_id')::uuid,
      'tenant-forbidden-001',
      current_setting('gestionpisos.workflow_tenant')::uuid
    );
    raise exception 'tenant workflow execution unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- ROOT vuelve a lanzar el caso manual exacto y se asigna explícitamente.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.workflow_root'),
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

do $$
begin
  begin
    perform * from public.execute_workflow_application_now_v1(
      current_setting('gestionpisos.workflow_room_application_id')::uuid,
      'manual-missing-assignee-001',
      null
    );
    raise exception 'manual workflow execution without assignee unexpectedly succeeded';
  exception when invalid_parameter_value then null;
  end;
end;
$$;

select set_config(
  'gestionpisos.workflow_execution_id',
  (
    select execution_id::text
    from public.execute_workflow_application_now_v1(
      current_setting('gestionpisos.workflow_room_application_id')::uuid,
      'manual-room-001',
      current_setting('gestionpisos.workflow_root')::uuid
    )
    limit 1
  ),
  true
);

do $$
declare
  v_execution public.workflow_executions_v2;
  v_events integer;
begin
  select * into v_execution
  from public.workflow_executions_v2
  where id=current_setting('gestionpisos.workflow_execution_id')::uuid;

  if v_execution.id is null then
    raise exception 'workflow execution was not created';
  end if;
  if v_execution.application_id<>current_setting('gestionpisos.workflow_room_application_id')::uuid then
    raise exception 'workflow execution lost application identity';
  end if;
  if v_execution.scope_type<>'room'
    or v_execution.property_id<>current_setting('gestionpisos.workflow_property_1')::uuid
    or v_execution.room_id<>current_setting('gestionpisos.workflow_room_1')::uuid
    or v_execution.occupancy_id is not null then
    raise exception 'workflow execution lost concrete room scope';
  end if;
  if v_execution.trigger_kind<>'manual_now'
    or v_execution.assignment_type<>'manual'
    or v_execution.assigned_user_id<>current_setting('gestionpisos.workflow_root')::uuid
    or v_execution.status<>'pending' then
    raise exception 'workflow execution did not freeze trigger/assignment/status';
  end if;
  if v_execution.spec_snapshot->>'scopeType'<>'room'
    or v_execution.spec_snapshot->>'assignmentType'<>'manual' then
    raise exception 'workflow execution lost immutable spec snapshot';
  end if;

  select count(*) into v_events
  from public.workflow_execution_events_v2
  where execution_id=v_execution.id and event_type='created';

  if v_events<>1 then
    raise exception 'workflow execution did not create exactly one initial event';
  end if;

  select count(*) into v_events
  from public.workflow_execution_events_v2
  where execution_id=v_execution.id and event_type='task_materialized';

  if v_events<>1 then
    raise exception 'workflow execution did not materialize exactly one task event';
  end if;
end;
$$;

do $$
declare
  v_task public.tenant_tasks_v2;
  v_history integer;
  v_actions integer;
begin
  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('gestionpisos.workflow_execution_id')::uuid;

  if v_task.id is null then
    raise exception 'workflow task was not materialized';
  end if;

  if v_task.task_type<>'workflow'
    or v_task.status<>'pending'
    or v_task.tenant_id is not null
    or v_task.property_id<>current_setting('gestionpisos.workflow_property_1')::uuid
    or v_task.room_id<>current_setting('gestionpisos.workflow_room_1')::uuid
    or v_task.assigned_user_id<>current_setting('gestionpisos.workflow_root')::uuid then
    raise exception 'workflow task lost execution scope or assignment';
  end if;

  select count(*) into v_history
  from public.tenant_task_history_v2
  where task_id=v_task.id and action_key='create';

  if v_history<>1 then
    raise exception 'workflow task did not create exactly one history row';
  end if;

  select count(*) into v_actions
  from public.tenant_task_actions_v2
  where task_id=v_task.id
    and action_key='accept'
    and from_status='pending'
    and to_status='completed'
    and actor='assignee'
    and active=true;

  if v_actions<>1 then
    raise exception 'workflow task did not expose the single safe accept action';
  end if;
end;
$$;

-- Reintentar la misma intención devuelve la ejecución existente y no duplica eventos.
do $$
declare
  v_execution_id uuid;
  v_created_new boolean;
  v_count integer;
  v_events integer;
  v_tasks integer;
  v_task_history integer;
  v_task_events integer;
begin
  select execution_id,created_new
  into v_execution_id,v_created_new
  from public.execute_workflow_application_now_v1(
    current_setting('gestionpisos.workflow_room_application_id')::uuid,
    'manual-room-001',
    current_setting('gestionpisos.workflow_root')::uuid
  )
  limit 1;

  if v_execution_id<>current_setting('gestionpisos.workflow_execution_id')::uuid then
    raise exception 'workflow execution idempotent retry returned another execution';
  end if;
  if v_created_new then
    raise exception 'workflow execution idempotent retry claimed a new execution';
  end if;

  select count(*) into v_count
  from public.workflow_executions_v2
  where application_id=current_setting('gestionpisos.workflow_room_application_id')::uuid
    and idempotency_key='manual-room-001';

  select count(*) into v_events
  from public.workflow_execution_events_v2
  where execution_id=v_execution_id and event_type='created';

  select count(*) into v_tasks
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution_id;

  select count(*) into v_task_history
  from public.tenant_task_history_v2 h
  join public.tenant_tasks_v2 t on t.id=h.task_id
  where t.source_kind='workflow_execution'
    and t.source_id=v_execution_id
    and h.action_key='create';

  select count(*) into v_task_events
  from public.workflow_execution_events_v2
  where execution_id=v_execution_id
    and event_type='task_materialized';

  if v_count<>1 or v_events<>1 or v_tasks<>1 or v_task_history<>1 or v_task_events<>1 then
    raise exception 'workflow execution idempotency duplicated execution, task or event';
  end if;
end;
$$;

-- Materializar de nuevo explícitamente es idempotente.
do $$
declare
  v_task_id uuid;
  v_count integer;
begin
  select id into v_task_id
  from public.materialize_workflow_execution_task_v1(
    current_setting('gestionpisos.workflow_execution_id')::uuid
  );

  select count(*) into v_count
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('gestionpisos.workflow_execution_id')::uuid;

  if v_task_id is null or v_count<>1 then
    raise exception 'explicit workflow task materialization was not idempotent';
  end if;
end;
$$;

-- TENANT no puede forzar materialización ni leer la tarea ajena.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.workflow_tenant'),
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

do $$
declare v_visible integer;
begin
  begin
    perform public.materialize_workflow_execution_task_v1(
      current_setting('gestionpisos.workflow_execution_id')::uuid
    );
    raise exception 'tenant workflow task materialization unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;

  select count(*) into v_visible
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('gestionpisos.workflow_execution_id')::uuid;

  if v_visible<>0 then
    raise exception 'tenant can read workflow task outside scope';
  end if;
end;
$$;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.workflow_root'),
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

-- La ruta legacy queda bloqueada para tareas workflow para impedir divergencia.
do $$
declare v_task_id uuid;
begin
  select id into v_task_id
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('gestionpisos.workflow_execution_id')::uuid;

  begin
    perform public.apply_tenant_task_action_v2(v_task_id,'accept',null);
    raise exception 'legacy task action RPC unexpectedly changed a workflow task';
  exception when feature_not_supported then null;
  end;
end;
$$;

-- Un usuario no asignado no puede aplicar una acción aunque conozca el task_id.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.workflow_tenant'),
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

do $$
declare v_task_id uuid;
begin
  select id into v_task_id
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('gestionpisos.workflow_execution_id')::uuid;

  begin
    perform * from public.apply_workflow_task_action_v1(
      v_task_id,'accept','tenant-forbidden-action-001',null
    );
    raise exception 'unassigned tenant workflow action unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- El asignado aplica accept: al ser el único paso y cierre auto, ambos estados terminan en completed.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.workflow_root'),
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

select set_config(
  'gestionpisos.workflow_task_id',
  (
    select id::text
    from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('gestionpisos.workflow_execution_id')::uuid
    limit 1
  ),
  true
);

do $$
declare
  v_task_status text;
  v_execution_status text;
  v_applied_new boolean;
begin
  select task_status,execution_status,applied_new
  into v_task_status,v_execution_status,v_applied_new
  from public.apply_workflow_task_action_v1(
    current_setting('gestionpisos.workflow_task_id')::uuid,
    'accept',
    'accept-room-001',
    null
  )
  limit 1;

  if v_task_status<>'completed' or v_execution_status<>'completed' or not v_applied_new then
    raise exception 'atomic workflow accept did not complete task and execution together';
  end if;
end;
$$;

do $$
declare
  v_task_status text;
  v_execution_status text;
  v_completed_at timestamptz;
  v_history integer;
  v_events integer;
begin
  select status into v_task_status
  from public.tenant_tasks_v2
  where id=current_setting('gestionpisos.workflow_task_id')::uuid;

  select status,completed_at
  into v_execution_status,v_completed_at
  from public.workflow_executions_v2
  where id=current_setting('gestionpisos.workflow_execution_id')::uuid;

  if v_task_status<>'completed' or v_execution_status<>'completed' or v_completed_at is null then
    raise exception 'workflow task/execution completion state diverged';
  end if;

  select count(*) into v_history
  from public.tenant_task_history_v2
  where task_id=current_setting('gestionpisos.workflow_task_id')::uuid
    and action_key='accept'
    and from_status='pending'
    and to_status='completed';

  select count(*) into v_events
  from public.workflow_execution_events_v2
  where execution_id=current_setting('gestionpisos.workflow_execution_id')::uuid
    and event_type='task_action_applied'
    and details->>'request_key'='accept-room-001'
    and details->>'action_key'='accept';

  if v_history<>1 or v_events<>1 then
    raise exception 'atomic workflow action did not create exactly one history/event';
  end if;
end;
$$;

-- Reintentar la misma request_key es idempotente y no duplica histórico/evento.
do $$
declare
  v_applied_new boolean;
  v_history integer;
  v_events integer;
begin
  select applied_new
  into v_applied_new
  from public.apply_workflow_task_action_v1(
    current_setting('gestionpisos.workflow_task_id')::uuid,
    'accept',
    'accept-room-001',
    null
  )
  limit 1;

  if v_applied_new then
    raise exception 'workflow action retry claimed a new transition';
  end if;

  select count(*) into v_history
  from public.tenant_task_history_v2
  where task_id=current_setting('gestionpisos.workflow_task_id')::uuid
    and action_key='accept';

  select count(*) into v_events
  from public.workflow_execution_events_v2
  where execution_id=current_setting('gestionpisos.workflow_execution_id')::uuid
    and event_type='task_action_applied'
    and details->>'request_key'='accept-room-001';

  if v_history<>1 or v_events<>1 then
    raise exception 'workflow action retry duplicated history or event';
  end if;
end;
$$;

-- La misma request_key no puede reutilizarse para otra acción.
do $$
begin
  begin
    perform * from public.apply_workflow_task_action_v1(
      current_setting('gestionpisos.workflow_task_id')::uuid,
      'different_action',
      'accept-room-001',
      null
    );
    raise exception 'workflow action request key conflict unexpectedly succeeded';
  exception when object_not_in_prerequisite_state then null;
  end;
end;
$$;

-- El cliente authenticated tampoco puede fabricar tareas saltándose el materializador.
do $$
begin
  begin
    insert into public.tenant_tasks_v2(
      organization_id,tenant_id,property_id,room_id,task_type,origin,title,status,
      assigned_user_id,source_kind,source_id,created_by
    ) values (
      current_setting('gestionpisos.workflow_org_1')::uuid,
      null,
      current_setting('gestionpisos.workflow_property_1')::uuid,
      current_setting('gestionpisos.workflow_room_1')::uuid,
      'workflow',
      'automatic',
      'Directa prohibida',
      'pending',
      current_setting('gestionpisos.workflow_root')::uuid,
      'workflow_execution',
      current_setting('gestionpisos.workflow_execution_id')::uuid,
      current_setting('gestionpisos.workflow_root')::uuid
    );
    raise exception 'direct workflow task insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- El cliente authenticated no puede fabricar ejecuciones saltándose el RPC.
do $$
begin
  begin
    insert into public.workflow_executions_v2(
      application_id,definition_id,definition_version_id,organization_id,
      scope_type,property_id,room_id,trigger_kind,idempotency_key,
      assignment_type,assigned_user_id,status,spec_snapshot,created_by
    ) values (
      current_setting('gestionpisos.workflow_room_application_id')::uuid,
      current_setting('gestionpisos.workflow_room_definition_id')::uuid,
      current_setting('gestionpisos.workflow_room_version_id')::uuid,
      current_setting('gestionpisos.workflow_org_1')::uuid,
      'room',
      current_setting('gestionpisos.workflow_property_1')::uuid,
      current_setting('gestionpisos.workflow_room_1')::uuid,
      'manual_now',
      'direct-forbidden-001',
      'manual',
      current_setting('gestionpisos.workflow_root')::uuid,
      'pending',
      '{}'::jsonb,
      current_setting('gestionpisos.workflow_root')::uuid
    );
    raise exception 'direct workflow execution insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- La relajación de tenant_id no permite tareas legacy sin inquilino.
reset role;

do $$
begin
  begin
    insert into public.tenant_tasks_v2(
      organization_id,tenant_id,task_type,origin,title,status,created_by
    ) values (
      current_setting('gestionpisos.workflow_org_1')::uuid,
      null,
      'generic',
      'manual',
      'Legacy sin inquilino prohibida',
      'pending',
      current_setting('gestionpisos.workflow_root')::uuid
    );
    raise exception 'legacy task without tenant unexpectedly succeeded';
  exception when check_violation then null;
  end;
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.workflow_root'),
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

-- La tabla de aplicaciones tampoco admite escritura directa desde authenticated.
do $$
begin
  begin
    insert into public.workflow_applications_v2(
      definition_id,definition_version_id,organization_id,scope_type,status,created_by
    ) values (
      current_setting('gestionpisos.workflow_manual_trigger_id')::uuid,
      current_setting('gestionpisos.workflow_org_version_id')::uuid,
      current_setting('gestionpisos.workflow_org_1')::uuid,
      'organization',
      'configured',
      current_setting('gestionpisos.workflow_root')::uuid
    );
    raise exception 'direct workflow application insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Archivar es explícito, reversible por nueva aplicación y conserva histórico.
select public.archive_workflow_application_v1(
  current_setting('gestionpisos.workflow_property_application_id')::uuid
);

do $$
declare v_status text;
begin
  select status into v_status
  from public.workflow_applications_v2
  where id=current_setting('gestionpisos.workflow_property_application_id')::uuid;
  if v_status<>'archived' then
    raise exception 'workflow application archive failed';
  end if;
end;
$$;

do $$
begin
  begin
    perform * from public.execute_workflow_application_now_v1(
      current_setting('gestionpisos.workflow_property_application_id')::uuid,
      'archived-forbidden-001',
      null
    );
    raise exception 'archived workflow application unexpectedly executed';
  exception when object_not_in_prerequisite_state then null;
  end;
end;
$$;

select * from public.create_workflow_application_v1(
  current_setting('gestionpisos.workflow_property_version_id')::uuid,
  current_setting('gestionpisos.workflow_property_1')::uuid
);

reset role;
rollback;
