-- GestionPisos · WF-03 · una única comunicación final para Limpieza auditada
-- El informe agregado de limpieza es la comunicación final del asignado cuando
-- existe un expediente de auditoría final. La notificación genérica de cierre
-- puede seguir llegando al creador/gestor si es una persona distinta.
-- Rechazos tempranos sin auditoría conservan la notificación workflow normal.

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
  v_cleaning_final_report boolean:=false;
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

    -- Solo se suprime el cierre genérico del asignado cuando ya existe el
    -- informe final especializado. Un rechazo previo a fotos/auditoría no entra aquí.
    if coalesce(new.spec_snapshot->>'flowType','')='cleaning'
      and coalesce(new.spec_snapshot->>'closeType','')='domain_adapter'
      and new.assigned_user_id is not null then
      select exists(
        select 1
        from public.cleaning_tasks_v2 ct
        join public.cleaning_audits_v2 ca
          on ca.cleaning_task_id=ct.id
        where ct.workflow_execution_id=new.id
          and ca.status in ('not_selected','closed','expired')
          and ca.report_status in ('ready','sent')
      )
      into v_cleaning_final_report;
    end if;

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
        and not (
          v_cleaning_final_report
          and user_id=new.assigned_user_id
        )
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
  from public,anon,authenticated,service_role;

comment on function private.workflow_execution_notifications_v1() is
  'Emite notificaciones workflow y evita duplicar el cierre del asignado cuando Limpieza ya genera su informe agregado final.';
