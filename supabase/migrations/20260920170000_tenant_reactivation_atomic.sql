-- GestionPisos · reactivación atómica de inquilino suspendido.
-- Cierra el hueco donde la UI podía dejar tenant=active sin ocupación activa
-- vinculada a Auth. Suspensión -> Alta se resuelve ahora en una sola transacción.

create or replace function public.reactivate_tenant_occupancy_v1(
  p_occupancy_id uuid,
  p_property_id uuid,
  p_room_id uuid,
  p_full_name text,
  p_document_type text,
  p_document_number text,
  p_email text,
  p_starts_on date,
  p_ends_on date default null,
  p_indefinite boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_org uuid;
  v_tenant_id uuid;
  v_auth_user_id uuid;
  v_old_property_id uuid;
  v_old_status public.record_status;
  v_new_occupancy_id uuid;
  v_email text:=lower(btrim(p_email));
  v_document text:=upper(btrim(p_document_number));
  v_restore jsonb:=null;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if p_occupancy_id is null or p_property_id is null or p_room_id is null then
    raise exception 'tenant_reactivation_scope_required' using errcode='22023';
  end if;

  if nullif(btrim(p_full_name),'') is null
    or nullif(btrim(p_document_type),'') is null
    or nullif(v_document,'') is null
    or nullif(v_email,'') is null then
    raise exception 'tenant_reactivation_identity_required' using errcode='22023';
  end if;

  if p_starts_on is null
    or (not coalesce(p_indefinite,false) and p_ends_on is null)
    or (p_ends_on is not null and p_ends_on<p_starts_on) then
    raise exception 'occupancy_dates_invalid' using errcode='22023';
  end if;

  select
    o.organization_id,
    o.tenant_id,
    coalesce(o.user_id,t.user_id),
    o.property_id,
    o.status
  into
    v_org,
    v_tenant_id,
    v_auth_user_id,
    v_old_property_id,
    v_old_status
  from public.occupancies_v2 o
  join public.tenants_v2 t
    on t.id=o.tenant_id
   and t.organization_id=o.organization_id
  where o.id=p_occupancy_id
  for update of o,t;

  if v_org is null or v_tenant_id is null then
    raise exception 'occupancy_not_found' using errcode='P0002';
  end if;

  if v_old_status<>'blocked' then
    raise exception 'tenant_reactivation_invalid_state' using errcode='22023';
  end if;

  if not public.can_operate_property_v3(v_old_property_id,true)
    or not public.can_operate_property_v3(p_property_id,true) then
    raise exception 'property_write_required' using errcode='42501';
  end if;

  if not exists(
    select 1
    from public.properties_v2 p
    where p.id=p_property_id
      and p.organization_id=v_org
      and p.archived_at is null
  ) then
    raise exception 'property_not_found' using errcode='P0002';
  end if;

  if not exists(
    select 1
    from public.rooms_v2 r
    where r.id=p_room_id
      and r.property_id=p_property_id
      and r.archived_at is null
  ) then
    raise exception 'room_property_mismatch' using errcode='42501';
  end if;

  if exists(
    select 1
    from public.tenants_v2 t
    where t.organization_id=v_org
      and t.id<>v_tenant_id
      and lower(t.email)=v_email
  ) then
    raise exception 'tenant_email_identity_conflict' using errcode='23505';
  end if;

  update public.tenants_v2
  set full_name=btrim(p_full_name),
      document_type=btrim(p_document_type),
      document_number=v_document,
      email=v_email,
      status='active',
      archived_at=null,
      deletion_requested_at=null,
      deletion_requested_by=null,
      updated_at=now()
  where id=v_tenant_id;

  update public.occupancies_v2
  set status='archived',
      starts_on=null,
      ends_on=null
  where id=p_occupancy_id;

  insert into public.occupancies_v2(
    organization_id,
    tenant_id,
    property_id,
    room_id,
    occupant_email,
    starts_on,
    ends_on,
    status,
    user_id,
    suspended_at
  ) values (
    v_org,
    v_tenant_id,
    p_property_id,
    p_room_id,
    v_email,
    p_starts_on,
    case when coalesce(p_indefinite,false) then null else p_ends_on end,
    'active',
    v_auth_user_id,
    null
  )
  returning id into v_new_occupancy_id;

  if v_auth_user_id is not null then
    v_restore:=public.restore_tenant_platform_access_v1(
      v_tenant_id,
      v_auth_user_id,
      v_actor
    );
  end if;

  insert into public.audit_log_v2(
    organization_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    result,
    details
  ) values (
    v_org,
    v_actor,
    'tenant_occupancy_reactivated',
    'tenant',
    v_tenant_id::text,
    'success',
    jsonb_build_object(
      'previous_occupancy_id',p_occupancy_id,
      'new_occupancy_id',v_new_occupancy_id,
      'property_id',p_property_id,
      'room_id',p_room_id,
      'starts_on',p_starts_on,
      'auth_user_id',v_auth_user_id
    )
  );

  return jsonb_build_object(
    'tenant_id',v_tenant_id,
    'occupancy_id',v_new_occupancy_id,
    'auth_user_id',v_auth_user_id,
    'platform_access_restored',coalesce((v_restore->>'platform_access_restored')::boolean,false)
  );
end;
$$;

revoke all on function public.reactivate_tenant_occupancy_v1(
  uuid,uuid,uuid,text,text,text,text,date,date,boolean
) from public,anon;

grant execute on function public.reactivate_tenant_occupancy_v1(
  uuid,uuid,uuid,text,text,text,text,date,date,boolean
) to authenticated,service_role;

comment on function public.reactivate_tenant_occupancy_v1(
  uuid,uuid,uuid,text,text,text,text,date,date,boolean
) is
  'Reactivación transaccional Suspendido->Alta: archiva la estancia suspendida, crea la nueva ocupación, religa Auth/rol tenant y audita; cualquier fallo revierte todo.';
