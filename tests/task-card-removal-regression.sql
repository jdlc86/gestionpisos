-- Tareas · regresión de eliminación segura de tarjetas.
-- PostgreSQL desechable. Todo se revierte.

begin;

select set_config(
  'gestionpisos.task_remove.org',
  (select id::text from public.organizations where name='Allaiso' limit 1),
  true
);
select set_config(
  'gestionpisos.task_remove.root',
  (select user_id::text from public.user_roles where role='root' and revoked_at is null limit 1),
  true
);
select set_config('gestionpisos.task_remove.tenant',gen_random_uuid()::text,true);
select set_config('gestionpisos.task_remove.done',gen_random_uuid()::text,true);
select set_config('gestionpisos.task_remove.pending',gen_random_uuid()::text,true);
select set_config('gestionpisos.task_remove.denied',gen_random_uuid()::text,true);

do $prerequisites$
begin
  if nullif(current_setting('gestionpisos.task_remove.org',true),'') is null
    or nullif(current_setting('gestionpisos.task_remove.root',true),'') is null then
    raise exception 'task removal prerequisites missing';
  end if;
end;
$prerequisites$;

insert into auth.users(id)
values ('44444444-4444-4444-8444-444444444444')
on conflict(id) do nothing;

insert into public.user_roles(user_id,organization_id,role)
values (
  '44444444-4444-4444-8444-444444444444',
  current_setting('gestionpisos.task_remove.org')::uuid,
  'employee'
)
on conflict do nothing;

insert into public.tenants_v2(
  id,organization_id,full_name,document_type,document_number,email,status
) values (
  current_setting('gestionpisos.task_remove.tenant')::uuid,
  current_setting('gestionpisos.task_remove.org')::uuid,
  'Task removal regression',
  'other',
  'REMOVE-TEST-001',
  'task-removal-regression@example.invalid',
  'active'
);

insert into public.tenant_tasks_v2(
  id,organization_id,tenant_id,task_type,origin,title,status,created_by
) values
(
  current_setting('gestionpisos.task_remove.done')::uuid,
  current_setting('gestionpisos.task_remove.org')::uuid,
  current_setting('gestionpisos.task_remove.tenant')::uuid,
  'generic','manual','Terminal task card','completed',
  current_setting('gestionpisos.task_remove.root')::uuid
),
(
  current_setting('gestionpisos.task_remove.pending')::uuid,
  current_setting('gestionpisos.task_remove.org')::uuid,
  current_setting('gestionpisos.task_remove.tenant')::uuid,
  'generic','manual','Open task card','pending',
  current_setting('gestionpisos.task_remove.root')::uuid
),
(
  current_setting('gestionpisos.task_remove.denied')::uuid,
  current_setting('gestionpisos.task_remove.org')::uuid,
  current_setting('gestionpisos.task_remove.tenant')::uuid,
  'generic','manual','Manager only task card','completed',
  current_setting('gestionpisos.task_remove.root')::uuid
);

insert into public.tenant_task_history_v2(
  task_id,action_key,action_label,from_status,to_status,actor_user_id
) values (
  current_setting('gestionpisos.task_remove.done')::uuid,
  'complete','Completada','pending','completed',
  current_setting('gestionpisos.task_remove.root')::uuid
);

do $privileges$
begin
  if has_function_privilege('anon','public.delete_task_card_v1(uuid)','execute') then
    raise exception 'anon can remove task cards';
  end if;
  if not has_function_privilege('authenticated','public.delete_task_card_v1(uuid)','execute') then
    raise exception 'authenticated cannot invoke guarded task removal';
  end if;
end;
$privileges$;

-- Un empleado autenticado no puede retirar tarjetas.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','44444444-4444-4444-8444-444444444444',
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

do $employee_denied$
begin
  perform public.delete_task_card_v1(
    current_setting('gestionpisos.task_remove.denied')::uuid
  );
  raise exception 'employee task removal unexpectedly succeeded';
exception
  when sqlstate '42501' then
    if sqlerrm<>'task_delete_forbidden' then raise; end if;
end;
$employee_denied$;

reset role;

-- Incluso ROOT debe completar MFA antes de retirar una tarjeta.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.task_remove.root'),
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

do $root_aal1_denied$
begin
  perform public.delete_task_card_v1(
    current_setting('gestionpisos.task_remove.done')::uuid
  );
  raise exception 'aal1 root task removal unexpectedly succeeded';
exception
  when sqlstate '42501' then
    if sqlerrm<>'aal2_required' then raise; end if;
end;
$root_aal1_denied$;

reset role;

-- ROOT retira una tarea cerrada.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.task_remove.root'),
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

do $remove_terminal$
declare
  v_result record;
begin
  select * into v_result
  from public.delete_task_card_v1(
    current_setting('gestionpisos.task_remove.done')::uuid
  );

  if v_result.removed_new is distinct from true then
    raise exception 'terminal task was not removed';
  end if;

  select * into v_result
  from public.delete_task_card_v1(
    current_setting('gestionpisos.task_remove.done')::uuid
  );

  if v_result.removed_new is distinct from false then
    raise exception 'task removal retry was not idempotent';
  end if;
end;
$remove_terminal$;

-- Una tarea operativa abierta nunca puede desaparecer.
do $open_task_blocked$
begin
  perform public.delete_task_card_v1(
    current_setting('gestionpisos.task_remove.pending')::uuid
  );
  raise exception 'open task removal unexpectedly succeeded';
exception
  when sqlstate '55000' then
    if sqlerrm<>'task_delete_requires_terminal' then raise; end if;
end;
$open_task_blocked$;

reset role;

do $preserves_audit$
begin
  if not exists(
    select 1
    from public.tenant_tasks_v2
    where id=current_setting('gestionpisos.task_remove.done')::uuid
      and removed_at is not null
      and removed_by=current_setting('gestionpisos.task_remove.root')::uuid
      and status='completed'
  ) then
    raise exception 'removed task record/audit marker missing';
  end if;

  if not exists(
    select 1
    from public.tenant_task_history_v2
    where task_id=current_setting('gestionpisos.task_remove.done')::uuid
      and action_key='complete'
  ) then
    raise exception 'task removal destroyed task history';
  end if;

  if (
    select count(*)
    from public.audit_log_v2
    where organization_id=current_setting('gestionpisos.task_remove.org')::uuid
      and actor_user_id=current_setting('gestionpisos.task_remove.root')::uuid
      and action='task_card_removed'
      and entity_type='tenant_task'
      and entity_id=current_setting('gestionpisos.task_remove.done')
      and result='success'
  )<>1 then
    raise exception 'task removal audit event missing or duplicated';
  end if;

  if exists(
    select 1
    from public.tenant_tasks_v2
    where id=current_setting('gestionpisos.task_remove.pending')::uuid
      and removed_at is not null
  ) then
    raise exception 'open task received removal marker';
  end if;
end;
$preserves_audit$;

rollback;
