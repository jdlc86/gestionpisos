create or replace function public.root_configuration_resources_service(
  p_actor_user_id uuid,
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile_organization_id uuid;
  v_active_organization_count integer := 0;
  v_database_bytes bigint := 0;
  v_storage_bytes bigint := 0;
  v_storage_objects bigint := 0;
  v_organization_name text;
  v_organization_status text;
  v_latest_reset_at timestamptz;
  v_root_recovery_operators integer := 0;
begin
  perform set_config('lock_timeout', '5s', true);
  perform set_config('statement_timeout', '20s', true);

  if p_actor_user_id is null or p_organization_id is null then
    raise exception 'configuration_resources_invalid_context';
  end if;

  if not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = p_actor_user_id
      and lower(ur.role::text) = 'root'
      and ur.revoked_at is null
  ) then
    raise exception 'root_required';
  end if;

  select o.name, o.status::text
    into v_organization_name, v_organization_status
  from public.organizations o
  where o.id = p_organization_id
    and lower(o.status::text) = 'active';

  if v_organization_name is null then
    raise exception 'organization_required';
  end if;

  select p.organization_id
    into v_profile_organization_id
  from public.profiles p
  where p.user_id = p_actor_user_id
    and lower(p.status::text) = 'active'
  limit 1;

  if v_profile_organization_id is not null then
    if v_profile_organization_id <> p_organization_id then
      raise exception 'root_organization_mismatch';
    end if;
  else
    select count(*)
      into v_active_organization_count
    from public.organizations o
    where lower(o.status::text) = 'active';

    if v_active_organization_count <> 1 then
      raise exception 'root_organization_ambiguous';
    end if;
  end if;

  select pg_database_size(current_database()) into v_database_bytes;

  select
    count(*)::bigint,
    coalesce(sum(case
      when nullif(so.metadata->>'size', '') ~ '^[0-9]+$'
        then (so.metadata->>'size')::bigint
      else 0
    end), 0)::bigint
  into v_storage_objects, v_storage_bytes
  from storage.objects so
  where so.bucket_id in ('photo-verification', 'tenant-documents-v2');

  select count(*)::integer
    into v_root_recovery_operators
  from public.platform_operators po
  where po.active = true
    and po.can_recover_root = true;

  select a.created_at
    into v_latest_reset_at
  from public.audit_log_v2 a
  where a.action = 'factory_reset_completed'
    and a.organization_id = p_organization_id
  order by a.created_at desc
  limit 1;

  return jsonb_build_object(
    'organization', jsonb_build_object(
      'id', p_organization_id,
      'name', v_organization_name,
      'status', v_organization_status
    ),
    'database', jsonb_build_object(
      'used_bytes', v_database_bytes
    ),
    'storage', jsonb_build_object(
      'used_bytes', v_storage_bytes,
      'objects', v_storage_objects
    ),
    'inventory', jsonb_build_object(
      'properties', (select count(*) from public.properties_v2 p where p.organization_id = p_organization_id and p.archived_at is null),
      'rooms', (select count(*) from public.rooms_v2 r join public.properties_v2 p on p.id = r.property_id where p.organization_id = p_organization_id and p.archived_at is null and r.archived_at is null),
      'owners', (select count(*) from public.owners o where o.organization_id = p_organization_id and o.archived_at is null),
      'tenants', (select count(*) from public.tenants_v2 t where t.organization_id = p_organization_id and t.archived_at is null),
      'occupancies', (select count(*) from public.occupancies_v2 oc where oc.organization_id = p_organization_id),
      'incidents', (select count(*) from public.incidents_v2 i where i.organization_id = p_organization_id),
      'cleaning_tasks', (select count(*) from public.cleaning_tasks_v2 c where c.organization_id = p_organization_id),
      'photo_verification_runs', (select count(*) from public.photo_verification_runs_v2 r where r.organization_id = p_organization_id),
      'tenant_documents', (select count(*) from public.tenant_documents_v2 d where d.organization_id = p_organization_id),
      'notifications', (select count(*) from public.notifications_v2 n where n.organization_id = p_organization_id)
    ),
    'security', jsonb_build_object(
      'root_recovery_operator_count', v_root_recovery_operators,
      'latest_factory_reset_at', v_latest_reset_at
    )
  );
end;
$$;

revoke all on function public.root_configuration_resources_service(uuid, uuid) from public, anon, authenticated;
grant execute on function public.root_configuration_resources_service(uuid, uuid) to service_role;

comment on function public.root_configuration_resources_service(uuid, uuid) is
  'Service-role-only ROOT overview for GestionPisos configuration/resources. Returns aggregate resource and application inventory data without exposing secrets.';
