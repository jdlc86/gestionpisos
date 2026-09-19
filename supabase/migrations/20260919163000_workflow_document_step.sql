-- GestionPisos · Flujos de Trabajo · paso Documento
-- Documento se integra en workflow_executions_v2 / tenant_tasks_v2.
-- No crea un motor paralelo de tareas ni reutiliza el expediente documental de inquilinos.
--
-- Contrato inicial:
--   * uno o más documentos por ejecución;
--   * al menos un documento submitted satisface el paso Documento;
--   * formatos: PDF, JPEG, PNG, WebP;
--   * máximo 10 MiB por archivo;
--   * solo el asignado prepara/sube; gestores autorizados pueden leer;
--   * Foto, Checklist y Documento pueden finalizar en cualquier orden.

create table public.workflow_execution_documents_v2 (
  id uuid primary key default gen_random_uuid(),
  execution_id uuid not null references public.workflow_executions_v2(id) on delete restrict,
  task_id uuid not null references public.tenant_tasks_v2(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  uploaded_by uuid not null references auth.users(id) on delete restrict,
  original_filename text not null check (
    length(btrim(original_filename)) between 1 and 255
  ),
  mime_type text not null check (
    mime_type in ('application/pdf','image/jpeg','image/png','image/webp')
  ),
  size_bytes bigint not null check (
    size_bytes between 1 and 10485760
  ),
  storage_path text not null unique,
  request_key text not null check (
    length(btrim(request_key)) between 1 and 200
  ),
  status text not null default 'uploading'
    check (status in ('uploading','submitted')),
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  unique(execution_id,request_key)
);

create index workflow_execution_documents_v2_execution_idx
  on public.workflow_execution_documents_v2(execution_id,status,created_at);

create index workflow_execution_documents_v2_task_idx
  on public.workflow_execution_documents_v2(task_id,created_at);

alter table public.workflow_execution_documents_v2 enable row level security;

revoke all on public.workflow_execution_documents_v2 from anon;
revoke insert,update,delete,truncate,references,trigger
  on public.workflow_execution_documents_v2 from authenticated;
grant select on public.workflow_execution_documents_v2 to authenticated;

create policy workflow_execution_documents_v2_read
on public.workflow_execution_documents_v2
for select to authenticated
using (
  uploaded_by=(select auth.uid())
  or public.workflow_can_read_definitions_v1(organization_id)
  or exists(
    select 1
    from public.workflow_executions_v2 e
    where e.id=execution_id
      and e.assigned_user_id=(select auth.uid())
  )
);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values (
  'workflow-documents-v2',
  'workflow-documents-v2',
  false,
  10485760,
  array['application/pdf','image/jpeg','image/png','image/webp']
)
on conflict(id) do update set
  public=excluded.public,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists workflow_documents_storage_insert
  on storage.objects;
create policy workflow_documents_storage_insert
on storage.objects
for insert to authenticated
with check (
  bucket_id='workflow-documents-v2'
  and exists(
    select 1
    from public.workflow_execution_documents_v2 d
    join public.workflow_executions_v2 e on e.id=d.execution_id
    join public.tenant_tasks_v2 t on t.id=d.task_id
    where d.storage_path=storage.objects.name
      and d.status='uploading'
      and d.uploaded_by=(select auth.uid())
      and e.organization_id=d.organization_id
      and e.assigned_user_id=(select auth.uid())
      and t.source_kind='workflow_execution'
      and t.source_id=e.id
      and t.assigned_user_id=(select auth.uid())
      and t.status in ('pending','active')
      and e.status=t.status
  )
);

drop policy if exists workflow_documents_storage_select
  on storage.objects;
create policy workflow_documents_storage_select
on storage.objects
for select to authenticated
using (
  bucket_id='workflow-documents-v2'
  and exists(
    select 1
    from public.workflow_execution_documents_v2 d
    join public.workflow_executions_v2 e on e.id=d.execution_id
    where d.storage_path=storage.objects.name
      and (
        d.uploaded_by=(select auth.uid())
        or e.assigned_user_id=(select auth.uid())
        or public.workflow_can_read_definitions_v1(d.organization_id)
      )
  )
);

create unique index if not exists workflow_execution_events_v2_document_request_uq
  on public.workflow_execution_events_v2(
    execution_id,(details->>'request_key')
  )
  where event_type='document_evidence_submitted'
    and nullif(details->>'request_key','') is not null;

create or replace function public.prepare_workflow_document_upload_v1(
  p_task_id uuid,
  p_original_filename text,
  p_mime_type text,
  p_size_bytes bigint,
  p_request_key text
)
returns table(
  document_id uuid,
  storage_path text,
  document_status text,
  task_status text,
  execution_status text,
  created_new boolean
)
language plpgsql
security definer
set search_path=public,pg_temp
as $workflow_document_prepare$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_filename text:=nullif(btrim(p_original_filename),'');
  v_mime text:=lower(nullif(btrim(p_mime_type),''));
  v_ext text;
  v_task public.tenant_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_document public.workflow_execution_documents_v2;
  v_doc_id uuid;
  v_path text;
  v_requires_accept boolean:=false;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_document_request_key_invalid' using errcode='22023';
  end if;
  if v_filename is null or length(v_filename)>255 then
    raise exception 'workflow_document_filename_invalid' using errcode='22023';
  end if;
  if p_size_bytes is null or p_size_bytes<1 or p_size_bytes>10485760 then
    raise exception 'workflow_document_size_invalid' using errcode='22023';
  end if;

  v_ext:=case v_mime
    when 'application/pdf' then 'pdf'
    when 'image/jpeg' then 'jpg'
    when 'image/png' then 'png'
    when 'image/webp' then 'webp'
    else null
  end;
  if v_ext is null then
    raise exception 'workflow_document_mime_invalid' using errcode='22023';
  end if;

  select * into v_task
  from public.tenant_tasks_v2
  where id=p_task_id
  for update;

  if v_task.id is null
    or v_task.task_type<>'workflow'
    or v_task.source_kind<>'workflow_execution'
    or v_task.source_id is null then
    raise exception 'workflow_task_required' using errcode='22023';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_task.source_id
  for update;

  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  if v_task.organization_id<>v_execution.organization_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id
    or v_task.property_id is distinct from v_execution.property_id
    or v_task.room_id is distinct from v_execution.room_id
    or v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_identity_mismatch' using errcode='55000';
  end if;

  if v_actor is distinct from v_execution.assigned_user_id
    or v_actor is distinct from v_task.assigned_user_id then
    raise exception 'workflow_document_actor_forbidden' using errcode='42501';
  end if;

  if not coalesce((v_execution.spec_snapshot#>>'{steps,document}')::boolean,false) then
    raise exception 'workflow_document_not_configured' using errcode='22023';
  end if;

  select * into v_document
  from public.workflow_execution_documents_v2 d
  where d.execution_id=v_execution.id
    and d.request_key=v_key
  for update;

  if v_document.id is not null then
    if v_document.task_id is distinct from v_task.id
      or v_document.original_filename is distinct from v_filename
      or v_document.mime_type is distinct from v_mime
      or v_document.size_bytes is distinct from p_size_bytes then
      raise exception 'workflow_document_request_key_conflict' using errcode='55000';
    end if;

    return query
    select v_document.id,v_document.storage_path,v_document.status,
           v_task.status,v_execution.status,false;
    return;
  end if;

  v_requires_accept:=coalesce((v_execution.spec_snapshot#>>'{steps,accept}')::boolean,false);
  if v_requires_accept and v_task.status='pending' then
    raise exception 'workflow_document_accept_required' using errcode='55000';
  end if;

  if v_task.status not in ('pending','active') then
    raise exception 'workflow_document_not_actionable' using errcode='55000';
  end if;

  if not v_requires_accept and v_task.status='pending' then
    update public.tenant_tasks_v2
    set status='active',updated_at=now()
    where id=v_task.id
    returning * into v_task;

    update public.workflow_executions_v2 e
    set status='active',
        updated_at=now(),
        started_at=coalesce(e.started_at,now())
    where e.id=v_execution.id
    returning * into v_execution;

    insert into public.tenant_task_history_v2(
      task_id,action_key,action_label,from_status,to_status,note,actor_user_id
    ) values (
      v_task.id,'start_document','Iniciar documento',
      'pending','active',null,v_actor
    );

    insert into public.workflow_execution_events_v2(
      execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
    ) values (
      v_execution.id,v_execution.organization_id,'document_step_started',
      'pending','active',v_actor,
      jsonb_build_object('task_id',v_task.id,'request_key',v_key)
    );
  elsif v_task.status<>'active' then
    raise exception 'workflow_document_not_actionable' using errcode='55000';
  end if;

  v_doc_id:=gen_random_uuid();
  v_path:=v_execution.organization_id::text||'/'||
          v_execution.id::text||'/'||
          v_doc_id::text||'.'||v_ext;

  insert into public.workflow_execution_documents_v2(
    id,execution_id,task_id,organization_id,uploaded_by,
    original_filename,mime_type,size_bytes,storage_path,request_key,status
  ) values (
    v_doc_id,v_execution.id,v_task.id,v_execution.organization_id,v_actor,
    v_filename,v_mime,p_size_bytes,v_path,v_key,'uploading'
  )
  returning * into v_document;

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,v_execution.organization_id,'document_upload_prepared',
    v_execution.status,v_execution.status,v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'document_id',v_document.id,
      'request_key',v_key,
      'mime_type',v_mime,
      'size_bytes',p_size_bytes
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,v_actor,'workflow_document_upload_prepared',
    'workflow_execution',v_execution.id::text,'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'document_id',v_document.id,
      'mime_type',v_mime,
      'size_bytes',p_size_bytes
    )
  );

  return query
  select v_document.id,v_document.storage_path,v_document.status,
         v_task.status,v_execution.status,true;
end;
$workflow_document_prepare$;

revoke all on function public.prepare_workflow_document_upload_v1(uuid,text,text,bigint,text)
  from public,anon;
grant execute on function public.prepare_workflow_document_upload_v1(uuid,text,text,bigint,text)
  to authenticated;

create or replace function public.submit_workflow_document_v1(
  p_document_id uuid,
  p_request_key text
)
returns table(
  document_id uuid,
  document_status text,
  all_documents_complete boolean,
  task_status text,
  execution_status text,
  applied_new boolean
)
language plpgsql
security definer
set search_path=public,storage,pg_temp
as $workflow_document_submit$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_document public.workflow_execution_documents_v2;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_previous public.workflow_execution_events_v2;
  v_photo_complete boolean:=true;
  v_checklist_complete boolean:=true;
  v_document_complete boolean:=false;
  v_all_complete boolean:=false;
  v_close_type text;
  v_from_status text;
  v_target_status text;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_document_request_key_invalid' using errcode='22023';
  end if;

  select * into v_document
  from public.workflow_execution_documents_v2
  where id=p_document_id
  for update;

  if v_document.id is null then
    raise exception 'workflow_document_not_found' using errcode='P0002';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_document.execution_id
  for update;

  select * into v_task
  from public.tenant_tasks_v2
  where id=v_document.task_id
  for update;

  if v_execution.id is null or v_task.id is null then
    raise exception 'workflow_document_execution_not_ready' using errcode='55000';
  end if;

  if v_task.source_kind<>'workflow_execution'
    or v_task.source_id is distinct from v_execution.id
    or v_task.organization_id<>v_execution.organization_id
    or v_document.organization_id<>v_execution.organization_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id
    or v_task.status is distinct from v_execution.status then
    raise exception 'workflow_document_identity_mismatch' using errcode='55000';
  end if;

  if v_actor is distinct from v_document.uploaded_by
    or v_actor is distinct from v_execution.assigned_user_id
    or v_actor is distinct from v_task.assigned_user_id then
    raise exception 'workflow_document_actor_forbidden' using errcode='42501';
  end if;

  if not coalesce((v_execution.spec_snapshot#>>'{steps,document}')::boolean,false) then
    raise exception 'workflow_document_not_configured' using errcode='22023';
  end if;

  select * into v_previous
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='document_evidence_submitted'
    and ev.details->>'request_key'=v_key
  order by ev.id
  limit 1;

  if v_previous.id is not null then
    if v_previous.details->>'document_id' is distinct from v_document.id::text then
      raise exception 'workflow_document_request_key_conflict' using errcode='55000';
    end if;

    select exists(
      select 1 from public.workflow_execution_documents_v2 d
      where d.execution_id=v_execution.id and d.status='submitted'
    ) into v_document_complete;

    return query
    select v_document.id,v_document.status,v_document_complete,
           v_task.status,v_execution.status,false;
    return;
  end if;

  if v_document.status='submitted' then
    select exists(
      select 1 from public.workflow_execution_documents_v2 d
      where d.execution_id=v_execution.id and d.status='submitted'
    ) into v_document_complete;

    return query
    select v_document.id,v_document.status,v_document_complete,
           v_task.status,v_execution.status,false;
    return;
  end if;

  if v_document.status<>'uploading'
    or v_task.status<>'active'
    or v_execution.status<>'active' then
    raise exception 'workflow_document_not_actionable' using errcode='55000';
  end if;

  if not exists(
    select 1
    from storage.objects o
    where o.bucket_id='workflow-documents-v2'
      and o.name=v_document.storage_path
      and o.owner_id=v_actor::text
  ) then
    raise exception 'workflow_document_object_missing' using errcode='55000';
  end if;

  v_from_status:=v_execution.status;

  update public.workflow_execution_documents_v2
  set status='submitted',
      submitted_at=coalesce(submitted_at,now())
  where id=v_document.id
  returning * into v_document;

  select exists(
    select 1
    from public.workflow_execution_documents_v2 d
    where d.execution_id=v_execution.id
      and d.status='submitted'
  ) into v_document_complete;

  if coalesce((v_execution.spec_snapshot#>>'{steps,photo}')::boolean,false) then
    select exists(
      select 1
      from public.workflow_execution_photo_resources_v2 r
      where r.execution_id=v_execution.id
    ) and not exists(
      select 1
      from public.workflow_execution_photo_resources_v2 r
      where r.execution_id=v_execution.id
        and r.status<>'submitted'
    ) into v_photo_complete;
  end if;

  if coalesce((v_execution.spec_snapshot#>>'{steps,checklist}')::boolean,false) then
    select
      jsonb_typeof(v_execution.checklist_state)='array'
      and jsonb_array_length(v_execution.checklist_state)>0
      and not exists(
        select 1
        from jsonb_array_elements(v_execution.checklist_state) item
        where coalesce((item->>'required')::boolean,true)
          and not coalesce((item->>'completed')::boolean,false)
      )
    into v_checklist_complete;
  end if;

  v_all_complete:=v_document_complete and v_photo_complete and v_checklist_complete;
  v_close_type:=nullif(v_execution.spec_snapshot->>'closeType','');
  v_target_status:=v_execution.status;

  if v_all_complete then
    if v_close_type='auto' then
      v_target_status:='completed';
    elsif v_close_type='human_review' then
      v_target_status:='waiting_review';
    end if;
  end if;

  if v_target_status is distinct from v_execution.status then
    update public.tenant_tasks_v2
    set status=v_target_status,updated_at=now()
    where id=v_task.id
    returning * into v_task;

    update public.workflow_executions_v2 e
    set status=v_target_status,
        updated_at=now(),
        started_at=coalesce(e.started_at,now()),
        completed_at=case
          when v_target_status='completed' then coalesce(e.completed_at,now())
          else e.completed_at
        end
    where id=v_execution.id
    returning * into v_execution;
  end if;

  insert into public.tenant_task_history_v2(
    task_id,action_key,action_label,from_status,to_status,note,actor_user_id
  ) values (
    v_task.id,
    'document_submitted',
    case
      when v_target_status='completed' then 'Documento adjuntado y tarea completada'
      when v_target_status='waiting_review' then 'Documento adjuntado y enviado a revisión'
      else 'Documento adjuntado'
    end,
    v_from_status,
    v_target_status,
    v_document.original_filename,
    v_actor
  );

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,v_execution.organization_id,'document_evidence_submitted',
    v_from_status,v_target_status,v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'document_id',v_document.id,
      'request_key',v_key,
      'mime_type',v_document.mime_type,
      'size_bytes',v_document.size_bytes,
      'all_documents_complete',v_document_complete,
      'photo_complete',v_photo_complete,
      'checklist_complete',v_checklist_complete
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,v_actor,'workflow_document_evidence_submitted',
    'workflow_execution',v_execution.id::text,'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'document_id',v_document.id,
      'mime_type',v_document.mime_type,
      'size_bytes',v_document.size_bytes,
      'task_status',v_task.status,
      'execution_status',v_execution.status
    )
  );

  return query
  select v_document.id,v_document.status,v_document_complete,
         v_task.status,v_execution.status,true;
end;
$workflow_document_submit$;

revoke all on function public.submit_workflow_document_v1(uuid,text)
  from public,anon;
grant execute on function public.submit_workflow_document_v1(uuid,text)
  to authenticated;

-- Checklist debe considerar Documento satisfecho si ya existe al menos uno submitted.
create or replace function public.set_workflow_checklist_item_v1(
  p_task_id uuid,
  p_item_key text,
  p_completed boolean,
  p_request_key text
)
returns table(
  task_id uuid,
  task_status text,
  execution_id uuid,
  execution_status text,
  checklist_state jsonb,
  all_required_complete boolean,
  applied_new boolean
)
language plpgsql
security definer
set search_path=public,pg_temp
as $workflow_checklist_apply$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_item_key text:=nullif(btrim(p_item_key),'');
  v_task public.tenant_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_previous public.workflow_execution_events_v2;
  v_item jsonb;
  v_item_index integer;
  v_new_state jsonb;
  v_all_required boolean:=false;
  v_photo_complete boolean:=true;
  v_document_pending boolean:=false;
  v_close_type text;
  v_target_status text;
  v_from_status text;
  v_requires_accept boolean:=false;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_checklist_request_key_invalid' using errcode='22023';
  end if;
  if v_item_key is null or length(v_item_key)>80 then
    raise exception 'workflow_checklist_item_key_invalid' using errcode='22023';
  end if;
  if p_completed is null then
    raise exception 'workflow_checklist_completed_invalid' using errcode='22023';
  end if;

  select * into v_task
  from public.tenant_tasks_v2
  where id=p_task_id
  for update;

  if v_task.id is null
    or v_task.task_type<>'workflow'
    or v_task.source_kind<>'workflow_execution'
    or v_task.source_id is null then
    raise exception 'workflow_task_required' using errcode='22023';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_task.source_id
  for update;

  if v_execution.id is null then
    raise exception 'workflow_execution_not_found' using errcode='P0002';
  end if;

  if v_task.organization_id<>v_execution.organization_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id
    or v_task.property_id is distinct from v_execution.property_id
    or v_task.room_id is distinct from v_execution.room_id
    or v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_identity_mismatch' using errcode='55000';
  end if;

  if v_actor is distinct from v_execution.assigned_user_id then
    raise exception 'workflow_checklist_actor_forbidden' using errcode='42501';
  end if;

  if not coalesce((v_execution.spec_snapshot#>>'{steps,checklist}')::boolean,false) then
    raise exception 'workflow_checklist_not_configured' using errcode='22023';
  end if;

  -- Idempotency receipts are checked before current actionability so a retry
  -- can recover a transition that already closed the task.
  select * into v_previous
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='checklist_item_changed'
    and ev.details->>'request_key'=v_key
  order by ev.id
  limit 1;

  if v_previous.id is not null then
    if v_previous.details->>'item_key' is distinct from v_item_key
      or coalesce((v_previous.details->>'completed')::boolean,false) is distinct from p_completed then
      raise exception 'workflow_checklist_request_key_conflict' using errcode='55000';
    end if;

    select not exists(
      select 1 from jsonb_array_elements(v_execution.checklist_state) item
      where coalesce((item->>'required')::boolean,true)
        and not coalesce((item->>'completed')::boolean,false)
    ) into v_all_required;

    return query
    select v_task.id,v_task.status,v_execution.id,v_execution.status,
           v_execution.checklist_state,v_all_required,false;
    return;
  end if;

  v_requires_accept:=coalesce((v_execution.spec_snapshot#>>'{steps,accept}')::boolean,false);
  if v_requires_accept and v_task.status='pending' then
    raise exception 'workflow_checklist_accept_required' using errcode='55000';
  end if;
  if v_task.status not in ('pending','active') then
    raise exception 'workflow_checklist_not_actionable' using errcode='55000';
  end if;

  select value,ord::integer
  into v_item,v_item_index
  from jsonb_array_elements(v_execution.checklist_state) with ordinality as x(value,ord)
  where value->>'key'=v_item_key
  limit 1;

  if v_item is null then
    raise exception 'workflow_checklist_item_not_found' using errcode='P0002';
  end if;

  if coalesce((v_item->>'completed')::boolean,false)=p_completed then
    -- A semantic no-op still gets an idempotency receipt so retries remain safe.
    v_new_state:=v_execution.checklist_state;
  else
    select coalesce(jsonb_agg(
      case
        when ord=v_item_index then
          jsonb_set(
            jsonb_set(
              jsonb_set(value,'{completed}',to_jsonb(p_completed),true),
              '{completedAt}',
              case when p_completed then to_jsonb(now()) else 'null'::jsonb end,
              true
            ),
            '{completedBy}',
            case when p_completed then to_jsonb(v_actor::text) else 'null'::jsonb end,
            true
          )
        else value
      end
      order by ord
    ),'[]'::jsonb)
    into v_new_state
    from jsonb_array_elements(v_execution.checklist_state) with ordinality as x(value,ord);
  end if;

  select not exists(
    select 1 from jsonb_array_elements(v_new_state) item
    where coalesce((item->>'required')::boolean,true)
      and not coalesce((item->>'completed')::boolean,false)
  ) into v_all_required;

  if coalesce((v_execution.spec_snapshot#>>'{steps,photo}')::boolean,false) then
    select exists(
      select 1
      from public.workflow_execution_photo_resources_v2 r
      where r.execution_id=v_execution.id
    ) and not exists(
      select 1
      from public.workflow_execution_photo_resources_v2 r
      where r.execution_id=v_execution.id
        and r.status<>'submitted'
    ) into v_photo_complete;
  end if;

  v_document_pending:=
    coalesce((v_execution.spec_snapshot#>>'{steps,document}')::boolean,false)
    and not exists(
      select 1
      from public.workflow_execution_documents_v2 d
      where d.execution_id=v_execution.id
        and d.status='submitted'
    );
  v_close_type:=nullif(v_execution.spec_snapshot->>'closeType','');
  v_from_status:=v_execution.status;
  v_target_status:=v_execution.status;

  if v_all_required and v_photo_complete and not v_document_pending then
    if v_close_type='auto' then
      v_target_status:='completed';
    elsif v_close_type='human_review' then
      v_target_status:='waiting_review';
    end if;
  elsif v_target_status='pending' then
    v_target_status:='active';
  end if;

  update public.workflow_executions_v2 e
  set checklist_state=v_new_state,
      status=v_target_status,
      updated_at=now(),
      started_at=coalesce(e.started_at,now()),
      completed_at=case
        when v_target_status='completed' then coalesce(e.completed_at,now())
        else e.completed_at
      end
  where e.id=v_execution.id
  returning * into v_execution;

  if v_task.status is distinct from v_target_status then
    update public.tenant_tasks_v2
    set status=v_target_status,updated_at=now()
    where id=v_task.id
    returning * into v_task;
  end if;

  insert into public.tenant_task_history_v2(
    task_id,action_key,action_label,from_status,to_status,note,actor_user_id
  ) values (
    v_task.id,
    case when p_completed then 'checklist_item_completed' else 'checklist_item_reopened' end,
    case when p_completed then 'Elemento de checklist completado' else 'Elemento de checklist reabierto' end,
    v_from_status,
    v_target_status,
    nullif(v_item->>'text',''),
    v_actor
  );

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,v_execution.organization_id,'checklist_item_changed',
    v_from_status,v_target_status,v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'item_key',v_item_key,
      'item_text',v_item->>'text',
      'required',coalesce((v_item->>'required')::boolean,true),
      'completed',p_completed,
      'all_required_complete',v_all_required,
      'photo_complete',v_photo_complete,
      'document_pending',v_document_pending,
      'request_key',v_key
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,v_actor,'workflow_checklist_item_changed',
    'workflow_execution',v_execution.id::text,'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'item_key',v_item_key,
      'completed',p_completed,
      'task_status',v_task.status,
      'execution_status',v_execution.status
    )
  );

  return query
  select v_task.id,v_task.status,v_execution.id,v_execution.status,
         v_execution.checklist_state,v_all_required,true;
end;
$workflow_checklist_apply$;

revoke all on function public.set_workflow_checklist_item_v1(uuid,text,boolean,text)
  from public,anon;
grant execute on function public.set_workflow_checklist_item_v1(uuid,text,boolean,text)
  to authenticated;

-- Foto + Checklist deben cerrar en cualquier orden. La foto deja de considerar
-- "checklist configurado" como pendiente cuando los obligatorios ya están completos.
create or replace function public.submit_workflow_photo_verification_v1(
  p_run_id uuid,
  p_item_id uuid,
  p_request_key text
)
returns table(
  photo_resource_id uuid,
  photo_resource_status text,
  all_photos_complete boolean,
  task_status text,
  execution_status text,
  applied_new boolean
)
language plpgsql
security definer
set search_path=public,storage,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_run public.photo_verification_runs_v2;
  v_item public.photo_verification_items_v2;
  v_resource public.workflow_execution_photo_resources_v2;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_previous_event public.workflow_execution_events_v2;
  v_expected_path text;
  v_all_complete boolean:=false;
  v_other_steps boolean:=false;
  v_close_type text;
  v_target_status text;
  v_from_status text;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_photo_request_key_invalid' using errcode='22023';
  end if;

  select * into v_run
  from public.photo_verification_runs_v2
  where id=p_run_id
  for update;

  if v_run.id is null
    or v_run.source_type<>'workflow_execution'
    or v_run.source_id is null then
    raise exception 'workflow_photo_run_not_found' using errcode='P0002';
  end if;

  select * into v_resource
  from public.workflow_execution_photo_resources_v2
  where photo_run_id=v_run.id
  for update;

  if v_resource.id is null then
    raise exception 'workflow_photo_resource_not_found' using errcode='55000';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_resource.execution_id
  for update;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id
  for update;

  if v_actor is distinct from v_run.actor_user_id
    or v_actor is distinct from v_execution.assigned_user_id
    or v_actor is distinct from v_task.assigned_user_id then
    raise exception 'workflow_photo_actor_forbidden' using errcode='42501';
  end if;

  if v_run.source_id is distinct from v_execution.id
    or v_run.organization_id<>v_execution.organization_id
    or v_run.property_id<>v_execution.property_id
    or v_resource.pattern_id is null then
    raise exception 'workflow_photo_identity_mismatch' using errcode='55000';
  end if;

  if v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_state_mismatch' using errcode='55000';
  end if;

  v_from_status:=v_execution.status;

  select * into v_previous_event
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='photo_evidence_submitted'
    and ev.details->>'request_key'=v_key
  order by ev.id
  limit 1;

  if v_previous_event.id is not null then
    if v_previous_event.details->>'photo_resource_id' is distinct from v_resource.id::text
      or v_previous_event.details->>'photo_run_id' is distinct from p_run_id::text
      or v_previous_event.details->>'item_id' is distinct from p_item_id::text then
      raise exception 'workflow_photo_request_key_conflict' using errcode='55000';
    end if;

    select not exists(
      select 1 from public.workflow_execution_photo_resources_v2 er
      where er.execution_id=v_execution.id and er.status<>'submitted'
    ) into v_all_complete;

    return query
    select v_resource.id,v_resource.status,v_all_complete,v_task.status,v_execution.status,false;
    return;
  end if;

  if v_run.status='submitted' and v_resource.status='submitted' then
    select not exists(
      select 1 from public.workflow_execution_photo_resources_v2 er
      where er.execution_id=v_execution.id and er.status<>'submitted'
    ) into v_all_complete;

    return query
    select v_resource.id,v_resource.status,v_all_complete,v_task.status,v_execution.status,false;
    return;
  end if;

  if v_run.status<>'capturing' or v_resource.status<>'capturing' then
    raise exception 'workflow_photo_not_capturing' using errcode='55000';
  end if;

  select * into v_item
  from public.photo_verification_items_v2
  where id=p_item_id
    and run_id=v_run.id;

  if v_item.id is null
    or v_item.pattern_id is distinct from v_resource.pattern_id then
    raise exception 'workflow_photo_item_invalid' using errcode='22023';
  end if;

  v_expected_path:=v_run.organization_id::text||'/'||v_run.id::text||'/'||v_item.id::text||'.jpg';
  if v_item.storage_path is distinct from v_expected_path then
    raise exception 'workflow_photo_storage_path_invalid' using errcode='55000';
  end if;

  if not exists(
    select 1
    from storage.objects o
    where o.bucket_id='photo-verification'
      and o.name=v_expected_path
      and o.owner_id=v_actor::text
  ) then
    raise exception 'workflow_photo_object_missing' using errcode='55000';
  end if;

  update public.photo_verification_runs_v2
  set status='submitted',submitted_at=coalesce(submitted_at,now())
  where id=v_run.id
  returning * into v_run;

  update public.workflow_execution_photo_resources_v2
  set status='submitted',completed_at=coalesce(completed_at,now())
  where id=v_resource.id
  returning * into v_resource;

  select not exists(
    select 1
    from public.workflow_execution_photo_resources_v2 er
    where er.execution_id=v_execution.id
      and er.status<>'submitted'
  ) into v_all_complete;

  v_target_status:=v_execution.status;

  if v_all_complete then
    v_other_steps:=
      coalesce((v_execution.spec_snapshot->'steps'->>'document')::boolean,false)
      or (
        coalesce((v_execution.spec_snapshot->'steps'->>'checklist')::boolean,false)
        and (
          jsonb_typeof(v_execution.checklist_state)<>'array'
          or jsonb_array_length(v_execution.checklist_state)=0
          or exists(
            select 1
            from jsonb_array_elements(v_execution.checklist_state) item
            where coalesce((item->>'required')::boolean,true)
              and not coalesce((item->>'completed')::boolean,false)
          )
        )
      );
    v_close_type:=nullif(v_execution.spec_snapshot->>'closeType','');

    if not v_other_steps then
      if v_close_type='auto' then
        v_target_status:='completed';
      elsif v_close_type='human_review' then
        v_target_status:='waiting_review';
      end if;
    end if;
  end if;

  if v_target_status is distinct from v_execution.status then
    insert into public.tenant_task_history_v2(
      task_id,action_key,action_label,from_status,to_status,note,actor_user_id
    ) values (
      v_task.id,
      'photo_complete',
      case
        when v_target_status='completed' then 'Evidencia fotográfica completada'
        when v_target_status='waiting_review' then 'Evidencia fotográfica enviada a revisión'
        else 'Evidencia fotográfica'
      end,
      v_task.status,
      v_target_status,
      null,
      v_actor
    );

    update public.tenant_tasks_v2
    set status=v_target_status,updated_at=now()
    where id=v_task.id
    returning * into v_task;

    update public.workflow_executions_v2 as updated_execution
    set status=v_target_status,
        updated_at=now(),
        started_at=coalesce(updated_execution.started_at,now()),
        completed_at=case
          when v_target_status='completed' then coalesce(updated_execution.completed_at,now())
          else updated_execution.completed_at
        end
    where id=v_execution.id
    returning * into v_execution;
  end if;

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,
    v_execution.organization_id,
    'photo_evidence_submitted',
    v_from_status,
    v_execution.status,
    v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'photo_resource_id',v_resource.id,
      'photo_run_id',v_run.id,
      'item_id',v_item.id,
      'pattern_id',v_resource.pattern_id,
      'request_key',v_key,
      'all_photos_complete',v_all_complete
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,
    v_actor,
    'workflow_photo_evidence_submitted',
    'workflow_execution',
    v_execution.id::text,
    'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'photo_resource_id',v_resource.id,
      'photo_run_id',v_run.id,
      'item_id',v_item.id,
      'pattern_id',v_resource.pattern_id,
      'all_photos_complete',v_all_complete,
      'task_status',v_task.status,
      'execution_status',v_execution.status
    )
  );

  return query
  select v_resource.id,v_resource.status,v_all_complete,v_task.status,v_execution.status,true;
end;
$$;

-- Foto debe considerar Documento satisfecho si ya existe al menos uno submitted.
create or replace function public.submit_workflow_photo_verification_v1(
  p_run_id uuid,
  p_item_id uuid,
  p_request_key text
)
returns table(
  photo_resource_id uuid,
  photo_resource_status text,
  all_photos_complete boolean,
  task_status text,
  execution_status text,
  applied_new boolean
)
language plpgsql
security definer
set search_path=public,storage,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_run public.photo_verification_runs_v2;
  v_item public.photo_verification_items_v2;
  v_resource public.workflow_execution_photo_resources_v2;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_previous_event public.workflow_execution_events_v2;
  v_expected_path text;
  v_all_complete boolean:=false;
  v_other_steps boolean:=false;
  v_close_type text;
  v_target_status text;
  v_from_status text;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if v_key is null or length(v_key)>200 then
    raise exception 'workflow_photo_request_key_invalid' using errcode='22023';
  end if;

  select * into v_run
  from public.photo_verification_runs_v2
  where id=p_run_id
  for update;

  if v_run.id is null
    or v_run.source_type<>'workflow_execution'
    or v_run.source_id is null then
    raise exception 'workflow_photo_run_not_found' using errcode='P0002';
  end if;

  select * into v_resource
  from public.workflow_execution_photo_resources_v2
  where photo_run_id=v_run.id
  for update;

  if v_resource.id is null then
    raise exception 'workflow_photo_resource_not_found' using errcode='55000';
  end if;

  select * into v_execution
  from public.workflow_executions_v2
  where id=v_resource.execution_id
  for update;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id
  for update;

  if v_actor is distinct from v_run.actor_user_id
    or v_actor is distinct from v_execution.assigned_user_id
    or v_actor is distinct from v_task.assigned_user_id then
    raise exception 'workflow_photo_actor_forbidden' using errcode='42501';
  end if;

  if v_run.source_id is distinct from v_execution.id
    or v_run.organization_id<>v_execution.organization_id
    or v_run.property_id<>v_execution.property_id
    or v_resource.pattern_id is null then
    raise exception 'workflow_photo_identity_mismatch' using errcode='55000';
  end if;

  if v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_state_mismatch' using errcode='55000';
  end if;

  v_from_status:=v_execution.status;

  select * into v_previous_event
  from public.workflow_execution_events_v2 ev
  where ev.execution_id=v_execution.id
    and ev.event_type='photo_evidence_submitted'
    and ev.details->>'request_key'=v_key
  order by ev.id
  limit 1;

  if v_previous_event.id is not null then
    if v_previous_event.details->>'photo_resource_id' is distinct from v_resource.id::text
      or v_previous_event.details->>'photo_run_id' is distinct from p_run_id::text
      or v_previous_event.details->>'item_id' is distinct from p_item_id::text then
      raise exception 'workflow_photo_request_key_conflict' using errcode='55000';
    end if;

    select not exists(
      select 1 from public.workflow_execution_photo_resources_v2 er
      where er.execution_id=v_execution.id and er.status<>'submitted'
    ) into v_all_complete;

    return query
    select v_resource.id,v_resource.status,v_all_complete,v_task.status,v_execution.status,false;
    return;
  end if;

  if v_run.status='submitted' and v_resource.status='submitted' then
    select not exists(
      select 1 from public.workflow_execution_photo_resources_v2 er
      where er.execution_id=v_execution.id and er.status<>'submitted'
    ) into v_all_complete;

    return query
    select v_resource.id,v_resource.status,v_all_complete,v_task.status,v_execution.status,false;
    return;
  end if;

  if v_run.status<>'capturing' or v_resource.status<>'capturing' then
    raise exception 'workflow_photo_not_capturing' using errcode='55000';
  end if;

  select * into v_item
  from public.photo_verification_items_v2
  where id=p_item_id
    and run_id=v_run.id;

  if v_item.id is null
    or v_item.pattern_id is distinct from v_resource.pattern_id then
    raise exception 'workflow_photo_item_invalid' using errcode='22023';
  end if;

  v_expected_path:=v_run.organization_id::text||'/'||v_run.id::text||'/'||v_item.id::text||'.jpg';
  if v_item.storage_path is distinct from v_expected_path then
    raise exception 'workflow_photo_storage_path_invalid' using errcode='55000';
  end if;

  if not exists(
    select 1
    from storage.objects o
    where o.bucket_id='photo-verification'
      and o.name=v_expected_path
      and o.owner_id=v_actor::text
  ) then
    raise exception 'workflow_photo_object_missing' using errcode='55000';
  end if;

  update public.photo_verification_runs_v2
  set status='submitted',submitted_at=coalesce(submitted_at,now())
  where id=v_run.id
  returning * into v_run;

  update public.workflow_execution_photo_resources_v2
  set status='submitted',completed_at=coalesce(completed_at,now())
  where id=v_resource.id
  returning * into v_resource;

  select not exists(
    select 1
    from public.workflow_execution_photo_resources_v2 er
    where er.execution_id=v_execution.id
      and er.status<>'submitted'
  ) into v_all_complete;

  v_target_status:=v_execution.status;

  if v_all_complete then
    v_other_steps:=
      (
        coalesce((v_execution.spec_snapshot->'steps'->>'document')::boolean,false)
        and not exists(
          select 1
          from public.workflow_execution_documents_v2 d
          where d.execution_id=v_execution.id
            and d.status='submitted'
        )
      )
      or (
        coalesce((v_execution.spec_snapshot->'steps'->>'checklist')::boolean,false)
        and (
          jsonb_typeof(v_execution.checklist_state)<>'array'
          or jsonb_array_length(v_execution.checklist_state)=0
          or exists(
            select 1
            from jsonb_array_elements(v_execution.checklist_state) item
            where coalesce((item->>'required')::boolean,true)
              and not coalesce((item->>'completed')::boolean,false)
          )
        )
      );
    v_close_type:=nullif(v_execution.spec_snapshot->>'closeType','');

    if not v_other_steps then
      if v_close_type='auto' then
        v_target_status:='completed';
      elsif v_close_type='human_review' then
        v_target_status:='waiting_review';
      end if;
    end if;
  end if;

  if v_target_status is distinct from v_execution.status then
    insert into public.tenant_task_history_v2(
      task_id,action_key,action_label,from_status,to_status,note,actor_user_id
    ) values (
      v_task.id,
      'photo_complete',
      case
        when v_target_status='completed' then 'Evidencia fotográfica completada'
        when v_target_status='waiting_review' then 'Evidencia fotográfica enviada a revisión'
        else 'Evidencia fotográfica'
      end,
      v_task.status,
      v_target_status,
      null,
      v_actor
    );

    update public.tenant_tasks_v2
    set status=v_target_status,updated_at=now()
    where id=v_task.id
    returning * into v_task;

    update public.workflow_executions_v2 as updated_execution
    set status=v_target_status,
        updated_at=now(),
        started_at=coalesce(updated_execution.started_at,now()),
        completed_at=case
          when v_target_status='completed' then coalesce(updated_execution.completed_at,now())
          else updated_execution.completed_at
        end
    where id=v_execution.id
    returning * into v_execution;
  end if;

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,
    v_execution.organization_id,
    'photo_evidence_submitted',
    v_from_status,
    v_execution.status,
    v_actor,
    jsonb_build_object(
      'task_id',v_task.id,
      'photo_resource_id',v_resource.id,
      'photo_run_id',v_run.id,
      'item_id',v_item.id,
      'pattern_id',v_resource.pattern_id,
      'request_key',v_key,
      'all_photos_complete',v_all_complete
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,
    v_actor,
    'workflow_photo_evidence_submitted',
    'workflow_execution',
    v_execution.id::text,
    'success',
    jsonb_build_object(
      'task_id',v_task.id,
      'photo_resource_id',v_resource.id,
      'photo_run_id',v_run.id,
      'item_id',v_item.id,
      'pattern_id',v_resource.pattern_id,
      'all_photos_complete',v_all_complete,
      'task_status',v_task.status,
      'execution_status',v_execution.status
    )
  );

  return query
  select v_resource.id,v_resource.status,v_all_complete,v_task.status,v_execution.status,true;
end;
$$;

comment on table public.workflow_execution_documents_v2 is
  'Evidencia documental privada adjuntada a una ejecución de workflow. Un documento submitted satisface el paso Documento.';
comment on function public.prepare_workflow_document_upload_v1(uuid,text,text,bigint,text) is
  'Prepara de forma idempotente una ruta privada de Storage para el documento de una tarea workflow.';
comment on function public.submit_workflow_document_v1(uuid,text) is
  'Confirma el objeto de Storage y sincroniza Documento con Foto/Checklist y el cierre de tarea+ejecución.';
