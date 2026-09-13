-- Execute with a privileged PostgreSQL connection against a disposable/test
-- transaction. The script creates no Auth users and rolls back every fixture.

begin;

select set_config(
  'gestionpisos.test_org_id',
  (select id::text from public.organizations where name = 'Allaiso' limit 1),
  true
);
select set_config(
  'gestionpisos.test_root_uid',
  (select user_id::text from public.user_roles where role = 'root' and revoked_at is null limit 1),
  true
);
select set_config('gestionpisos.test_owner_id', gen_random_uuid()::text, true);
select set_config('gestionpisos.test_admin_owner_id', gen_random_uuid()::text, true);

do $$
begin
  if current_setting('gestionpisos.test_org_id', true) is null
    or current_setting('gestionpisos.test_root_uid', true) is null then
    raise exception 'test prerequisites missing: Allaiso organization or active ROOT';
  end if;
end;
$$;

set local role authenticated;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', current_setting('gestionpisos.test_root_uid'),
    'role', 'authenticated',
    'app_metadata', jsonb_build_object('role', 'root')
  )::text,
  true
);

insert into public.owners (id, organization_id, full_name)
values (
  current_setting('gestionpisos.test_owner_id')::uuid,
  current_setting('gestionpisos.test_org_id')::uuid,
  'RLS regression ROOT'
);

update public.owners
set status = 'archived', archived_at = now()
where id = current_setting('gestionpisos.test_owner_id')::uuid;

do $$
begin
  begin
    delete from public.owners
    where id = current_setting('gestionpisos.test_owner_id')::uuid;
    raise exception 'ROOT client delete unexpectedly succeeded';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', current_setting('gestionpisos.test_root_uid'),
    'role', 'authenticated',
    'app_metadata', jsonb_build_object(
      'role', 'admin',
      'organization_id', current_setting('gestionpisos.test_org_id')
    )
  )::text,
  true
);

insert into public.owners (id, organization_id, full_name)
values (
  current_setting('gestionpisos.test_admin_owner_id')::uuid,
  current_setting('gestionpisos.test_org_id')::uuid,
  'RLS regression ADMIN'
);

update public.owners
set full_name = 'RLS regression ADMIN updated'
where id = current_setting('gestionpisos.test_admin_owner_id')::uuid;

do $$
declare
  denied_role text;
begin
  foreach denied_role in array array['owner', 'employee', 'tenant']
  loop
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', current_setting('gestionpisos.test_root_uid'),
        'role', 'authenticated',
        'app_metadata', jsonb_build_object(
          'role', denied_role,
          'organization_id', current_setting('gestionpisos.test_org_id')
        )
      )::text,
      true
    );

    begin
      insert into public.owners (organization_id, full_name)
      values (
        current_setting('gestionpisos.test_org_id')::uuid,
        'Denied ' || denied_role
      );
      raise exception '% insert unexpectedly succeeded', denied_role;
    exception
      when insufficient_privilege then null;
    end;

    begin
      update public.owners
      set full_name = 'Denied update'
      where id = current_setting('gestionpisos.test_admin_owner_id')::uuid;
      if found then
        raise exception '% update unexpectedly succeeded', denied_role;
      end if;
    end;
  end loop;
end;
$$;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', current_setting('gestionpisos.test_root_uid'),
    'role', 'authenticated',
    'app_metadata', jsonb_build_object(
      'role', 'admin',
      'organization_id', gen_random_uuid()::text
    )
  )::text,
  true
);

do $$
begin
  begin
    insert into public.owners (organization_id, full_name)
    values (
      current_setting('gestionpisos.test_org_id')::uuid,
      'Denied cross-organization ADMIN'
    );
    raise exception 'cross-organization ADMIN insert unexpectedly succeeded';
  exception
    when insufficient_privilege then null;
  end;

  update public.owners
  set full_name = 'Denied cross-organization ADMIN update'
  where id = current_setting('gestionpisos.test_admin_owner_id')::uuid;
  if found then
    raise exception 'cross-organization ADMIN update unexpectedly succeeded';
  end if;
end;
$$;

reset role;

do $$
declare
  owner_id uuid := gen_random_uuid();
  property_id uuid := gen_random_uuid();
  open_room_id uuid := gen_random_uuid();
  dated_room_id uuid := gen_random_uuid();
  rejected boolean;
begin
  insert into public.owners (id, organization_id, full_name)
  values (
    owner_id,
    current_setting('gestionpisos.test_org_id')::uuid,
    'Occupancy regression owner'
  );

  insert into public.properties_v2 (
    id, organization_id, owner_id, name, address_line, status
  )
  values (
    property_id,
    current_setting('gestionpisos.test_org_id')::uuid,
    owner_id,
    'Occupancy regression property',
    'Test-only address',
    'active'
  );

  insert into public.rooms_v2 (id, property_id, label)
  values
    (open_room_id, property_id, 'Open overlap room'),
    (dated_room_id, property_id, 'Dated overlap room');

  insert into public.occupancies_v2 (
    organization_id, property_id, room_id, occupant_email,
    starts_on, ends_on, status
  )
  values (
    current_setting('gestionpisos.test_org_id')::uuid,
    property_id,
    open_room_id,
    'open-one@example.invalid',
    date '2026-01-01',
    null,
    'active'
  );

  rejected := false;
  begin
    insert into public.occupancies_v2 (
      organization_id, property_id, room_id, occupant_email,
      starts_on, ends_on, status
    )
    values (
      current_setting('gestionpisos.test_org_id')::uuid,
      property_id,
      open_room_id,
      'open-two@example.invalid',
      date '2026-02-01',
      null,
      'active'
    );
  exception
    when exclusion_violation then rejected := true;
  end;
  if not rejected then
    raise exception 'second open active occupancy unexpectedly succeeded';
  end if;

  insert into public.occupancies_v2 (
    organization_id, property_id, room_id, occupant_email,
    starts_on, ends_on, status
  )
  values (
    current_setting('gestionpisos.test_org_id')::uuid,
    property_id,
    dated_room_id,
    'dated-one@example.invalid',
    date '2026-01-01',
    date '2026-01-31',
    'active'
  );

  rejected := false;
  begin
    insert into public.occupancies_v2 (
      organization_id, property_id, room_id, occupant_email,
      starts_on, ends_on, status
    )
    values (
      current_setting('gestionpisos.test_org_id')::uuid,
      property_id,
      dated_room_id,
      'dated-overlap@example.invalid',
      date '2026-01-15',
      date '2026-02-15',
      'active'
    );
  exception
    when exclusion_violation then rejected := true;
  end;
  if not rejected then
    raise exception 'overlapping dated active occupancy unexpectedly succeeded';
  end if;

  insert into public.occupancies_v2 (
    organization_id, property_id, room_id, occupant_email,
    starts_on, ends_on, status
  )
  values (
    current_setting('gestionpisos.test_org_id')::uuid,
    property_id,
    dated_room_id,
    'dated-non-overlap@example.invalid',
    date '2026-02-01',
    date '2026-02-28',
    'active'
  );

  rejected := false;
  begin
    insert into public.occupancies_v2 (
      organization_id, property_id, room_id, occupant_email,
      starts_on, ends_on, status
    )
    values (
      current_setting('gestionpisos.test_org_id')::uuid,
      property_id,
      dated_room_id,
      'invalid-dates@example.invalid',
      date '2027-02-01',
      date '2027-01-31',
      'active'
    );
  exception
    when check_violation then rejected := true;
  end;
  if not rejected then
    raise exception 'invalid occupancy date range unexpectedly succeeded';
  end if;
end;
$$;

do $$
begin
  begin
    update public.user_roles
    set role = 'admin'
    where role = 'root' and revoked_at is null;
    raise exception 'ROOT role mutation unexpectedly succeeded';
  exception
    when raise_exception then
      if sqlerrm <> 'ROOT role is immutable' then
        raise;
      end if;
  end;
end;
$$;

select 'Database security regression tests passed' as result;

rollback;
