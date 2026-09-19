-- GestionPisos · eliminación segura de tarjetas de Tareas
-- La UI llama "Eliminar" a retirar una tarjeta de la bandeja operativa.
-- El registro, historial, ejecución y evidencias se conservan para auditoría.

alter table public.tenant_tasks_v2
  add column if not exists removed_at timestamptz,
  add column if not exists removed_by uuid references auth.users(id) on delete set null;

alter table public.tenant_tasks_v2
  drop constraint if exists tenant_tasks_v2_removal_shape_check;

alter table public.tenant_tasks_v2
  add constraint tenant_tasks_v2_removal_shape_check
  check (
    (removed_at is null and removed_by is null)
    or (removed_at is not null and removed_by is not null)
  ) not valid;

alter table public.tenant_tasks_v2
  validate constraint tenant_tasks_v2_removal_shape_check;

create index if not exists tenant_tasks_v2_active_created_idx
  on public.tenant_tasks_v2(created_at desc)
  where removed_at is null;

create or replace function public.delete_task_card_v1(
  p_task_id uuid
)
returns table(
  task_id uuid,
  removed_new boolean
)
language plpgsql
security definer
set search_path=''
as $delete_task_card$
declare
  v_actor uuid:=auth.uid();
  v_task public.tenant_tasks_v2;
  v_execution_status text;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select *
  into v_task
  from public.tenant_tasks_v2
  where id=p_task_id
  for update;

  if v_task.id is null then
    raise exception 'task_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_task.organization_id) then
    raise exception 'task_delete_forbidden' using errcode='42501';
  end if;

  if v_task.removed_at is not null then
    return query select v_task.id,false;
    return;
  end if;

  if v_task.status not in (
    'completed','cancelled','failed','rejected','refunded','held'
  ) then
    raise exception 'task_delete_requires_terminal' using errcode='55000';
  end if;

  if v_task.source_kind='workflow_execution' and v_task.source_id is not null then
    select e.status
    into v_execution_status
    from public.workflow_executions_v2 e
    where e.id=v_task.source_id;

    if v_execution_status is not null
      and v_execution_status not in ('completed','cancelled','failed','rejected') then
      raise exception 'task_delete_execution_not_terminal' using errcode='55000';
    end if;
  end if;

  update public.tenant_tasks_v2
  set removed_at=now(),
      removed_by=v_actor,
      updated_at=now()
  where id=v_task.id;

  return query select v_task.id,true;
end;
$delete_task_card$;

revoke all on function public.delete_task_card_v1(uuid)
  from public,anon;
grant execute on function public.delete_task_card_v1(uuid)
  to authenticated;

comment on column public.tenant_tasks_v2.removed_at is
  'Retira la tarjeta de la bandeja operativa sin borrar historial, ejecución ni evidencias.';
comment on function public.delete_task_card_v1(uuid) is
  'Elimina visualmente una tarea terminal para ROOT/ADMIN conservando íntegramente su trazabilidad.';
