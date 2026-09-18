-- Canonical administrative write authority for Gestión de Permisos.
-- ROOT always retains supervisory authority; exactly one ADMIN may hold write_control per organization.

alter table public.admin_capability_holders
  drop constraint if exists admin_capability_holders_capability_check;

alter table public.admin_capability_holders
  add constraint admin_capability_holders_capability_check
  check (capability in ('property_lifecycle','permission_management','write_control'));

alter table public.admin_capability_requests
  drop constraint if exists admin_capability_requests_capability_check;

alter table public.admin_capability_requests
  add constraint admin_capability_requests_capability_check
  check (capability in ('property_lifecycle','write_control'));

create or replace function public.can_manage_permissions(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1
    from public.user_roles ur
    where ur.user_id=auth.uid()
      and ur.role='root'
      and ur.revoked_at is null
  ) or exists(
    select 1
    from public.user_roles ur
    join public.admin_capability_holders h
      on h.organization_id=ur.organization_id
     and h.holder_user_id=ur.user_id
     and h.capability='write_control'
     and h.revoked_at is null
    where ur.user_id=auth.uid()
      and ur.organization_id=p_organization_id
      and ur.role='admin'
      and ur.revoked_at is null
  );
$$;

revoke all on function public.can_manage_permissions(uuid) from public;
revoke execute on function public.can_manage_permissions(uuid) from anon;
grant execute on function public.can_manage_permissions(uuid) to authenticated;
grant execute on function public.can_manage_permissions(uuid) to service_role;

create or replace function public.assign_initial_admin_write_control(
  p_organization_id uuid,
  p_admin_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_holder_id uuid;
  v_existing_holder uuid;
begin
  if v_actor is null then
    raise exception 'not_authenticated';
  end if;

  if not exists(
    select 1
    from public.user_roles
    where user_id=v_actor
      and role='root'
      and revoked_at is null
  ) then
    raise exception 'root_required';
  end if;

  if not exists(
    select 1
    from public.user_roles
    where user_id=p_admin_user_id
      and organization_id=p_organization_id
      and role='admin'
      and revoked_at is null
  ) then
    raise exception 'target_admin_required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':write_control',0));

  select holder_user_id into v_existing_holder
  from public.admin_capability_holders
  where organization_id=p_organization_id
    and capability='write_control'
    and revoked_at is null
  for update;

  if v_existing_holder is not null then
    raise exception 'write_control_already_assigned';
  end if;

  insert into public.admin_capability_holders(
    organization_id,capability,holder_user_id,granted_by
  )
  values(
    p_organization_id,'write_control',p_admin_user_id,v_actor
  )
  returning id into v_holder_id;

  update public.admin_capability_requests
  set status='approved',decided_at=now(),decided_by=v_actor
  where organization_id=p_organization_id
    and capability='write_control'
    and requester_user_id=p_admin_user_id
    and status='pending';

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  )
  values(
    p_organization_id,v_actor,'assign_initial_admin_write_control',
    'admin_capability_holder',v_holder_id::text,'success',
    jsonb_build_object('holder_user_id',p_admin_user_id,'capability','write_control')
  );

  return v_holder_id;
end
$$;

revoke all on function public.assign_initial_admin_write_control(uuid,uuid) from public;
revoke execute on function public.assign_initial_admin_write_control(uuid,uuid) from anon;
grant execute on function public.assign_initial_admin_write_control(uuid,uuid) to authenticated;
