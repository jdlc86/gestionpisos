-- Tenant offboarding access regression.
-- Reproduce a stale JWT after Baja and prove that DB access is revoked
-- immediately while history remains. Entire fixture rolls back.

begin;

-- Supabase grants authenticated table privileges outside the migration files.
-- The isolated PostgreSQL harness needs the minimum equivalent grants so this
-- regression can exercise RLS rather than fail earlier at table ACL level.
grant select on table
  public.occupancies_v2,
  public.tenants_v2,
  public.tenant_tasks_v2,
  public.user_roles
to authenticated;

select set_config('gestionpisos.offboard.org','11111111-1111-4111-8111-111111111111',true);
select set_config('gestionpisos.offboard.root','22222222-2222-4222-8222-222222222222',true);
select set_config('gestionpisos.offboard.owner',gen_random_uuid()::text,true);
select set_config('gestionpisos.offboard.property',gen_random_uuid()::text,true);
select set_config('gestionpisos.offboard.room1',gen_random_uuid()::text,true);
select set_config('gestionpisos.offboard.room2',gen_random_uuid()::text,true);
select set_config('gestionpisos.offboard.room3',gen_random_uuid()::text,true);
select set_config('gestionpisos.offboard.user1','99999999-9999-4999-8999-999999999901',true);
select set_config('gestionpisos.offboard.user2','99999999-9999-4999-8999-999999999902',true);
select set_config('gestionpisos.offboard.tenant1',gen_random_uuid()::text,true);
select set_config('gestionpisos.offboard.tenant2',gen_random_uuid()::text,true);
select set_config('gestionpisos.offboard.reactivated_occ',gen_random_uuid()::text,true);
select set_config('gestionpisos.offboard.occ1',gen_random_uuid()::text,true);
select set_config('gestionpisos.offboard.occ2a',gen_random_uuid()::text,true);
select set_config('gestionpisos.offboard.occ2b',gen_random_uuid()::text,true);
select set_config('gestionpisos.offboard.task1',gen_random_uuid()::text,true);

insert into auth.users(id) values
  (current_setting('gestionpisos.offboard.user1')::uuid),
  (current_setting('gestionpisos.offboard.user2')::uuid)
on conflict(id) do nothing;

insert into public.owners(id,organization_id,full_name,status)
values(
  current_setting('gestionpisos.offboard.owner')::uuid,
  current_setting('gestionpisos.offboard.org')::uuid,
  'Offboarding regression owner',
  'active'
);

insert into public.properties_v2(
  id,organization_id,owner_id,name,address_line,status
) values(
  current_setting('gestionpisos.offboard.property')::uuid,
  current_setting('gestionpisos.offboard.org')::uuid,
  current_setting('gestionpisos.offboard.owner')::uuid,
  'Offboarding regression property',
  'Regression only',
  'active'
);

insert into public.rooms_v2(id,property_id,label,status) values
(
  current_setting('gestionpisos.offboard.room1')::uuid,
  current_setting('gestionpisos.offboard.property')::uuid,
  'Offboard room 1',
  'active'
),
(
  current_setting('gestionpisos.offboard.room2')::uuid,
  current_setting('gestionpisos.offboard.property')::uuid,
  'Offboard room 2',
  'active'
),
(
  current_setting('gestionpisos.offboard.room3')::uuid,
  current_setting('gestionpisos.offboard.property')::uuid,
  'Offboard room 3',
  'active'
);

insert into public.user_roles(user_id,organization_id,role) values
(
  current_setting('gestionpisos.offboard.user1')::uuid,
  current_setting('gestionpisos.offboard.org')::uuid,
  'tenant'
),
(
  current_setting('gestionpisos.offboard.user2')::uuid,
  current_setting('gestionpisos.offboard.org')::uuid,
  'tenant'
);

insert into public.tenants_v2(
  id,organization_id,user_id,full_name,document_type,document_number,email,status
) values
(
  current_setting('gestionpisos.offboard.tenant1')::uuid,
  current_setting('gestionpisos.offboard.org')::uuid,
  current_setting('gestionpisos.offboard.user1')::uuid,
  'Tenant one',
  'other',
  'OFFBOARD-ONE',
  'tenant-one@example.invalid',
  'active'
),
(
  current_setting('gestionpisos.offboard.tenant2')::uuid,
  current_setting('gestionpisos.offboard.org')::uuid,
  current_setting('gestionpisos.offboard.user2')::uuid,
  'Tenant two shared identity',
  'other',
  'OFFBOARD-TWO',
  'tenant-two@example.invalid',
  'active'
);

insert into public.occupancies_v2(
  id,organization_id,property_id,room_id,occupant_email,starts_on,ends_on,status,user_id,tenant_id
) values
(
  current_setting('gestionpisos.offboard.occ1')::uuid,
  current_setting('gestionpisos.offboard.org')::uuid,
  current_setting('gestionpisos.offboard.property')::uuid,
  current_setting('gestionpisos.offboard.room1')::uuid,
  'tenant-one@example.invalid',
  current_date-10,
  null,
  'active',
  current_setting('gestionpisos.offboard.user1')::uuid,
  current_setting('gestionpisos.offboard.tenant1')::uuid
),
(
  current_setting('gestionpisos.offboard.occ2a')::uuid,
  current_setting('gestionpisos.offboard.org')::uuid,
  current_setting('gestionpisos.offboard.property')::uuid,
  current_setting('gestionpisos.offboard.room2')::uuid,
  'tenant-two@example.invalid',
  current_date-10,
  null,
  'active',
  current_setting('gestionpisos.offboard.user2')::uuid,
  current_setting('gestionpisos.offboard.tenant2')::uuid
),
(
  current_setting('gestionpisos.offboard.occ2b')::uuid,
  current_setting('gestionpisos.offboard.org')::uuid,
  current_setting('gestionpisos.offboard.property')::uuid,
  current_setting('gestionpisos.offboard.room3')::uuid,
  'tenant-two@example.invalid',
  current_date-5,
  null,
  'active',
  current_setting('gestionpisos.offboard.user2')::uuid,
  current_setting('gestionpisos.offboard.tenant2')::uuid
);

insert into public.tenant_tasks_v2(
  id,organization_id,tenant_id,property_id,room_id,task_type,origin,title,status,assigned_user_id
) values(
  current_setting('gestionpisos.offboard.task1')::uuid,
  current_setting('gestionpisos.offboard.org')::uuid,
  current_setting('gestionpisos.offboard.tenant1')::uuid,
  current_setting('gestionpisos.offboard.property')::uuid,
  current_setting('gestionpisos.offboard.room1')::uuid,
  'generic',
  'manual',
  'Stale token task',
  'pending',
  current_setting('gestionpisos.offboard.user1')::uuid
);

-- Before Baja the tenant has normal platform access.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.offboard.user1'),
    'role','authenticated',
    'app_metadata',jsonb_build_object(
      'role','tenant',
      'organization_id',current_setting('gestionpisos.offboard.org')
    )
  )::text,
  true
);

do $before_offboard$
begin
  if public.has_current_platform_access_v1() is distinct from true then
    raise exception 'active tenant unexpectedly lacks platform access';
  end if;
  if (
    select count(*) from public.occupancies_v2
    where id=current_setting('gestionpisos.offboard.occ1')::uuid
  )<>1 then
    raise exception 'active tenant cannot read own occupancy';
  end if;
  if (
    select count(*) from public.tenant_tasks_v2
    where id=current_setting('gestionpisos.offboard.task1')::uuid
  )<>1 then
    raise exception 'active tenant cannot read own task';
  end if;
end;
$before_offboard$;

-- ROOT processes Baja using the normal RPC.
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.offboard.root'),
    'role','authenticated',
    'app_metadata',jsonb_build_object('role','root')
  )::text,
  true
);

select public.offboard_tenant_occupancy_v2(
  current_setting('gestionpisos.offboard.occ1')::uuid,
  current_date+1
);

reset role;

do $wf04_offboarding_event$
begin
  if (
    select count(*) from public.workflow_event_outbox_v2
    where event_type='occupancy.offboarded'
      and source_id=current_setting('gestionpisos.offboard.occ1')::uuid
      and status='pending'
      and payload->>'previousStatus'='active'
  )<>1 then
    raise exception 'Baja did not enqueue exactly one pending offboarding event';
  end if;
end;
$wf04_offboarding_event$;

do $authoritative_state$
begin
  if not exists(
    select 1 from public.occupancies_v2
    where id=current_setting('gestionpisos.offboard.occ1')::uuid
      and status='archived'
      and ends_on=current_date+1
  ) then
    raise exception 'offboarding did not preserve archived occupancy history';
  end if;

  if not exists(
    select 1 from public.tenants_v2
    where id=current_setting('gestionpisos.offboard.tenant1')::uuid
      and status='archived'
      and archived_at is not null
      and deletion_requested_at is not null
      and deletion_requested_by=current_setting('gestionpisos.offboard.root')::uuid
  ) then
    raise exception 'offboarding did not archive tenant identity';
  end if;

  if not exists(
    select 1 from public.user_roles
    where user_id=current_setting('gestionpisos.offboard.user1')::uuid
      and organization_id=current_setting('gestionpisos.offboard.org')::uuid
      and role='tenant'
      and revoked_at is not null
  ) then
    raise exception 'tenant role remained active after final occupancy Baja';
  end if;

  if not exists(
    select 1 from public.audit_log_v2
    where action='tenant_platform_access_revoked'
      and entity_id=current_setting('gestionpisos.offboard.tenant1')
      and actor_user_id=current_setting('gestionpisos.offboard.root')::uuid
  ) then
    raise exception 'tenant platform access revocation was not audited';
  end if;
end;
$authoritative_state$;

-- Same stale tenant JWT: Auth token is syntactically valid, but RLS must deny
-- all gated platform data immediately.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.offboard.user1'),
    'role','authenticated',
    'app_metadata',jsonb_build_object(
      'role','tenant',
      'organization_id',current_setting('gestionpisos.offboard.org')
    )
  )::text,
  true
);

do $stale_jwt_denied$
begin
  if public.has_current_platform_access_v1() is distinct from false then
    raise exception 'stale tenant JWT retained platform access';
  end if;

  if exists(
    select 1 from public.occupancies_v2
    where id=current_setting('gestionpisos.offboard.occ1')::uuid
  ) then
    raise exception 'stale tenant JWT can still read archived occupancy';
  end if;

  if exists(
    select 1 from public.tenants_v2
    where id=current_setting('gestionpisos.offboard.tenant1')::uuid
  ) then
    raise exception 'stale tenant JWT can still read archived tenant identity';
  end if;

  if exists(
    select 1 from public.tenant_tasks_v2
    where id=current_setting('gestionpisos.offboard.task1')::uuid
  ) then
    raise exception 'stale tenant JWT can still read assigned task';
  end if;

  if exists(
    select 1 from public.user_roles
    where user_id=current_setting('gestionpisos.offboard.user1')::uuid
  ) then
    raise exception 'stale tenant JWT can still inspect role history';
  end if;
end;
$stale_jwt_denied$;

-- Returning tenant: a new Alta reuses the same canonical identity/UUID. The
-- backend-only restoration reopens DB access and links the new occupancy.
reset role;
update public.tenants_v2
set status='active',
    archived_at=null,
    deletion_requested_at=null,
    deletion_requested_by=null,
    updated_at=now()
where id=current_setting('gestionpisos.offboard.tenant1')::uuid;

insert into public.occupancies_v2(
  id,organization_id,property_id,room_id,occupant_email,starts_on,ends_on,status,user_id,tenant_id
) values(
  current_setting('gestionpisos.offboard.reactivated_occ')::uuid,
  current_setting('gestionpisos.offboard.org')::uuid,
  current_setting('gestionpisos.offboard.property')::uuid,
  current_setting('gestionpisos.offboard.room1')::uuid,
  'tenant-one@example.invalid',
  current_date,
  null,
  'active',
  null,
  current_setting('gestionpisos.offboard.tenant1')::uuid
);

set local role service_role;
select public.restore_tenant_platform_access_v1(
  current_setting('gestionpisos.offboard.tenant1')::uuid,
  current_setting('gestionpisos.offboard.user1')::uuid,
  current_setting('gestionpisos.offboard.root')::uuid
);
reset role;

do $reactivated_identity$
begin
  if not exists(
    select 1 from public.user_roles
    where user_id=current_setting('gestionpisos.offboard.user1')::uuid
      and organization_id=current_setting('gestionpisos.offboard.org')::uuid
      and role='tenant'
      and revoked_at is null
  ) then
    raise exception 'returning tenant role was not restored';
  end if;

  if not exists(
    select 1 from public.occupancies_v2
    where id=current_setting('gestionpisos.offboard.reactivated_occ')::uuid
      and user_id=current_setting('gestionpisos.offboard.user1')::uuid
  ) then
    raise exception 'returning tenant occupancy was not relinked to Auth identity';
  end if;

  if not exists(
    select 1 from public.audit_log_v2
    where action='tenant_platform_access_reactivated'
      and entity_id=current_setting('gestionpisos.offboard.tenant1')
  ) then
    raise exception 'tenant platform reactivation was not audited';
  end if;
end;
$reactivated_identity$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.offboard.user1'),
    'role','authenticated',
    'app_metadata',jsonb_build_object(
      'role','tenant',
      'organization_id',current_setting('gestionpisos.offboard.org')
    )
  )::text,
  true
);
do $reactivated_access$
begin
  if public.has_current_platform_access_v1() is distinct from true then
    raise exception 'reactivated tenant did not regain platform access';
  end if;
end;
$reactivated_access$;

-- A second active occupancy sharing the SAME canonical tenant identity prevents
-- archival/revocation when only one stay is ended.
reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.offboard.root'),
    'role','authenticated',
    'app_metadata',jsonb_build_object('role','root')
  )::text,
  true
);

select public.offboard_tenant_occupancy_v2(
  current_setting('gestionpisos.offboard.occ2a')::uuid,
  current_date+1
);

reset role;

do $other_occupancy_preserves_role$
begin
  if exists(
    select 1 from public.user_roles
    where user_id=current_setting('gestionpisos.offboard.user2')::uuid
      and organization_id=current_setting('gestionpisos.offboard.org')::uuid
      and role='tenant'
      and revoked_at is not null
  ) then
    raise exception 'tenant role revoked despite another active occupancy';
  end if;

  if not exists(
    select 1 from public.tenants_v2
    where id=current_setting('gestionpisos.offboard.tenant2')::uuid
      and status='active'
      and archived_at is null
  ) then
    raise exception 'shared canonical tenant was archived while another occupancy remained active';
  end if;

  if not exists(
    select 1 from public.occupancies_v2
    where id=current_setting('gestionpisos.offboard.occ2a')::uuid
      and status='archived'
  ) then
    raise exception 'selected occupancy was not archived';
  end if;
end;
$other_occupancy_preserves_role$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',current_setting('gestionpisos.offboard.user2'),
    'role','authenticated',
    'app_metadata',jsonb_build_object(
      'role','tenant',
      'organization_id',current_setting('gestionpisos.offboard.org')
    )
  )::text,
  true
);

do $other_occupancy_access$
begin
  if public.has_current_platform_access_v1() is distinct from true then
    raise exception 'remaining active occupancy did not preserve platform access';
  end if;
  if not exists(
    select 1 from public.occupancies_v2
    where id=current_setting('gestionpisos.offboard.occ2b')::uuid
  ) then
    raise exception 'remaining active occupancy is not readable';
  end if;
end;
$other_occupancy_access$;

reset role;
rollback;
