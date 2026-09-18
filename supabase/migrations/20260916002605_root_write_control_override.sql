create or replace function public.root_set_admin_write_control(
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
  v_current_holder_id uuid;
  v_current_holder_user_id uuid;
  v_new_holder_id uuid;
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

  if p_admin_user_id is not null and not exists(
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

  select id,holder_user_id
  into v_current_holder_id,v_current_holder_user_id
  from public.admin_capability_holders
  where organization_id=p_organization_id
    and capability='write_control'
    and revoked_at is null
  for update;

  if p_admin_user_id is not null and v_current_holder_user_id=p_admin_user_id then
    return v_current_holder_id;
  end if;

  update public.admin_capability_holders
  set revoked_at=now()
  where organization_id=p_organization_id
    and capability='write_control'
    and revoked_at is null;

  if p_admin_user_id is null then
    insert into public.audit_log_v2(
      organization_id,actor_user_id,action,entity_type,entity_id,result,details
    ) values(
      p_organization_id,v_actor,'root_revoke_admin_write_control',
      'admin_capability_holder',coalesce(v_current_holder_id::text,p_organization_id::text),'success',
      jsonb_build_object('previous_holder_user_id',v_current_holder_user_id,'capability','write_control')
    );
    return null;
  end if;

  insert into public.admin_capability_holders(
    organization_id,capability,holder_user_id,granted_by
  ) values(
    p_organization_id,'write_control',p_admin_user_id,v_actor
  ) returning id into v_new_holder_id;

  update public.admin_capability_requests
  set status='approved',decided_at=now(),decided_by=v_actor
  where organization_id=p_organization_id
    and capability='write_control'
    and requester_user_id=p_admin_user_id
    and status='pending';

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values(
    p_organization_id,v_actor,'root_transfer_admin_write_control',
    'admin_capability_holder',v_new_holder_id::text,'success',
    jsonb_build_object(
      'previous_holder_user_id',v_current_holder_user_id,
      'holder_user_id',p_admin_user_id,
      'capability','write_control'
    )
  );

  return v_new_holder_id;
end
$$;

revoke all on function public.root_set_admin_write_control(uuid,uuid) from public;
revoke execute on function public.root_set_admin_write_control(uuid,uuid) from anon;
grant execute on function public.root_set_admin_write_control(uuid,uuid) to authenticated;
