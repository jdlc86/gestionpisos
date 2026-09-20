-- Suspensión -> Alta debe restaurar ocupación + rol + acceso en una sola transacción.
begin;

select set_config('gestionpisos.reactivate.org','11111111-1111-4111-8111-111111111111',true);
select set_config('gestionpisos.reactivate.root','22222222-2222-4222-8222-222222222222',true);
select set_config('gestionpisos.reactivate.owner',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.property',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.room',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.user','99999999-9999-4999-8999-999999999903',true);
select set_config('gestionpisos.reactivate.tenant',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.blocked_occ',gen_random_uuid()::text,true);

insert into auth.users(id) values
  (current_setting('gestionpisos.reactivate.user')::uuid)
on conflict(id) do nothing;

insert into public.owners(id,organization_id,full_name,status)
values(
  current_setting('gestionpisos.reactivate.owner')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  'Reactivation regression owner',
  'active'
);

insert into public.properties_v2(
  id,organization_id,owner_id,name,address_line,status
) values(
  current_setting('gestionpisos.reactivate.property')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  current_setting('gestionpisos.reactivate.owner')::uuid,
  'Reactivation regression property',
  'Regression only',
  'active'
);

insert into public.rooms_v2(id,property_id,label,status)
values(
  current_setting('gestionpisos.reactivate.room')::uuid,
  current_setting('gestionpisos.reactivate.property')::uuid,
  'Reactivation room',
  'active'
);

insert into public.user_roles(user_id,organization_id,role,revoked_at)
values(
  current_setting('gestionpisos.reactivate.user')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  'tenant',
  now()
);

insert into public.tenants_v2(
  id,organization_id,user_id,full_name,document_type,document_number,email,status
) values(
  current_setting('gestionpisos.reactivate.tenant')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  current_setting('gestionpisos.reactivate.user')::uuid,
  'Suspended tenant',
  'dni',
  'REACTIVATE-ONE',
  'reactivate@example.invalid',
  'blocked'
);

insert into public.occupancies_v2(
  id,organization_id,tenant_id,property_id,room_id,occupant_email,
  starts_on,ends_on,status,user_id,suspended_at
) values(
  current_setting('gestionpisos.reactivate.blocked_occ')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  current_setting('gestionpisos.reactivate.tenant')::uuid,
  current_setting('gestionpisos.reactivate.property')::uuid,
  current_setting('gestionpisos.reactivate.room')::uuid,
  'reactivate@example.invalid',
  null,
  null,
  'blocked',
  current_setting('gestionpisos.reactivate.user')::uuid,
  now()
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.reactivate.root'),
    'role','authenticated',
    'app_metadata',jsonb_build_object('role','root')
  )::text,
  true
);

select public.reactivate_tenant_occupancy_v1(
  current_setting('gestionpisos.reactivate.blocked_occ')::uuid,
  current_setting('gestionpisos.reactivate.property')::uuid,
  current_setting('gestionpisos.reactivate.room')::uuid,
  'Suspended tenant',
  'dni',
  'REACTIVATE-ONE',
  'reactivate@example.invalid',
  current_date,
  null,
  true
);

reset role;

do $reactivated_state$
declare
  v_new_occ uuid;
begin
  if not exists(
    select 1 from public.occupancies_v2
    where id=current_setting('gestionpisos.reactivate.blocked_occ')::uuid
      and status='archived'
      and starts_on is null
      and ends_on is null
  ) then
    raise exception 'suspended occupancy was not archived';
  end if;

  select id into v_new_occ
  from public.occupancies_v2
  where tenant_id=current_setting('gestionpisos.reactivate.tenant')::uuid
    and id<>current_setting('gestionpisos.reactivate.blocked_occ')::uuid
    and status='active'
    and starts_on=current_date
    and ends_on is null
    and user_id=current_setting('gestionpisos.reactivate.user')::uuid;

  if v_new_occ is null then
    raise exception 'reactivation did not create linked active occupancy';
  end if;

  if not exists(
    select 1 from public.tenants_v2
    where id=current_setting('gestionpisos.reactivate.tenant')::uuid
      and status='active'
      and archived_at is null
  ) then
    raise exception 'reactivation did not activate canonical tenant';
  end if;

  if not exists(
    select 1 from public.user_roles
    where user_id=current_setting('gestionpisos.reactivate.user')::uuid
      and organization_id=current_setting('gestionpisos.reactivate.org')::uuid
      and role='tenant'
      and revoked_at is null
  ) then
    raise exception 'reactivation did not restore tenant role';
  end if;

  if not exists(
    select 1 from public.audit_log_v2
    where action='tenant_occupancy_reactivated'
      and entity_id=current_setting('gestionpisos.reactivate.tenant')
  ) then
    raise exception 'reactivation was not audited';
  end if;

  if not exists(
    select 1 from public.audit_log_v2
    where action='tenant_platform_access_reactivated'
      and entity_id=current_setting('gestionpisos.reactivate.tenant')
  ) then
    raise exception 'platform access restoration was not audited';
  end if;
end;
$reactivated_state$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.reactivate.user'),
    'role','authenticated',
    'app_metadata',jsonb_build_object(
      'role','tenant',
      'organization_id',current_setting('gestionpisos.reactivate.org')
    )
  )::text,
  true
);

do $reactivated_login_gate$
begin
  if public.has_current_platform_access_v1() is distinct from true then
    raise exception 'reactivated tenant still lacks platform access';
  end if;
end;
$reactivated_login_gate$;

reset role;
rollback;
