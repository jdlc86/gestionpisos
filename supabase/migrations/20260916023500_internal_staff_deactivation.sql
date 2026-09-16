-- Safe removal of internal agency staff.
-- We preserve history: removing a staff member revokes active authority/access and archives the profile
-- instead of deleting auth/database rows referenced by audit and operational history.

create or replace function public.deactivate_internal_staff_user(
  p_organization_id uuid,
  p_target_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_role_count integer:=0;
  v_access_count integer:=0;
  v_capability_count integer:=0;
  v_request_count integer:=0;
  v_profile_archived boolean:=false;
begin
  if v_actor is null then
    raise exception 'not_authenticated';
  end if;

  if p_target_user_id is null or p_organization_id is null then
    raise exception 'invalid_staff_target';
  end if;

  if p_target_user_id=v_actor then
    raise exception 'self_deactivation_not_allowed';
  end if;

  if not public.can_manage_permissions(p_organization_id) then
    raise exception 'permission_management_required';
  end if;

  if not exists(
    select 1
    from public.user_roles ur
    where ur.user_id=p_target_user_id
      and ur.organization_id=p_organization_id
      and ur.role in ('admin','employee')
      and ur.revoked_at is null
  ) then
    raise exception 'target_internal_staff_required';
  end if;

  -- A responsible property must be reassigned explicitly so removal never leaves an
  -- operational responsibility orphaned by surprise.
  if exists(
    select 1
    from public.property_staff_access_v3 a
    join public.properties_v2 p on p.id=a.property_id
    where a.employee_user_id=p_target_user_id
      and a.assignment_type='responsible'
      and a.revoked_at is null
      and p.organization_id=p_organization_id
      and p.archived_at is null
  ) then
    raise exception 'staff_responsible_reassignment_required';
  end if;

  -- The administrative write holder must first be revoked/transferred using the
  -- dedicated control flow, preserving the one-holder invariant and audit trail.
  if exists(
    select 1
    from public.admin_capability_holders h
    where h.organization_id=p_organization_id
      and h.holder_user_id=p_target_user_id
      and h.capability='write_control'
      and h.revoked_at is null
  ) then
    raise exception 'staff_write_control_transfer_required';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':staff:'||p_target_user_id::text,0));

  update public.property_staff_access_v3
  set revoked_at=now()
  where employee_user_id=p_target_user_id
    and assignment_type='access'
    and revoked_at is null
    and property_id in (
      select id from public.properties_v2 where organization_id=p_organization_id
    );
  get diagnostics v_access_count = row_count;

  update public.admin_capability_requests
  set status='cancelled',decided_at=now(),decided_by=v_actor
  where organization_id=p_organization_id
    and requester_user_id=p_target_user_id
    and status='pending';
  get diagnostics v_request_count = row_count;

  update public.admin_capability_holders
  set revoked_at=now()
  where organization_id=p_organization_id
    and holder_user_id=p_target_user_id
    and revoked_at is null;
  get diagnostics v_capability_count = row_count;

  update public.user_roles
  set revoked_at=now()
  where user_id=p_target_user_id
    and organization_id=p_organization_id
    and role in ('admin','employee')
    and revoked_at is null;
  get diagnostics v_role_count = row_count;

  -- Archive the profile only when no other active role remains. This avoids damaging
  -- a person who may legitimately have another non-staff role elsewhere in the model.
  if not exists(
    select 1 from public.user_roles
    where user_id=p_target_user_id and revoked_at is null
  ) then
    update public.profiles
    set status='archived',archived_at=coalesce(archived_at,now()),updated_at=now()
    where user_id=p_target_user_id;
    v_profile_archived:=found;
  end if;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  )
  values(
    p_organization_id,v_actor,'deactivate_internal_staff',
    'user',p_target_user_id::text,'success',
    jsonb_build_object(
      'target_user_id',p_target_user_id,
      'revoked_roles',v_role_count,
      'revoked_property_access',v_access_count,
      'revoked_capabilities',v_capability_count,
      'cancelled_requests',v_request_count,
      'profile_archived',v_profile_archived
    )
  );

  return jsonb_build_object(
    'ok',true,
    'target_user_id',p_target_user_id,
    'revoked_roles',v_role_count,
    'revoked_property_access',v_access_count,
    'revoked_capabilities',v_capability_count,
    'cancelled_requests',v_request_count,
    'profile_archived',v_profile_archived
  );
end
$$;

revoke all on function public.deactivate_internal_staff_user(uuid,uuid) from public;
revoke execute on function public.deactivate_internal_staff_user(uuid,uuid) from anon;
grant execute on function public.deactivate_internal_staff_user(uuid,uuid) to authenticated;
grant execute on function public.deactivate_internal_staff_user(uuid,uuid) to service_role;
