-- Responsibility resolution for internal staff removal and explicit unassignment.
-- Historical rows are preserved by revocation; no assignment history is hard-deleted.

create or replace function public.assign_property_responsible_v3(
  p_property_id uuid,
  p_employee_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_org uuid;
  v_id uuid;
  v_old uuid;
begin
  if v_actor is null then raise exception 'not_authenticated'; end if;

  select organization_id into v_org
  from public.properties_v2
  where id=p_property_id and archived_at is null
  for update;

  if v_org is null then raise exception 'property_not_found_or_archived'; end if;

  if not exists(
    select 1 from public.user_roles
    where user_id=v_actor and role='root' and revoked_at is null
  ) then
    if not exists(
      select 1 from public.user_roles
      where user_id=v_actor and organization_id=v_org
        and role='admin' and revoked_at is null
    ) then
      raise exception 'not_authorized';
    end if;

    if not exists(
      select 1 from public.admin_capability_holders
      where organization_id=v_org
        and capability='write_control'
        and holder_user_id=v_actor
        and revoked_at is null
    ) then
      raise exception 'write_control_required';
    end if;
  end if;

  if p_employee_user_id is not null and not exists(
    select 1 from public.user_roles
    where user_id=p_employee_user_id
      and organization_id=v_org
      and role in ('employee','admin')
      and revoked_at is null
  ) then
    raise exception 'target_not_eligible';
  end if;

  select id,employee_user_id into v_id,v_old
  from public.property_staff_access_v3
  where property_id=p_property_id
    and assignment_type='responsible'
    and revoked_at is null
  for update;

  if p_employee_user_id is null then
    if v_id is null then return null; end if;

    update public.property_staff_access_v3
    set revoked_at=now()
    where id=v_id and revoked_at is null;

    insert into public.audit_log_v2(
      organization_id,actor_user_id,action,entity_type,entity_id,result,details
    )
    values(
      v_org,v_actor,'unassign_property_responsible','property',
      p_property_id::text,'success',
      jsonb_build_object(
        'previous_responsible_user_id',v_old,
        'assignment_id',v_id
      )
    );

    return v_id;
  end if;

  if v_id is not null and v_old=p_employee_user_id then return v_id; end if;

  -- A responsible person does not also need a duplicate additional-access row.
  update public.property_staff_access_v3
  set revoked_at=now()
  where property_id=p_property_id
    and employee_user_id=p_employee_user_id
    and assignment_type='access'
    and revoked_at is null;

  update public.property_staff_access_v3
  set revoked_at=now()
  where property_id=p_property_id
    and assignment_type='responsible'
    and revoked_at is null;

  insert into public.property_staff_access_v3(
    organization_id,property_id,employee_user_id,assignment_type,
    can_write,valid_from,valid_until,granted_by,revoked_at
  )
  values(
    v_org,p_property_id,p_employee_user_id,'responsible',
    true,now(),null,v_actor,null
  )
  returning id into v_id;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  )
  values(
    v_org,v_actor,'assign_property_responsible','property',
    p_property_id::text,'success',
    jsonb_build_object(
      'responsible_user_id',p_employee_user_id,
      'assignment_id',v_id,
      'previous_responsible_user_id',v_old
    )
  );

  return v_id;
end
$$;

revoke all on function public.assign_property_responsible_v3(uuid,uuid) from public;
revoke execute on function public.assign_property_responsible_v3(uuid,uuid) from anon;
grant execute on function public.assign_property_responsible_v3(uuid,uuid) to authenticated;
grant execute on function public.assign_property_responsible_v3(uuid,uuid) to service_role;

create or replace function public.deactivate_internal_staff_user_v2(
  p_organization_id uuid,
  p_target_user_id uuid,
  p_responsibility_mode text default 'block',
  p_replacement_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_actor uuid:=auth.uid();
  v_responsibility_count integer:=0;
  v_result jsonb;
begin
  if v_actor is null then raise exception 'not_authenticated'; end if;
  if p_organization_id is null or p_target_user_id is null then
    raise exception 'invalid_staff_target';
  end if;
  if p_target_user_id=v_actor then raise exception 'self_deactivation_not_allowed'; end if;
  if p_responsibility_mode not in ('block','unassign','reassign') then
    raise exception 'invalid_responsibility_mode';
  end if;
  if not public.can_manage_permissions(p_organization_id) then
    raise exception 'permission_management_required';
  end if;

  if not exists(
    select 1 from public.user_roles
    where user_id=p_target_user_id
      and organization_id=p_organization_id
      and role in ('admin','employee')
      and revoked_at is null
  ) then
    raise exception 'target_internal_staff_required';
  end if;

  if exists(
    select 1 from public.admin_capability_holders
    where organization_id=p_organization_id
      and holder_user_id=p_target_user_id
      and capability='write_control'
      and revoked_at is null
  ) then
    raise exception 'staff_write_control_transfer_required';
  end if;

  -- Serialize removal for this staff member and lock affected active properties.
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':staff:'||p_target_user_id::text,0));
  perform p.id
  from public.properties_v2 p
  join public.property_staff_access_v3 a on a.property_id=p.id
  where p.organization_id=p_organization_id
    and p.archived_at is null
    and a.employee_user_id=p_target_user_id
    and a.assignment_type='responsible'
    and a.revoked_at is null
  for update of p,a;

  select count(*) into v_responsibility_count
  from public.property_staff_access_v3 a
  join public.properties_v2 p on p.id=a.property_id
  where p.organization_id=p_organization_id
    and p.archived_at is null
    and a.employee_user_id=p_target_user_id
    and a.assignment_type='responsible'
    and a.revoked_at is null;

  if v_responsibility_count>0 then
    if p_responsibility_mode='block' then
      raise exception 'staff_responsible_reassignment_required';
    end if;

    if p_responsibility_mode='reassign' then
      if p_replacement_user_id is null or p_replacement_user_id=p_target_user_id then
        raise exception 'replacement_staff_required';
      end if;
      if not exists(
        select 1 from public.user_roles
        where user_id=p_replacement_user_id
          and organization_id=p_organization_id
          and role in ('admin','employee')
          and revoked_at is null
      ) then
        raise exception 'replacement_not_eligible';
      end if;

      -- Remove redundant additional access for the incoming responsible person.
      update public.property_staff_access_v3
      set revoked_at=now()
      where employee_user_id=p_replacement_user_id
        and assignment_type='access'
        and revoked_at is null
        and property_id in (
          select a.property_id
          from public.property_staff_access_v3 a
          join public.properties_v2 p on p.id=a.property_id
          where p.organization_id=p_organization_id
            and p.archived_at is null
            and a.employee_user_id=p_target_user_id
            and a.assignment_type='responsible'
            and a.revoked_at is null
        );

      with affected as materialized (
        select a.property_id
        from public.property_staff_access_v3 a
        join public.properties_v2 p on p.id=a.property_id
        where p.organization_id=p_organization_id
          and p.archived_at is null
          and a.employee_user_id=p_target_user_id
          and a.assignment_type='responsible'
          and a.revoked_at is null
      ), revoked as (
        update public.property_staff_access_v3 a
        set revoked_at=now()
        where a.property_id in (select property_id from affected)
          and a.employee_user_id=p_target_user_id
          and a.assignment_type='responsible'
          and a.revoked_at is null
        returning a.property_id
      )
      insert into public.property_staff_access_v3(
        organization_id,property_id,employee_user_id,assignment_type,
        can_write,valid_from,valid_until,granted_by,revoked_at
      )
      select p_organization_id,r.property_id,p_replacement_user_id,'responsible',
             true,now(),null,v_actor,null
      from revoked r;
    else
      update public.property_staff_access_v3 a
      set revoked_at=now()
      where a.employee_user_id=p_target_user_id
        and a.assignment_type='responsible'
        and a.revoked_at is null
        and a.property_id in (
          select id from public.properties_v2
          where organization_id=p_organization_id and archived_at is null
        );
    end if;

    insert into public.audit_log_v2(
      organization_id,actor_user_id,action,entity_type,entity_id,result,details
    )
    values(
      p_organization_id,v_actor,'resolve_staff_responsibilities_for_deactivation',
      'user',p_target_user_id::text,'success',
      jsonb_build_object(
        'target_user_id',p_target_user_id,
        'responsibility_count',v_responsibility_count,
        'mode',p_responsibility_mode,
        'replacement_user_id',p_replacement_user_id
      )
    );
  end if;

  -- Reuse the established deactivation contract. Because this call is in the same
  -- transaction, responsibility resolution and staff deactivation commit atomically.
  v_result:=public.deactivate_internal_staff_user(p_organization_id,p_target_user_id);

  return v_result || jsonb_build_object(
    'resolved_responsibilities',v_responsibility_count,
    'responsibility_mode',p_responsibility_mode,
    'replacement_user_id',p_replacement_user_id
  );
end
$$;

revoke all on function public.deactivate_internal_staff_user_v2(uuid,uuid,text,uuid) from public;
revoke execute on function public.deactivate_internal_staff_user_v2(uuid,uuid,text,uuid) from anon;
grant execute on function public.deactivate_internal_staff_user_v2(uuid,uuid,text,uuid) to authenticated;
grant execute on function public.deactivate_internal_staff_user_v2(uuid,uuid,text,uuid) to service_role;
