begin;

do $$
declare
  v_org uuid;
  v_owner uuid := gen_random_uuid();
  v_property_active_on_insert uuid := gen_random_uuid();
  v_property_active_on_update uuid := gen_random_uuid();
  v_property_stays_onboarding uuid := gen_random_uuid();
  v_room uuid := gen_random_uuid();
  v_status public.property_status;
begin
  select id into v_org
  from public.organizations
  where name='Allaiso'
  limit 1;

  if v_org is null then
    raise exception 'property auto-activation regression requires Allaiso fixture';
  end if;

  insert into public.owners(id,organization_id,full_name)
  values(v_owner,v_org,'Property activation regression owner');

  insert into public.properties_v2(
    id,organization_id,owner_id,name,address_line,status
  ) values (
    v_property_active_on_insert,v_org,v_owner,
    'Auto active on room insert','Regression address','onboarding'
  );

  insert into public.rooms_v2(id,property_id,label,status)
  values(gen_random_uuid(),v_property_active_on_insert,'Active room','active');

  select status into v_status
  from public.properties_v2
  where id=v_property_active_on_insert;

  if v_status <> 'active' then
    raise exception 'onboarding property was not activated by first active room insert';
  end if;

  insert into public.properties_v2(
    id,organization_id,owner_id,name,address_line,status
  ) values (
    v_property_active_on_update,v_org,v_owner,
    'Auto active on room update','Regression address','onboarding'
  );

  insert into public.rooms_v2(id,property_id,label,status)
  values(v_room,v_property_active_on_update,'Initially blocked room','blocked');

  select status into v_status
  from public.properties_v2
  where id=v_property_active_on_update;

  if v_status <> 'onboarding' then
    raise exception 'blocked room activated property unexpectedly';
  end if;

  update public.rooms_v2
  set status='active',updated_at=now()
  where id=v_room;

  select status into v_status
  from public.properties_v2
  where id=v_property_active_on_update;

  if v_status <> 'active' then
    raise exception 'activating existing room did not activate onboarding property';
  end if;

  update public.rooms_v2
  set status='archived',archived_at=now(),updated_at=now()
  where id=v_room;

  select status into v_status
  from public.properties_v2
  where id=v_property_active_on_update;

  if v_status <> 'active' then
    raise exception 'property reverted after room archival';
  end if;

  insert into public.properties_v2(
    id,organization_id,owner_id,name,address_line,status
  ) values (
    v_property_stays_onboarding,v_org,v_owner,
    'No active rooms','Regression address','onboarding'
  );

  select status into v_status
  from public.properties_v2
  where id=v_property_stays_onboarding;

  if v_status <> 'onboarding' then
    raise exception 'property without active rooms must remain onboarding';
  end if;
end;
$$;

do $$
begin
  if has_function_privilege('anon','private.promote_property_on_active_room_v1()','EXECUTE') then
    raise exception 'anon can execute private property promotion function';
  end if;
  if has_function_privilege('authenticated','private.promote_property_on_active_room_v1()','EXECUTE') then
    raise exception 'authenticated can execute private property promotion function';
  end if;
end;
$$;

select 'Property auto-activation regression passed' as result;

rollback;
