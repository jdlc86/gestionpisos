-- GestionPisos · acceso de inquilino tras Suspensión/Baja
-- La sesión Auth no es autoridad de acceso. Un JWT aún válido debe quedar
-- inutilizable en cuanto desaparece la relación operativa del usuario.

create or replace function public.has_current_platform_access_v1()
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
begin
  if v_actor is null then
    return false;
  end if;

  -- Roles internos/propietario: el rol DB vigente es la autoridad.
  if exists(
    select 1
    from public.user_roles ur
    where ur.user_id=v_actor
      and ur.revoked_at is null
      and ur.role in ('root','admin','owner','employee')
  ) then
    return true;
  end if;

  -- Inquilino: no basta con conservar el rol tenant. Debe existir identidad
  -- activa y una ocupación Alta/vigente vinculada al mismo usuario.
  return exists(
    select 1
    from public.user_roles ur
    join public.tenants_v2 t
      on t.user_id=ur.user_id
     and t.organization_id=ur.organization_id
     and t.status='active'
     and t.archived_at is null
    join public.occupancies_v2 o
      on o.tenant_id=t.id
     and o.user_id=ur.user_id
     and o.organization_id=ur.organization_id
     and o.status='active'
     and o.starts_on is not null
     and o.starts_on<=current_date
     and (o.ends_on is null or o.ends_on>=current_date)
    where ur.user_id=v_actor
      and ur.role='tenant'
      and ur.revoked_at is null
  );
end;
$$;

revoke all on function public.has_current_platform_access_v1()
  from public,anon;
grant execute on function public.has_current_platform_access_v1()
  to authenticated,service_role;

comment on function public.has_current_platform_access_v1() is
  'Autoridad DB de acceso a Allaiso. Tenant requiere rol vigente + identidad activa + ocupación Alta y vigente; Suspensión/Baja devuelven false aunque el JWT siga vivo.';

-- Estado server-side que usa la Edge Function después de una Baja. No acepta
-- un user_id suministrado por el cliente: resuelve la identidad desde la
-- ocupación y vuelve a comprobar la autorización del actor.
create or replace function public.get_tenant_offboarding_auth_state_v1(
  p_occupancy_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_org uuid;
  v_property_id uuid;
  v_tenant_id uuid;
  v_user_id uuid;
  v_occupancy_status public.record_status;
  v_tenant_status public.record_status;
  v_other_active boolean:=false;
  v_active_tenant_role boolean:=false;
  v_other_active_role boolean:=false;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if p_occupancy_id is null then
    raise exception 'occupancy_required' using errcode='22023';
  end if;

  select
    o.organization_id,
    o.property_id,
    o.tenant_id,
    coalesce(o.user_id,t.user_id),
    o.status,
    t.status
  into
    v_org,
    v_property_id,
    v_tenant_id,
    v_user_id,
    v_occupancy_status,
    v_tenant_status
  from public.occupancies_v2 o
  join public.tenants_v2 t
    on t.id=o.tenant_id
   and t.organization_id=o.organization_id
  where o.id=p_occupancy_id;

  if v_org is null or v_tenant_id is null then
    raise exception 'occupancy_not_found' using errcode='P0002';
  end if;
  if not (
    exists(
      select 1 from public.user_roles ur
      where ur.user_id=v_actor
        and ur.role='root'
        and ur.revoked_at is null
    )
    or exists(
      select 1 from public.user_roles ur
      where ur.user_id=v_actor
        and ur.organization_id=v_org
        and ur.role='admin'
        and ur.revoked_at is null
    )
    or exists(
      select 1 from public.property_staff_access_v3 a
      where a.property_id=v_property_id
        and a.employee_user_id=v_actor
        and a.revoked_at is null
        and (a.valid_until is null or a.valid_until>now())
        and a.can_write=true
    )
  ) then
    raise exception 'property_write_required' using errcode='42501';
  end if;
  if v_occupancy_status<>'archived' or v_tenant_status<>'archived' then
    raise exception 'tenant_offboarding_not_completed' using errcode='55000';
  end if;

  if v_user_id is not null then
    select exists(
      select 1
      from public.occupancies_v2 o
      join public.tenants_v2 t
        on t.id=o.tenant_id
       and t.organization_id=o.organization_id
       and t.user_id=v_user_id
       and t.status='active'
       and t.archived_at is null
      where o.organization_id=v_org
        and o.id<>p_occupancy_id
        and o.user_id=v_user_id
        and o.status='active'
        and o.starts_on is not null
        and o.starts_on<=current_date
        and (o.ends_on is null or o.ends_on>=current_date)
    ) into v_other_active;

    select exists(
      select 1
      from public.user_roles ur
      where ur.user_id=v_user_id
        and ur.organization_id=v_org
        and ur.role='tenant'
        and ur.revoked_at is null
    ) into v_active_tenant_role;

    select exists(
      select 1
      from public.user_roles ur
      where ur.user_id=v_user_id
        and ur.revoked_at is null
        and ur.role<>'tenant'
    ) into v_other_active_role;
  end if;

  return jsonb_build_object(
    'organization_id',v_org,
    'property_id',v_property_id,
    'tenant_id',v_tenant_id,
    'target_user_id',v_user_id,
    'other_active_occupancy',v_other_active,
    'active_tenant_role',v_active_tenant_role,
    'other_active_role',v_other_active_role,
    'disable_auth',v_user_id is not null
      and not v_other_active
      and not v_active_tenant_role
      and not v_other_active_role
  );
end;
$$;

revoke all on function public.get_tenant_offboarding_auth_state_v1(uuid)
  from public,anon;
grant execute on function public.get_tenant_offboarding_auth_state_v1(uuid)
  to authenticated,service_role;

-- Mantiene la firma histórica para no romper Cartera.
create or replace function public.offboard_tenant_occupancy_v2(
  p_occupancy_id uuid,
  p_ends_on date
)
returns void
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare
  v_actor uuid:=auth.uid();
  v_tenant_id uuid;
  v_user_id uuid;
  v_org uuid;
  v_property_id uuid;
  v_status public.record_status;
  v_other_active boolean:=false;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if p_ends_on is null or p_ends_on<current_date then
    raise exception 'offboarding_end_invalid' using errcode='22023';
  end if;

  select o.tenant_id,coalesce(o.user_id,t.user_id),o.organization_id,o.property_id,o.status
  into v_tenant_id,v_user_id,v_org,v_property_id,v_status
  from public.occupancies_v2 o
  join public.tenants_v2 t on t.id=o.tenant_id
  where o.id=p_occupancy_id
  for update of o,t;

  if v_tenant_id is null then
    raise exception 'occupancy_not_found' using errcode='P0002';
  end if;
  if not (
    exists(
      select 1 from public.user_roles ur
      where ur.user_id=v_actor
        and ur.role='root'
        and ur.revoked_at is null
    )
    or exists(
      select 1 from public.user_roles ur
      where ur.user_id=v_actor
        and ur.organization_id=v_org
        and ur.role='admin'
        and ur.revoked_at is null
    )
    or exists(
      select 1 from public.property_staff_access_v3 a
      where a.property_id=v_property_id
        and a.employee_user_id=v_actor
        and a.revoked_at is null
        and (a.valid_until is null or a.valid_until>now())
        and a.can_write=true
    )
  ) then
    raise exception 'property_write_required' using errcode='42501';
  end if;
  if v_status not in ('active','blocked') then
    raise exception 'offboarding_invalid_state' using errcode='22023';
  end if;

  update public.occupancies_v2
  set status='archived',
      ends_on=p_ends_on,
      starts_on=case when v_status='blocked' then null else starts_on end
  where id=p_occupancy_id;

  update public.tenants_v2
  set status='archived',
      archived_at=coalesce(archived_at,now()),
      deletion_requested_at=coalesce(deletion_requested_at,now()),
      deletion_requested_by=coalesce(deletion_requested_by,v_actor),
      updated_at=now()
  where id=v_tenant_id;

  if v_user_id is not null then
    select exists(
      select 1
      from public.occupancies_v2 o
      join public.tenants_v2 t
        on t.id=o.tenant_id
       and t.organization_id=o.organization_id
       and t.user_id=v_user_id
       and t.status='active'
       and t.archived_at is null
      where o.organization_id=v_org
        and o.id<>p_occupancy_id
        and o.user_id=v_user_id
        and o.status='active'
        and o.starts_on is not null
        and o.starts_on<=current_date
        and (o.ends_on is null or o.ends_on>=current_date)
    ) into v_other_active;

    if not v_other_active then
      update public.user_roles
      set revoked_at=coalesce(revoked_at,now())
      where user_id=v_user_id
        and organization_id=v_org
        and role='tenant'
        and revoked_at is null;

      insert into public.audit_log_v2(
        organization_id,actor_user_id,action,entity_type,entity_id,result,details
      ) values(
        v_org,v_actor,'tenant_platform_access_revoked','tenant',v_tenant_id::text,'success',
        jsonb_build_object(
          'occupancy_id',p_occupancy_id,
          'auth_user_id',v_user_id,
          'reason','tenant_offboarding'
        )
      );
    end if;
  end if;
end;
$$;

revoke all on function public.offboard_tenant_occupancy_v2(uuid,date)
  from public,anon;
grant execute on function public.offboard_tenant_occupancy_v2(uuid,date)
  to authenticated,service_role;

-- Un JWT antiguo no debe saltarse la Baja mediante políticas self/assignee.
-- Restrictive = se combina con AND con las policies permisivas existentes.
do $platform_gate$
declare
  v_table text;
begin
  foreach v_table in array array[
    'access_requests',
    'claims_v2',
    'cleaning_debts_v2',
    'cleaning_swap_requests_v2',
    'notifications_v2',
    'occupancies_v2',
    'payment_obligations_v2',
    'photo_verification_items_v2',
    'photo_verification_runs_v2',
    'profiles',
    'random_photo_requests_v2',
    'tenant_documents_v2',
    'tenant_task_actions_v2',
    'tenant_task_history_v2',
    'tenant_tasks_v2',
    'tenants_v2',
    'user_roles',
    'workflow_execution_documents_v2',
    'workflow_execution_photo_resources_v2',
    'workflow_executions_v2'
  ]
  loop
    if to_regclass(format('public.%I',v_table)) is not null then
      execute format(
        'drop policy if exists platform_access_required_v1 on public.%I',
        v_table
      );
      execute format(
        'create policy platform_access_required_v1 on public.%I as restrictive for all to authenticated using (public.has_current_platform_access_v1()) with check (public.has_current_platform_access_v1())',
        v_table
      );
    end if;
  end loop;
end;
$platform_gate$;

-- Los buckets que contienen información operativa personal siguen la misma
-- autoridad DB. Otros buckets no se ven afectados.
drop policy if exists platform_access_required_v1 on storage.objects;
create policy platform_access_required_v1
on storage.objects
as restrictive
for all
to authenticated
using (
  bucket_id not in ('photo-verification','tenant-documents-v2','workflow-documents-v2')
  or public.has_current_platform_access_v1()
)
with check (
  bucket_id not in ('photo-verification','tenant-documents-v2','workflow-documents-v2')
  or public.has_current_platform_access_v1()
);
