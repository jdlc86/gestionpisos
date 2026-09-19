-- Tareas · ocultamiento personal por usuario.
-- PostgreSQL desechable. Todo se revierte.

begin;

select set_config(
  'gestionpisos.personal_hide.org',
  (select id::text from public.organizations order by id limit 1),
  true
);
select set_config(
  'gestionpisos.personal_hide.root',
  (select user_id::text from public.user_roles where role='root' and revoked_at is null limit 1),
  true
);

select set_config('gestionpisos.personal_hide.employee','55555555-5555-4555-8555-555555555555',true);
select set_config('gestionpisos.personal_hide.owner','66666666-6666-4666-8666-666666666666',true);
select set_config('gestionpisos.personal_hide.tenant_user','77777777-7777-4777-8777-777777777777',true);
select set_config('gestionpisos.personal_hide.tenant',gen_random_uuid()::text,true);
select set_config('gestionpisos.personal_hide.employee_done',gen_random_uuid()::text,true);
select set_config('gestionpisos.personal_hide.employee_open',gen_random_uuid()::text,true);
select set_config('gestionpisos.personal_hide.owner_done',gen_random_uuid()::text,true);
select set_config('gestionpisos.personal_hide.tenant_done',gen_random_uuid()::text,true);
select set_config('gestionpisos.personal_hide.unassigned_done',gen_random_uuid()::text,true);

do $prerequisites$
begin
  if nullif(current_setting('gestionpisos.personal_hide.org',true),'') is null
    or nullif(current_setting('gestionpisos.personal_hide.root',true),'') is null then
    raise exception 'personal task hiding prerequisites missing';
  end if;
end;
$prerequisites$;

insert into auth.users(id)
values
  (current_setting('gestionpisos.personal_hide.employee')::uuid),
  (current_setting('gestionpisos.personal_hide.owner')::uuid),
  (current_setting('gestionpisos.personal_hide.tenant_user')::uuid)
on conflict(id) do nothing;

insert into public.user_roles(user_id,organization_id,role)
values (
  current_setting('gestionpisos.personal_hide.employee')::uuid,
  current_setting('gestionpisos.personal_hide.org')::uuid,
  'employee'
)
on conflict do nothing;

insert into public.owners(
  organization_id,user_id,full_name,email,status
) values (
  current_setting('gestionpisos.personal_hide.org')::uuid,
  current_setting('gestionpisos.personal_hide.owner')::uuid,
  'Personal hide owner',
  'personal-hide-owner@example.invalid',
  'active'
);

insert into public.tenants_v2(
  id,organization_id,user_id,full_name,document_type,document_number,email,status
) values (
  current_setting('gestionpisos.personal_hide.tenant')::uuid,
  current_setting('gestionpisos.personal_hide.org')::uuid,
  current_setting('gestionpisos.personal_hide.tenant_user')::uuid,
  'Personal hide tenant',
  'other',
  'PERSONAL-HIDE-TENANT',
  'personal-hide-tenant@example.invalid',
  'active'
);

insert into public.tenant_tasks_v2(
  id,organization_id,tenant_id,task_type,origin,title,status,assigned_user_id,created_by
) values
(
  current_setting('gestionpisos.personal_hide.employee_done')::uuid,
  current_setting('gestionpisos.personal_hide.org')::uuid,
  current_setting('gestionpisos.personal_hide.tenant')::uuid,
  'generic','manual','Employee terminal task','completed',
  current_setting('gestionpisos.personal_hide.employee')::uuid,
  current_setting('gestionpisos.personal_hide.root')::uuid
),
(
  current_setting('gestionpisos.personal_hide.employee_open')::uuid,
  current_setting('gestionpisos.personal_hide.org')::uuid,
  current_setting('gestionpisos.personal_hide.tenant')::uuid,
  'generic','manual','Employee open task','pending',
  current_setting('gestionpisos.personal_hide.employee')::uuid,
  current_setting('gestionpisos.personal_hide.root')::uuid
),
(
  current_setting('gestionpisos.personal_hide.owner_done')::uuid,
  current_setting('gestionpisos.personal_hide.org')::uuid,
  current_setting('gestionpisos.personal_hide.tenant')::uuid,
  'generic','manual','Owner terminal task','completed',
  current_setting('gestionpisos.personal_hide.owner')::uuid,
  current_setting('gestionpisos.personal_hide.root')::uuid
),
(
  current_setting('gestionpisos.personal_hide.tenant_done')::uuid,
  current_setting('gestionpisos.personal_hide.org')::uuid,
  current_setting('gestionpisos.personal_hide.tenant')::uuid,
  'generic','manual','Tenant terminal task','completed',
  current_setting('gestionpisos.personal_hide.tenant_user')::uuid,
  current_setting('gestionpisos.personal_hide.root')::uuid
),
(
  current_setting('gestionpisos.personal_hide.unassigned_done')::uuid,
  current_setting('gestionpisos.personal_hide.org')::uuid,
  null,
  'generic','manual','Unassigned terminal task','completed',
  null,
  current_setting('gestionpisos.personal_hide.root')::uuid
);

do $grants$
begin
  if has_function_privilege('anon','public.hide_my_task_card_v1(uuid)','execute') then
    raise exception 'anon can hide personal task cards';
  end if;
  if has_function_privilege('anon','public.unhide_my_task_card_v1(uuid)','execute') then
    raise exception 'anon can restore personal task cards';
  end if;
  if has_function_privilege('anon','public.list_my_hidden_task_cards_v1()','execute') then
    raise exception 'anon can list personal hidden task cards';
  end if;
  if not has_function_privilege('authenticated','public.hide_my_task_card_v1(uuid)','execute') then
    raise exception 'authenticated cannot invoke guarded personal hide';
  end if;
  if has_table_privilege('authenticated','public.tenant_task_personal_hidden_v1','select') then
    raise exception 'authenticated can read personal hidden table directly';
  end if;
end;
$grants$;

-- EMPLEADO: puede ocultar su tarea cerrada, pero no una abierta ni una ajena.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.personal_hide.employee'),
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

do $employee_hide$
begin
  if public.hide_my_task_card_v1(
    current_setting('gestionpisos.personal_hide.employee_done')::uuid
  ) is distinct from true then
    raise exception 'employee terminal task was not hidden';
  end if;
end;
$employee_hide$;

do $employee_open_blocked$
begin
  perform public.hide_my_task_card_v1(
    current_setting('gestionpisos.personal_hide.employee_open')::uuid
  );
  raise exception 'employee open task hide unexpectedly succeeded';
exception
  when sqlstate '55000' then
    if sqlerrm<>'task_hide_requires_terminal' then raise; end if;
end;
$employee_open_blocked$;

do $employee_foreign_denied$
begin
  perform public.hide_my_task_card_v1(
    current_setting('gestionpisos.personal_hide.owner_done')::uuid
  );
  raise exception 'employee foreign task hide unexpectedly succeeded';
exception
  when sqlstate '42501' then
    if sqlerrm<>'task_hide_forbidden' then raise; end if;
end;
$employee_foreign_denied$;

do $employee_list$
begin
  if (
    select count(*)
    from public.list_my_hidden_task_cards_v1()
    where task_id=current_setting('gestionpisos.personal_hide.employee_done')::uuid
  )<>1 then
    raise exception 'employee hidden task missing from personal list';
  end if;
end;
$employee_list$;

reset role;

-- PROPIETARIO: puede ocultar una tarea terminal expresamente asignada.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.personal_hide.owner'),
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

select public.hide_my_task_card_v1(
  current_setting('gestionpisos.personal_hide.owner_done')::uuid
);

do $owner_isolated$
begin
  if (
    select count(*)
    from public.list_my_hidden_task_cards_v1()
  )<>1 then
    raise exception 'owner personal hidden list leaked another user';
  end if;
end;
$owner_isolated$;

reset role;

-- INQUILINO: puede ocultar una tarea terminal asignada a su identidad.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.personal_hide.tenant_user'),
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

select public.hide_my_task_card_v1(
  current_setting('gestionpisos.personal_hide.tenant_done')::uuid
);

do $tenant_unrelated_denied$
begin
  perform public.hide_my_task_card_v1(
    current_setting('gestionpisos.personal_hide.unassigned_done')::uuid
  );
  raise exception 'tenant unrelated task hide unexpectedly succeeded';
exception
  when sqlstate '42501' then
    if sqlerrm<>'task_hide_forbidden' then raise; end if;
end;
$tenant_unrelated_denied$;

do $tenant_restore$
begin
  if public.unhide_my_task_card_v1(
    current_setting('gestionpisos.personal_hide.tenant_done')::uuid
  ) is distinct from true then
    raise exception 'tenant hidden task was not restored';
  end if;

  if public.unhide_my_task_card_v1(
    current_setting('gestionpisos.personal_hide.tenant_done')::uuid
  ) is distinct from false then
    raise exception 'tenant restore retry was not idempotent';
  end if;
end;
$tenant_restore$;

reset role;

do $global_tasks_preserved$
begin
  if (
    select count(*)
    from public.tenant_tasks_v2
    where id in (
      current_setting('gestionpisos.personal_hide.employee_done')::uuid,
      current_setting('gestionpisos.personal_hide.owner_done')::uuid,
      current_setting('gestionpisos.personal_hide.tenant_done')::uuid
    )
      and removed_at is null
      and status='completed'
  )<>3 then
    raise exception 'personal hiding modified global task records';
  end if;

  if (
    select count(*)
    from public.tenant_task_personal_hidden_v1
    where task_id=current_setting('gestionpisos.personal_hide.employee_done')::uuid
      and user_id=current_setting('gestionpisos.personal_hide.employee')::uuid
  )<>1 then
    raise exception 'employee personal hidden row missing';
  end if;

  if (
    select count(*)
    from public.tenant_task_personal_hidden_v1
    where task_id=current_setting('gestionpisos.personal_hide.owner_done')::uuid
      and user_id=current_setting('gestionpisos.personal_hide.owner')::uuid
  )<>1 then
    raise exception 'owner personal hidden row missing';
  end if;

  if exists(
    select 1
    from public.tenant_task_personal_hidden_v1
    where task_id=current_setting('gestionpisos.personal_hide.tenant_done')::uuid
      and user_id=current_setting('gestionpisos.personal_hide.tenant_user')::uuid
  ) then
    raise exception 'tenant restored task remains hidden';
  end if;
end;
$global_tasks_preserved$;

rollback;
