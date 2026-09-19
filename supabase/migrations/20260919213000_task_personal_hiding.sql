-- GestionPisos · ocultamiento personal de tarjetas de Tareas
-- EMPLEADOS, INQUILINOS y PROPIETARIOS pueden ocultar de su propia bandeja
-- tareas terminales que les son visibles. No altera la tarea global ni su histórico.

create table if not exists public.tenant_task_personal_hidden_v1(
  task_id uuid not null references public.tenant_tasks_v2(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key(task_id,user_id)
);

create index if not exists tenant_task_personal_hidden_user_idx
  on public.tenant_task_personal_hidden_v1(user_id,hidden_at desc);

alter table public.tenant_task_personal_hidden_v1 enable row level security;
revoke all on table public.tenant_task_personal_hidden_v1 from public,anon,authenticated;
grant select,insert,delete on table public.tenant_task_personal_hidden_v1 to service_role;

create or replace function private.task_personal_hide_allowed_v1(
  p_task public.tenant_tasks_v2,
  p_actor uuid
)
returns boolean
language sql
stable
security definer
set search_path=''
as $task_personal_hide_allowed$
  select
    p_actor is not null
    and p_task.removed_at is null
    and p_task.assigned_user_id=p_actor
    and p_task.status in ('completed','cancelled','failed','rejected','refunded','held')
    and (
      exists(
        select 1
        from public.user_roles ur
        where ur.user_id=p_actor
          and ur.organization_id=p_task.organization_id
          and ur.revoked_at is null
          and ur.role in ('employee','tenant','owner')
      )
      or exists(
        select 1
        from public.owners o
        where o.user_id=p_actor
          and o.organization_id=p_task.organization_id
          and o.status='active'
          and o.archived_at is null
      )
      or exists(
        select 1
        from public.tenants_v2 tn
        where tn.user_id=p_actor
          and tn.organization_id=p_task.organization_id
          and tn.status='active'
          and tn.archived_at is null
      )
    );
$task_personal_hide_allowed$;

revoke all on function private.task_personal_hide_allowed_v1(public.tenant_tasks_v2,uuid)
  from public,anon,authenticated;

create or replace function public.hide_my_task_card_v1(
  p_task_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=''
as $hide_my_task_card$
declare
  v_actor uuid:=auth.uid();
  v_task public.tenant_tasks_v2;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select *
  into v_task
  from public.tenant_tasks_v2
  where id=p_task_id
  for share;

  if v_task.id is null then
    raise exception 'task_not_found' using errcode='P0002';
  end if;

  if not private.task_personal_hide_allowed_v1(v_task,v_actor) then
    if v_task.status not in ('completed','cancelled','failed','rejected','refunded','held') then
      raise exception 'task_hide_requires_terminal' using errcode='55000';
    end if;
    raise exception 'task_hide_forbidden' using errcode='42501';
  end if;

  insert into public.tenant_task_personal_hidden_v1(task_id,user_id,hidden_at)
  values(v_task.id,v_actor,now())
  on conflict(task_id,user_id) do nothing;

  return true;
end;
$hide_my_task_card$;

revoke all on function public.hide_my_task_card_v1(uuid)
  from public,anon;
grant execute on function public.hide_my_task_card_v1(uuid)
  to authenticated;

create or replace function public.unhide_my_task_card_v1(
  p_task_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=''
as $unhide_my_task_card$
declare
  v_actor uuid:=auth.uid();
  v_count integer;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  delete from public.tenant_task_personal_hidden_v1
  where task_id=p_task_id
    and user_id=v_actor;

  get diagnostics v_count=row_count;
  return v_count>0;
end;
$unhide_my_task_card$;

revoke all on function public.unhide_my_task_card_v1(uuid)
  from public,anon;
grant execute on function public.unhide_my_task_card_v1(uuid)
  to authenticated;

create or replace function public.list_my_hidden_task_cards_v1()
returns table(
  task_id uuid,
  hidden_at timestamptz
)
language sql
stable
security definer
set search_path=''
as $list_my_hidden_task_cards$
  select h.task_id,h.hidden_at
  from public.tenant_task_personal_hidden_v1 h
  where auth.uid() is not null
    and h.user_id=auth.uid()
  order by h.hidden_at desc;
$list_my_hidden_task_cards$;

revoke all on function public.list_my_hidden_task_cards_v1()
  from public,anon;
grant execute on function public.list_my_hidden_task_cards_v1()
  to authenticated;

comment on table public.tenant_task_personal_hidden_v1 is
  'Preferencia personal: oculta una tarjeta terminal solo de la bandeja del usuario.';
comment on function public.hide_my_task_card_v1(uuid) is
  'Oculta de la bandeja propia una tarea terminal asignada al empleado, inquilino o propietario actual.';
comment on function public.unhide_my_task_card_v1(uuid) is
  'Restaura una tarjeta previamente ocultada por el usuario actual.';
