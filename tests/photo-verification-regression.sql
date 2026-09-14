-- Isolated RLS matrix for the B-10 backend policies. All fixtures are local
-- to this transaction and are rolled back; no real Auth user is created.

begin;

grant select, insert, update, delete on table
  public.verification_policies_v2,
  public.photo_patterns_v2,
  public.photo_verification_runs_v2,
  public.photo_verification_items_v2,
  public.random_photo_requests_v2
to authenticated;

grant select on table
  public.occupancies_v2,
  public.property_staff_access_v3
to authenticated;

select set_config(
  'gestionpisos.photo.org_a',
  (select id::text from public.organizations where name = 'Allaiso' limit 1),
  true
);
select set_config(
  'gestionpisos.photo.root_uid',
  (select user_id::text from public.user_roles where role = 'root' and revoked_at is null limit 1),
  true
);
select set_config('gestionpisos.photo.org_b', gen_random_uuid()::text, true);
select set_config('gestionpisos.photo.admin_uid', gen_random_uuid()::text, true);
select set_config('gestionpisos.photo.actor_uid', gen_random_uuid()::text, true);
select set_config('gestionpisos.photo.other_uid', gen_random_uuid()::text, true);
select set_config('gestionpisos.photo.owner_a', gen_random_uuid()::text, true);
select set_config('gestionpisos.photo.owner_b', gen_random_uuid()::text, true);
select set_config('gestionpisos.photo.property_a', gen_random_uuid()::text, true);
select set_config('gestionpisos.photo.property_b', gen_random_uuid()::text, true);
select set_config('gestionpisos.photo.room_a', gen_random_uuid()::text, true);
select set_config('gestionpisos.photo.pattern_a', gen_random_uuid()::text, true);
select set_config('gestionpisos.photo.pattern_b', gen_random_uuid()::text, true);
select set_config('gestionpisos.photo.run_own', gen_random_uuid()::text, true);
select set_config('gestionpisos.photo.run_other', gen_random_uuid()::text, true);

insert into auth.users (id)
values
  (current_setting('gestionpisos.photo.admin_uid')::uuid),
  (current_setting('gestionpisos.photo.actor_uid')::uuid),
  (current_setting('gestionpisos.photo.other_uid')::uuid);

insert into public.organizations (id, name)
values (current_setting('gestionpisos.photo.org_b')::uuid, 'Other test organization');

insert into public.owners (id, organization_id, full_name)
values
  (
    current_setting('gestionpisos.photo.owner_a')::uuid,
    current_setting('gestionpisos.photo.org_a')::uuid,
    'Photo test owner A'
  ),
  (
    current_setting('gestionpisos.photo.owner_b')::uuid,
    current_setting('gestionpisos.photo.org_b')::uuid,
    'Photo test owner B'
  );

insert into public.properties_v2 (id, organization_id, owner_id, name, address_line, status)
values
  (
    current_setting('gestionpisos.photo.property_a')::uuid,
    current_setting('gestionpisos.photo.org_a')::uuid,
    current_setting('gestionpisos.photo.owner_a')::uuid,
    'Photo test property A',
    'Test-only address A',
    'active'
  ),
  (
    current_setting('gestionpisos.photo.property_b')::uuid,
    current_setting('gestionpisos.photo.org_b')::uuid,
    current_setting('gestionpisos.photo.owner_b')::uuid,
    'Photo test property B',
    'Test-only address B',
    'active'
  );

insert into public.rooms_v2 (id, property_id, label)
values (
  current_setting('gestionpisos.photo.room_a')::uuid,
  current_setting('gestionpisos.photo.property_a')::uuid,
  'Photo test room A'
);

insert into public.occupancies_v2 (
  organization_id, property_id, room_id, occupant_email, starts_on, status, user_id
)
values (
  current_setting('gestionpisos.photo.org_a')::uuid,
  current_setting('gestionpisos.photo.property_a')::uuid,
  current_setting('gestionpisos.photo.room_a')::uuid,
  'photo-actor@example.invalid',
  current_date,
  'active',
  current_setting('gestionpisos.photo.actor_uid')::uuid
);

insert into public.photo_patterns_v2 (
  id, organization_id, property_id, name, target_type, reference_storage_path
)
values
  (
    current_setting('gestionpisos.photo.pattern_a')::uuid,
    current_setting('gestionpisos.photo.org_a')::uuid,
    current_setting('gestionpisos.photo.property_a')::uuid,
    'Seed pattern A',
    'zone',
    'seed/a.webp'
  ),
  (
    current_setting('gestionpisos.photo.pattern_b')::uuid,
    current_setting('gestionpisos.photo.org_b')::uuid,
    current_setting('gestionpisos.photo.property_b')::uuid,
    'Seed pattern B',
    'zone',
    'seed/b.webp'
  );

insert into public.photo_verification_runs_v2 (
  id, organization_id, property_id, actor_user_id, source_type, verification_mode
)
values
  (
    current_setting('gestionpisos.photo.run_own')::uuid,
    current_setting('gestionpisos.photo.org_a')::uuid,
    current_setting('gestionpisos.photo.property_a')::uuid,
    current_setting('gestionpisos.photo.actor_uid')::uuid,
    'manual',
    'manual'
  ),
  (
    current_setting('gestionpisos.photo.run_other')::uuid,
    current_setting('gestionpisos.photo.org_a')::uuid,
    current_setting('gestionpisos.photo.property_a')::uuid,
    current_setting('gestionpisos.photo.other_uid')::uuid,
    'manual',
    'manual'
  );

set local role authenticated;

-- ROOT can manage policies, patterns and random requests globally.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', current_setting('gestionpisos.photo.root_uid'),
    'role', 'authenticated',
    'app_metadata', jsonb_build_object('role', 'root')
  )::text,
  true
);

insert into public.verification_policies_v2 (
  organization_id, property_id, verification_mode
)
values (
  current_setting('gestionpisos.photo.org_b')::uuid,
  current_setting('gestionpisos.photo.property_b')::uuid,
  'manual'
);
update public.verification_policies_v2
set verification_mode = 'hybrid'
where organization_id = current_setting('gestionpisos.photo.org_b')::uuid;

insert into public.photo_patterns_v2 (
  organization_id, property_id, name, target_type, reference_storage_path
)
values (
  current_setting('gestionpisos.photo.org_b')::uuid,
  current_setting('gestionpisos.photo.property_b')::uuid,
  'ROOT managed pattern',
  'zone',
  'root/pattern.webp'
);
update public.photo_patterns_v2
set active = false
where name = 'ROOT managed pattern';

insert into public.random_photo_requests_v2 (
  organization_id, property_id, assigned_user_id, pattern_id
)
values (
  current_setting('gestionpisos.photo.org_a')::uuid,
  current_setting('gestionpisos.photo.property_a')::uuid,
  current_setting('gestionpisos.photo.actor_uid')::uuid,
  current_setting('gestionpisos.photo.pattern_a')::uuid
);
update public.random_photo_requests_v2
set status = 'cancelled'
where organization_id = current_setting('gestionpisos.photo.org_a')::uuid;

-- ADMIN can manage rows inside its own organization.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', current_setting('gestionpisos.photo.admin_uid'),
    'role', 'authenticated',
    'app_metadata', jsonb_build_object(
      'role', 'admin',
      'organization_id', current_setting('gestionpisos.photo.org_a')
    )
  )::text,
  true
);

insert into public.verification_policies_v2 (
  organization_id, property_id, verification_mode
)
values (
  current_setting('gestionpisos.photo.org_a')::uuid,
  current_setting('gestionpisos.photo.property_a')::uuid,
  'manual'
);
update public.verification_policies_v2
set verification_mode = 'ai'
where organization_id = current_setting('gestionpisos.photo.org_a')::uuid;

insert into public.photo_patterns_v2 (
  organization_id, property_id, name, target_type, reference_storage_path
)
values (
  current_setting('gestionpisos.photo.org_a')::uuid,
  current_setting('gestionpisos.photo.property_a')::uuid,
  'ADMIN managed pattern',
  'zone',
  'admin/pattern.webp'
);
update public.photo_patterns_v2
set active = false
where name = 'ADMIN managed pattern';

insert into public.random_photo_requests_v2 (
  organization_id, property_id, assigned_user_id, pattern_id
)
values (
  current_setting('gestionpisos.photo.org_a')::uuid,
  current_setting('gestionpisos.photo.property_a')::uuid,
  current_setting('gestionpisos.photo.actor_uid')::uuid,
  current_setting('gestionpisos.photo.pattern_a')::uuid
);
update public.random_photo_requests_v2
set status = 'cancelled'
where organization_id = current_setting('gestionpisos.photo.org_a')::uuid;

-- ADMIN A cannot insert rows scoped to organization B.
do $$
begin
  begin
    insert into public.verification_policies_v2 (
      organization_id, property_id, verification_mode
    )
    values (
      current_setting('gestionpisos.photo.org_b')::uuid,
      current_setting('gestionpisos.photo.property_b')::uuid,
      'manual'
    );
    raise exception 'cross-organization ADMIN policy insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.photo_patterns_v2 (
      organization_id, property_id, name, target_type, reference_storage_path
    )
    values (
      current_setting('gestionpisos.photo.org_b')::uuid,
      current_setting('gestionpisos.photo.property_b')::uuid,
      'Denied cross-organization pattern',
      'zone',
      'denied/pattern.webp'
    );
    raise exception 'cross-organization ADMIN pattern insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.random_photo_requests_v2 (
      organization_id, property_id, assigned_user_id, pattern_id
    )
    values (
      current_setting('gestionpisos.photo.org_b')::uuid,
      current_setting('gestionpisos.photo.property_b')::uuid,
      current_setting('gestionpisos.photo.actor_uid')::uuid,
      current_setting('gestionpisos.photo.pattern_b')::uuid
    );
    raise exception 'cross-organization ADMIN random request insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- A normal assigned actor cannot manage configuration or invent requests.
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', current_setting('gestionpisos.photo.actor_uid'),
    'role', 'authenticated',
    'app_metadata', jsonb_build_object(
      'role', 'tenant',
      'organization_id', current_setting('gestionpisos.photo.org_a')
    )
  )::text,
  true
);

do $$
begin
  begin
    insert into public.verification_policies_v2 (
      organization_id, property_id, verification_mode
    )
    values (
      current_setting('gestionpisos.photo.org_a')::uuid,
      current_setting('gestionpisos.photo.property_a')::uuid,
      'manual'
    );
    raise exception 'normal user policy insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.photo_patterns_v2 (
      organization_id, property_id, name, target_type, reference_storage_path
    )
    values (
      current_setting('gestionpisos.photo.org_a')::uuid,
      current_setting('gestionpisos.photo.property_a')::uuid,
      'Denied normal-user pattern',
      'zone',
      'denied/user-pattern.webp'
    );
    raise exception 'normal user pattern insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.random_photo_requests_v2 (
      organization_id, property_id, assigned_user_id, pattern_id
    )
    values (
      current_setting('gestionpisos.photo.org_a')::uuid,
      current_setting('gestionpisos.photo.property_a')::uuid,
      current_setting('gestionpisos.photo.actor_uid')::uuid,
      current_setting('gestionpisos.photo.pattern_a')::uuid
    );
    raise exception 'assigned user random request insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

do $$
declare
  affected integer;
begin
  update public.photo_patterns_v2
  set active = false
  where id = current_setting('gestionpisos.photo.pattern_a')::uuid;
  get diagnostics affected = row_count;
  if affected <> 0 then
    raise exception 'normal user pattern update unexpectedly succeeded';
  end if;
end;
$$;

-- The actor can insert an item only in its own run.
insert into public.photo_verification_items_v2 (run_id, pattern_id, storage_path)
values (
  current_setting('gestionpisos.photo.run_own')::uuid,
  current_setting('gestionpisos.photo.pattern_a')::uuid,
  'own/item.webp'
);

do $$
begin
  begin
    insert into public.photo_verification_items_v2 (run_id, pattern_id, storage_path)
    values (
      current_setting('gestionpisos.photo.run_other')::uuid,
      current_setting('gestionpisos.photo.pattern_a')::uuid,
      'other/item.webp'
    );
    raise exception 'actor insert into another run unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select 'Photo verification RLS regression tests passed' as result;

rollback;
