-- GestionPisos · Flujos de Trabajo · notificaciones operativas transversales
-- Reutiliza notifications_v2. No crea un motor de notificaciones paralelo.
--
-- Semántica:
--   notifications.onCreate=true -> avisar al asignado cuando nace la ejecución/tarea.
--   notifications.onClose=true  -> avisar a creador + asignado al completed/rejected.
--   channel_in_app=true, channel_email=false en esta primera integración.
--   correlación genérica source_kind/source_id/event_key evita duplicados.

alter table public.notifications_v2
  add column if not exists source_kind text,
  add column if not exists source_id uuid,
  add column if not exists event_key text;

alter table public.notifications_v2
  drop constraint if exists notifications_source_correlation_check;

alter table public.notifications_v2
  add constraint notifications_source_correlation_check
  check (
    (source_kind is null and source_id is null and event_key is null)
    or (
      nullif(btrim(source_kind),'') is not null
      and source_id is not null
      and nullif(btrim(event_key),'') is not null
    )
  ) not valid;

alter table public.notifications_v2
  validate constraint notifications_source_correlation_check;

create unique index if not exists notifications_v2_source_event_recipient_uq
  on public.notifications_v2(source_kind,source_id,event_key,recipient_user_id)
  where source_kind is not null
    and source_id is not null
    and event_key is not null;

create index if not exists notifications_v2_source_lookup_idx
  on public.notifications_v2(source_kind,source_id,created_at desc)
  where source_kind is not null
    and source_id is not null;

create schema if not exists private;

create or replace function private.workflow_execution_notifications_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $workflow_notifications$
declare
  v_flow_name text;
  v_notify_create boolean:=false;
  v_notify_close boolean:=false;
  v_event_type text;
  v_event_key text;
  v_title text;
  v_body text;
begin
  v_flow_name:=left(
    coalesce(
      nullif(btrim(new.spec_snapshot->>'flowName'),''),
      'Flujo'
    ),
    120
  );

  v_notify_create:=coalesce(
    (new.spec_snapshot#>>'{notifications,onCreate}')::boolean,
    false
  );
  v_notify_close:=coalesce(
    (new.spec_snapshot#>>'{notifications,onClose}')::boolean,
    false
  );

  if tg_op='INSERT' then
    if v_notify_create and new.assigned_user_id is not null then
      insert into public.notifications_v2(
        organization_id,
        recipient_user_id,
        event_type,
        title,
        body,
        status,
        channel_in_app,
        channel_email,
        source_kind,
        source_id,
        event_key
      ) values (
        new.organization_id,
        new.assigned_user_id,
        'workflow_task_created',
        left('Nueva tarea · '||v_flow_name,200),
        'Se te ha asignado una nueva tarea de flujo.',
        'pending',
        true,
        false,
        'workflow_execution',
        new.id,
        'created'
      )
      on conflict (source_kind,source_id,event_key,recipient_user_id)
      where source_kind is not null
        and source_id is not null
        and event_key is not null
      do nothing;
    end if;

    return new;
  end if;

  if tg_op='UPDATE'
    and old.status is distinct from new.status
    and new.status in ('completed','rejected')
    and v_notify_close then

    if new.status='completed' then
      v_event_type:='workflow_completed';
      v_event_key:='completed';
      v_title:=left('Flujo completado · '||v_flow_name,200);
      v_body:='La ejecución ha finalizado correctamente.';
    else
      v_event_type:='workflow_rejected';
      v_event_key:='rejected';
      v_title:=left('Flujo rechazado · '||v_flow_name,200);
      v_body:='La ejecución se cerró como rechazada. Revisa Historial para consultar el motivo.';
    end if;

    insert into public.notifications_v2(
      organization_id,
      recipient_user_id,
      event_type,
      title,
      body,
      status,
      channel_in_app,
      channel_email,
      source_kind,
      source_id,
      event_key
    )
    select
      new.organization_id,
      recipients.user_id,
      v_event_type,
      v_title,
      v_body,
      'pending',
      true,
      false,
      'workflow_execution',
      new.id,
      v_event_key
    from (
      select distinct user_id
      from unnest(array[new.created_by,new.assigned_user_id]) as recipient(user_id)
      where user_id is not null
    ) recipients
    on conflict (source_kind,source_id,event_key,recipient_user_id)
    where source_kind is not null
      and source_id is not null
      and event_key is not null
    do nothing;
  end if;

  return new;
end;
$workflow_notifications$;

revoke all on function private.workflow_execution_notifications_v1()
  from public,anon,authenticated;

drop trigger if exists workflow_execution_notifications_v1
  on public.workflow_executions_v2;

create trigger workflow_execution_notifications_v1
after insert or update of status
on public.workflow_executions_v2
for each row
execute function private.workflow_execution_notifications_v1();

comment on function private.workflow_execution_notifications_v1() is
  'Emite notificaciones in-app idempotentes para creación y cierre de ejecuciones workflow usando notifications_v2.';
