-- Suspensión -> Alta debe restaurar ocupación + rol + acceso en una sola transacción.
begin;

select set_config('gestionpisos.reactivate.org','11111111-1111-4111-8111-111111111111',true);
select set_config('gestionpisos.reactivate.root','22222222-2222-4222-8222-222222222222',true);
select set_config('gestionpisos.reactivate.owner',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.property',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.room',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.future_room',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.user','99999999-9999-4999-8999-999999999903',true);
select set_config('gestionpisos.reactivate.user2','99999999-9999-4999-8999-999999999904',true);
select set_config('gestionpisos.reactivate.future_user','99999999-9999-4999-8999-999999999905',true);
select set_config('gestionpisos.reactivate.tenant',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.tenant2',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.future_tenant',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.blocked_occ',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.blocked_occ2',gen_random_uuid()::text,true);
select set_config('gestionpisos.reactivate.future_blocked_occ',gen_random_uuid()::text,true);

insert into auth.users(id) values
  (current_setting('gestionpisos.reactivate.user')::uuid),
  (current_setting('gestionpisos.reactivate.user2')::uuid),
  (current_setting('gestionpisos.reactivate.future_user')::uuid)
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
values
(
  current_setting('gestionpisos.reactivate.room')::uuid,
  current_setting('gestionpisos.reactivate.property')::uuid,
  'Reactivation room',
  'active'
),
(
  current_setting('gestionpisos.reactivate.future_room')::uuid,
  current_setting('gestionpisos.reactivate.property')::uuid,
  'Future reactivation room',
  'active'
);

insert into public.user_roles(user_id,organization_id,role,revoked_at)
values
(
  current_setting('gestionpisos.reactivate.user')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  'tenant',
  now()
),
(
  current_setting('gestionpisos.reactivate.user2')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  'tenant',
  now()
),
(
  current_setting('gestionpisos.reactivate.future_user')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  'tenant',
  now()
);

insert into public.tenants_v2(
  id,organization_id,user_id,full_name,document_type,document_number,email,status
) values
(
  current_setting('gestionpisos.reactivate.tenant')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  current_setting('gestionpisos.reactivate.user')::uuid,
  'Suspended tenant',
  'dni',
  'REACTIVATE-ONE',
  'reactivate@example.invalid',
  'blocked'
),
(
  current_setting('gestionpisos.reactivate.tenant2')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  current_setting('gestionpisos.reactivate.user2')::uuid,
  'Suspended tenant rollback',
  'dni',
  'REACTIVATE-TWO',
  'reactivate-two@example.invalid',
  'blocked'
),
(
  current_setting('gestionpisos.reactivate.future_tenant')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  current_setting('gestionpisos.reactivate.future_user')::uuid,
  'Future suspended tenant',
  'dni',
  'REACTIVATE-FUTURE',
  'reactivate-future@example.invalid',
  'blocked'
);

insert into public.occupancies_v2(
  id,organization_id,tenant_id,property_id,room_id,occupant_email,
  starts_on,ends_on,status,user_id,suspended_at
) values
(
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
),
(
  current_setting('gestionpisos.reactivate.blocked_occ2')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  current_setting('gestionpisos.reactivate.tenant2')::uuid,
  current_setting('gestionpisos.reactivate.property')::uuid,
  current_setting('gestionpisos.reactivate.room')::uuid,
  'reactivate-two@example.invalid',
  null,
  null,
  'blocked',
  current_setting('gestionpisos.reactivate.user2')::uuid,
  now()
),
(
  current_setting('gestionpisos.reactivate.future_blocked_occ')::uuid,
  current_setting('gestionpisos.reactivate.org')::uuid,
  current_setting('gestionpisos.reactivate.future_tenant')::uuid,
  current_setting('gestionpisos.reactivate.property')::uuid,
  current_setting('gestionpisos.reactivate.future_room')::uuid,
  'reactivate-future@example.invalid',
  null,
  null,
  'blocked',
  current_setting('gestionpisos.reactivate.future_user')::uuid,
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

-- Una reactivación futura prepara identidad/rol, pero no debe conceder acceso
-- antes de starts_on ni fallar por exigir una ocupación vigente hoy.
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

do $future_reactivation$
declare
  v_result jsonb;
begin
  select public.reactivate_tenant_occupancy_v1(
    current_setting('gestionpisos.reactivate.future_blocked_occ')::uuid,
    current_setting('gestionpisos.reactivate.property')::uuid,
    current_setting('gestionpisos.reactivate.future_room')::uuid,
    'Future suspended tenant',
    'dni',
    'REACTIVATE-FUTURE',
    'reactivate-future@example.invalid',
    current_date+1,
    null,
    true
  ) into v_result;

  if coalesce((v_result->>'platform_access_restored')::boolean,false) then
    raise exception 'future reactivation reported current platform access';
  end if;
  if coalesce((v_result->>'platform_access_scheduled')::boolean,false) is distinct from true then
    raise exception 'future reactivation was not marked as scheduled';
  end if;
end;
$future_reactivation$;

reset role;

do $future_state$
begin
  if not exists(
    select 1 from public.occupancies_v2
    where id=current_setting('gestionpisos.reactivate.future_blocked_occ')::uuid
      and status='archived'
  ) then
    raise exception 'future reactivation did not archive suspended occupancy';
  end if;

  if not exists(
    select 1 from public.occupancies_v2
    where tenant_id=current_setting('gestionpisos.reactivate.future_tenant')::uuid
      and id<>current_setting('gestionpisos.reactivate.future_blocked_occ')::uuid
      and status='active'
      and starts_on=current_date+1
      and user_id=current_setting('gestionpisos.reactivate.future_user')::uuid
  ) then
    raise exception 'future reactivation did not create scheduled linked occupancy';
  end if;

  if not exists(
    select 1 from public.user_roles
    where user_id=current_setting('gestionpisos.reactivate.future_user')::uuid
      and organization_id=current_setting('gestionpisos.reactivate.org')::uuid
      and role='tenant'
      and revoked_at is null
  ) then
    raise exception 'future reactivation did not prepare tenant role';
  end if;

  if not exists(
    select 1 from public.audit_log_v2
    where action='tenant_platform_access_scheduled'
      and entity_id=current_setting('gestionpisos.reactivate.future_tenant')
  ) then
    raise exception 'future platform access scheduling was not audited';
  end if;
end;
$future_state$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.reactivate.future_user'),
    'role','authenticated',
    'app_metadata',jsonb_build_object(
      'role','tenant',
      'organization_id',current_setting('gestionpisos.reactivate.org')
    )
  )::text,
  true
);

do $future_login_gate$
begin
  if public.has_current_platform_access_v1() is distinct from false then
    raise exception 'future tenant gained platform access before starts_on';
  end if;
end;
$future_login_gate$;

reset role;

-- Un segundo suspendido intenta reactivarse en la misma habitación/fecha.
-- La exclusión de solape falla DESPUÉS de que la función haya comenzado;
-- toda la sentencia debe retroceder y conservar el estado suspendido.
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

do $overlap_must_rollback$
begin
  begin
    perform public.reactivate_tenant_occupancy_v1(
      current_setting('gestionpisos.reactivate.blocked_occ2')::uuid,
      current_setting('gestionpisos.reactivate.property')::uuid,
      current_setting('gestionpisos.reactivate.room')::uuid,
      'Suspended tenant rollback',
      'dni',
      'REACTIVATE-TWO',
      'reactivate-two@example.invalid',
      current_date,
      null,
      true
    );
    raise exception 'overlapping reactivation unexpectedly succeeded';
  exception
    when exclusion_violation then
      null;
  end;
end;
$overlap_must_rollback$;

reset role;

do $rollback_state$
begin
  if not exists(
    select 1 from public.occupancies_v2
    where id=current_setting('gestionpisos.reactivate.blocked_occ2')::uuid
      and status='blocked'
      and starts_on is null
      and ends_on is null
      and suspended_at is not null
  ) then
    raise exception 'failed reactivation did not preserve suspended occupancy';
  end if;

  if exists(
    select 1 from public.occupancies_v2
    where tenant_id=current_setting('gestionpisos.reactivate.tenant2')::uuid
      and status='active'
  ) then
    raise exception 'failed reactivation leaked an active occupancy';
  end if;

  if not exists(
    select 1 from public.tenants_v2
    where id=current_setting('gestionpisos.reactivate.tenant2')::uuid
      and status='blocked'
  ) then
    raise exception 'failed reactivation did not roll tenant status back';
  end if;

  if not exists(
    select 1 from public.user_roles
    where user_id=current_setting('gestionpisos.reactivate.user2')::uuid
      and organization_id=current_setting('gestionpisos.reactivate.org')::uuid
      and role='tenant'
      and revoked_at is not null
  ) then
    raise exception 'failed reactivation unexpectedly restored tenant role';
  end if;
end;
$rollback_state$;

rollback;
