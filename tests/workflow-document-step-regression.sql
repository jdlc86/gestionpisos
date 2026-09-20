-- Flujos · regresión del paso Documento.
-- PostgreSQL desechable. Todo se revierte al finalizar.

begin;

do $privileges$
begin
  if has_function_privilege('anon','public.prepare_workflow_document_upload_v1(uuid,text,text,bigint,text)','EXECUTE') then
    raise exception 'anon can prepare workflow documents';
  end if;
  if has_function_privilege('anon','public.submit_workflow_document_v1(uuid,text)','EXECUTE') then
    raise exception 'anon can submit workflow documents';
  end if;
  if not has_function_privilege('authenticated','public.prepare_workflow_document_upload_v1(uuid,text,text,bigint,text)','EXECUTE')
    or not has_function_privilege('authenticated','public.submit_workflow_document_v1(uuid,text)','EXECUTE') then
    raise exception 'authenticated missing workflow document RPC';
  end if;
end;
$privileges$;

do $schema$
begin
  if not exists(
    select 1
    from information_schema.tables
    where table_schema='public'
      and table_name='workflow_execution_documents_v2'
  ) then
    raise exception 'workflow document table missing';
  end if;

  if not exists(
    select 1
    from storage.buckets
    where id='workflow-documents-v2'
      and public=false
      and file_size_limit=10485760
  ) then
    raise exception 'workflow document bucket missing or unsafe';
  end if;
end;
$schema$;

-- El ROOT del fixture actúa como assignee en esta regresión de Documento solo
-- mediante una relación employee explícita, no por privilegio ROOT.
insert into public.user_roles(user_id,organization_id,role)
select ur.user_id,ur.organization_id,'employee'
from public.user_roles ur
where ur.user_id='22222222-2222-4222-8222-222222222222'::uuid
  and ur.role='root'
  and ur.revoked_at is null
limit 1
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

-- Documento solo: prepare inicia la tarea y submit la cierra.
select set_config(
  'gestionpisos.doc.execution',
  (
    select execution_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Documento solo',
        'flowType','custom',
        'flowDescription','Documento auto',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',false,'photo',false,'checklist',false,'document',true),
        'checklistItems','[]'::jsonb,
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      null,null,null,'{}'::uuid[],true,
      'regression-document-only',
      'regression-document-only-execution',
      '22222222-2222-4222-8222-222222222222'::uuid
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.doc.task',
  (
    select id::text
    from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('gestionpisos.doc.execution')::uuid
  ),
  true
);

do $document_initial$
begin
  if not exists(
    select 1
    from public.tenant_tasks_v2 t
    join public.workflow_executions_v2 e on e.id=t.source_id
    where t.id=current_setting('gestionpisos.doc.task')::uuid
      and t.status='pending'
      and e.status='pending'
  ) then
    raise exception 'document-only execution did not start pending';
  end if;
end;
$document_initial$;

select set_config(
  'gestionpisos.doc.id',
  (
    select document_id::text
    from public.prepare_workflow_document_upload_v1(
      current_setting('gestionpisos.doc.task')::uuid,
      'contrato.pdf',
      'application/pdf',
      4096,
      'regression-document-upload'
    )
    limit 1
  ),
  true
);

do $document_prepared$
declare
  v_execution uuid:=current_setting('gestionpisos.doc.execution')::uuid;
  v_task uuid:=current_setting('gestionpisos.doc.task')::uuid;
  v_doc uuid:=current_setting('gestionpisos.doc.id')::uuid;
  v_created_new boolean;
begin
  if not exists(
    select 1
    from public.workflow_execution_documents_v2
    where id=v_doc
      and execution_id=v_execution
      and task_id=v_task
      and status='uploading'
      and mime_type='application/pdf'
      and size_bytes=4096
  ) then
    raise exception 'prepared document metadata missing';
  end if;

  if not exists(
    select 1
    from public.tenant_tasks_v2 t
    join public.workflow_executions_v2 e on e.id=t.source_id
    where t.id=v_task
      and t.status='active'
      and e.status='active'
  ) then
    raise exception 'document prepare did not activate no-accept workflow';
  end if;

  select created_new
  into v_created_new
  from public.prepare_workflow_document_upload_v1(
    v_task,'contrato.pdf','application/pdf',4096,'regression-document-upload'
  )
  limit 1;

  if v_created_new then
    raise exception 'document prepare retry was not idempotent';
  end if;

  if (
    select count(*)
    from public.workflow_execution_documents_v2
    where execution_id=v_execution
      and request_key='regression-document-upload'
  )<>1 then
    raise exception 'document prepare retry duplicated metadata';
  end if;
end;
$document_prepared$;

reset role;
insert into storage.objects(bucket_id,name,owner_id)
select 'workflow-documents-v2',storage_path,'22222222-2222-4222-8222-222222222222'
from public.workflow_execution_documents_v2
where id=current_setting('gestionpisos.doc.id')::uuid;
set local role authenticated;

select *
from public.submit_workflow_document_v1(
  current_setting('gestionpisos.doc.id')::uuid,
  'regression-document-upload'
);

do $document_completed$
declare
  v_execution uuid:=current_setting('gestionpisos.doc.execution')::uuid;
  v_task uuid:=current_setting('gestionpisos.doc.task')::uuid;
  v_doc uuid:=current_setting('gestionpisos.doc.id')::uuid;
  v_applied boolean;
begin
  if not exists(
    select 1
    from public.workflow_execution_documents_v2
    where id=v_doc
      and status='submitted'
      and submitted_at is not null
  ) then
    raise exception 'document did not become submitted';
  end if;

  if not exists(
    select 1
    from public.tenant_tasks_v2 t
    join public.workflow_executions_v2 e on e.id=t.source_id
    where t.id=v_task
      and t.status='completed'
      and e.id=v_execution
      and e.status='completed'
      and e.completed_at is not null
  ) then
    raise exception 'document-only workflow did not complete';
  end if;

  select applied_new
  into v_applied
  from public.submit_workflow_document_v1(v_doc,'regression-document-upload')
  limit 1;

  if v_applied then
    raise exception 'document submit retry was not idempotent';
  end if;

  if (
    select count(*)
    from public.workflow_execution_events_v2
    where execution_id=v_execution
      and event_type='document_evidence_submitted'
      and details->>'request_key'='regression-document-upload'
  )<>1 then
    raise exception 'document submit retry duplicated event';
  end if;
end;
$document_completed$;

-- Checklist primero, Documento después: checklist no puede cerrar mientras falte Documento.
select set_config(
  'gestionpisos.doccheck.execution',
  (
    select execution_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Checklist luego documento',
        'flowType','custom',
        'flowDescription','Orden checklist-documento',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',false,'photo',false,'checklist',true,'document',true),
        'checklistItems',jsonb_build_array(jsonb_build_object('text','Comprobar contrato','required',true)),
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      null,null,null,'{}'::uuid[],true,
      'regression-checklist-before-document',
      'regression-checklist-before-document-execution',
      '22222222-2222-4222-8222-222222222222'::uuid
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.doccheck.task',
  (
    select id::text
    from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('gestionpisos.doccheck.execution')::uuid
  ),
  true
);

select *
from public.set_workflow_checklist_item_v1(
  current_setting('gestionpisos.doccheck.task')::uuid,
  (
    select item->>'key'
    from public.workflow_executions_v2 e,
         lateral jsonb_array_elements(e.checklist_state) item
    where e.id=current_setting('gestionpisos.doccheck.execution')::uuid
    limit 1
  ),
  true,
  'regression-checklist-before-document-item'
);

do $checklist_waits_for_document$
begin
  if not exists(
    select 1
    from public.workflow_executions_v2
    where id=current_setting('gestionpisos.doccheck.execution')::uuid
      and status='active'
  ) then
    raise exception 'checklist closed while document was still missing';
  end if;
end;
$checklist_waits_for_document$;

select set_config(
  'gestionpisos.doccheck.id',
  (
    select document_id::text
    from public.prepare_workflow_document_upload_v1(
      current_setting('gestionpisos.doccheck.task')::uuid,
      'evidencia.png',
      'image/png',
      2048,
      'regression-checklist-before-document-upload'
    )
    limit 1
  ),
  true
);

reset role;
insert into storage.objects(bucket_id,name,owner_id)
select 'workflow-documents-v2',storage_path,'22222222-2222-4222-8222-222222222222'
from public.workflow_execution_documents_v2
where id=current_setting('gestionpisos.doccheck.id')::uuid;
set local role authenticated;

select *
from public.submit_workflow_document_v1(
  current_setting('gestionpisos.doccheck.id')::uuid,
  'regression-checklist-before-document-upload'
);

do $checklist_then_document_completed$
begin
  if not exists(
    select 1
    from public.workflow_executions_v2 e
    join public.tenant_tasks_v2 t on t.source_id=e.id and t.source_kind='workflow_execution'
    where e.id=current_setting('gestionpisos.doccheck.execution')::uuid
      and e.status='completed'
      and t.status='completed'
  ) then
    raise exception 'document did not close completed checklist workflow';
  end if;
end;
$checklist_then_document_completed$;

-- Documento primero, Checklist después: Documento no puede cerrar mientras falte Checklist.
select set_config(
  'gestionpisos.docfirst.execution',
  (
    select execution_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Documento luego checklist',
        'flowType','custom',
        'flowDescription','Orden documento-checklist',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',false,'photo',false,'checklist',true,'document',true),
        'checklistItems',jsonb_build_array(jsonb_build_object('text','Validar evidencia','required',true)),
        'closeType','auto',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      null,null,null,'{}'::uuid[],true,
      'regression-document-before-checklist',
      'regression-document-before-checklist-execution',
      '22222222-2222-4222-8222-222222222222'::uuid
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.docfirst.task',
  (
    select id::text
    from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('gestionpisos.docfirst.execution')::uuid
  ),
  true
);

select set_config(
  'gestionpisos.docfirst.id',
  (
    select document_id::text
    from public.prepare_workflow_document_upload_v1(
      current_setting('gestionpisos.docfirst.task')::uuid,
      'evidencia.jpg',
      'image/jpeg',
      1024,
      'regression-document-before-checklist-upload'
    )
    limit 1
  ),
  true
);

reset role;
insert into storage.objects(bucket_id,name,owner_id)
select 'workflow-documents-v2',storage_path,'22222222-2222-4222-8222-222222222222'
from public.workflow_execution_documents_v2
where id=current_setting('gestionpisos.docfirst.id')::uuid;
set local role authenticated;

select *
from public.submit_workflow_document_v1(
  current_setting('gestionpisos.docfirst.id')::uuid,
  'regression-document-before-checklist-upload'
);

do $document_waits_for_checklist$
begin
  if not exists(
    select 1
    from public.workflow_executions_v2
    where id=current_setting('gestionpisos.docfirst.execution')::uuid
      and status='active'
  ) then
    raise exception 'document closed while checklist was still missing';
  end if;
end;
$document_waits_for_checklist$;

select *
from public.set_workflow_checklist_item_v1(
  current_setting('gestionpisos.docfirst.task')::uuid,
  (
    select item->>'key'
    from public.workflow_executions_v2 e,
         lateral jsonb_array_elements(e.checklist_state) item
    where e.id=current_setting('gestionpisos.docfirst.execution')::uuid
    limit 1
  ),
  true,
  'regression-document-before-checklist-item'
);

do $document_then_checklist_completed$
begin
  if not exists(
    select 1
    from public.workflow_executions_v2 e
    join public.tenant_tasks_v2 t on t.source_id=e.id and t.source_kind='workflow_execution'
    where e.id=current_setting('gestionpisos.docfirst.execution')::uuid
      and e.status='completed'
      and t.status='completed'
  ) then
    raise exception 'checklist did not close submitted document workflow';
  end if;
end;
$document_then_checklist_completed$;

-- Documento + human_review: submit debe llegar a waiting_review, no completar.
select set_config(
  'gestionpisos.docreview.execution',
  (
    select execution_id::text
    from public.publish_workflow_ready_v1(
      jsonb_build_object(
        'authoringVersion',2,
        'flowName','Documento revisión',
        'flowType','custom',
        'flowDescription','Documento con revisión humana',
        'scopeType','organization',
        'triggerType','manual',
        'recurrence','',
        'scheduledAt','',
        'customEvery','',
        'customUnit','',
        'assignmentType','manual',
        'steps',jsonb_build_object('accept',false,'photo',false,'checklist',false,'document',true),
        'checklistItems','[]'::jsonb,
        'closeType','human_review',
        'notifications',jsonb_build_object('onCreate',false,'onClose',false)
      ),
      null,null,null,'{}'::uuid[],true,
      'regression-document-review',
      'regression-document-review-execution',
      '22222222-2222-4222-8222-222222222222'::uuid
    )
    limit 1
  ),
  true
);

select set_config(
  'gestionpisos.docreview.task',
  (
    select id::text
    from public.tenant_tasks_v2
    where source_kind='workflow_execution'
      and source_id=current_setting('gestionpisos.docreview.execution')::uuid
  ),
  true
);

select set_config(
  'gestionpisos.docreview.id',
  (
    select document_id::text
    from public.prepare_workflow_document_upload_v1(
      current_setting('gestionpisos.docreview.task')::uuid,
      'revision.webp',
      'image/webp',
      512,
      'regression-document-review-upload'
    )
    limit 1
  ),
  true
);

reset role;
insert into storage.objects(bucket_id,name,owner_id)
select 'workflow-documents-v2',storage_path,'22222222-2222-4222-8222-222222222222'
from public.workflow_execution_documents_v2
where id=current_setting('gestionpisos.docreview.id')::uuid;
set local role authenticated;

select *
from public.submit_workflow_document_v1(
  current_setting('gestionpisos.docreview.id')::uuid,
  'regression-document-review-upload'
);

do $document_waiting_review$
begin
  if not exists(
    select 1
    from public.workflow_executions_v2 e
    join public.tenant_tasks_v2 t on t.source_id=e.id and t.source_kind='workflow_execution'
    where e.id=current_setting('gestionpisos.docreview.execution')::uuid
      and e.status='waiting_review'
      and t.status='waiting_review'
  ) then
    raise exception 'document human review did not wait for manager';
  end if;

  if not exists(
    select 1
    from public.tenant_task_actions_v2
    where task_id=current_setting('gestionpisos.docreview.task')::uuid
      and action_key='review_approve'
      and from_status='waiting_review'
      and actor='agency'
      and active=true
  ) then
    raise exception 'document human review action missing';
  end if;
end;
$document_waiting_review$;

rollback;
