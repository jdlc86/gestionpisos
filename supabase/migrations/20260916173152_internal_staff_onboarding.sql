-- Professional onboarding for internal staff.
-- Pending identities have no active internal role or property access until they
-- prove control of their email, choose their own password and complete activation.

create table if not exists public.internal_staff_onboarding (
  user_id uuid primary key references auth.users(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  intended_role public.app_role not null,
  status text not null default 'pending',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  last_invitation_attempt_at timestamptz,
  invited_at timestamptz,
  invite_count integer not null default 0,
  activated_at timestamptz,
  revoked_at timestamptz,
  updated_at timestamptz not null default now(),
  last_delivery_status text,
  last_delivery_error text,
  constraint internal_staff_onboarding_role_check check (intended_role in ('admin'::public.app_role,'employee'::public.app_role)),
  constraint internal_staff_onboarding_status_check check (status in ('pending','active','revoked')),
  constraint internal_staff_onboarding_invite_count_check check (invite_count >= 0)
);

create index if not exists internal_staff_onboarding_org_status_idx
  on public.internal_staff_onboarding(organization_id,status);

alter table public.internal_staff_onboarding enable row level security;
revoke all on table public.internal_staff_onboarding from public, anon, authenticated;
grant select,insert,update,delete on table public.internal_staff_onboarding to service_role;

create table if not exists public.internal_staff_onboarding_access_snapshot (
  user_id uuid not null references auth.users(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  property_id uuid not null references public.properties_v2(id) on delete restrict,
  assignment_type text not null,
  can_write boolean not null,
  valid_until timestamptz,
  original_assignment_id uuid not null,
  created_at timestamptz not null default now(),
  restored_at timestamptz,
  restore_result text,
  primary key(user_id,property_id,assignment_type),
  constraint internal_staff_onboarding_snapshot_type_check check (assignment_type in ('responsible','access'))
);

alter table public.internal_staff_onboarding_access_snapshot enable row level security;
revoke all on table public.internal_staff_onboarding_access_snapshot from public, anon, authenticated;
grant select,insert,update,delete on table public.internal_staff_onboarding_access_snapshot to service_role;

create or replace function public.provision_internal_staff_pending(
  p_user_id uuid,
  p_email text,
  p_display_name text,
  p_organization_id uuid,
  p_role public.app_role default 'employee'::public.app_role,
  p_created_by uuid default null
)
returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode='42501';
  end if;
  if p_role not in ('admin'::public.app_role,'employee'::public.app_role) then
    raise exception 'internal_staff_role_required' using errcode='22023';
  end if;
  if exists(
    select 1 from public.user_roles
    where user_id=p_user_id
      and organization_id=p_organization_id
      and role in ('admin','employee')
      and revoked_at is null
  ) then
    raise exception 'active_internal_staff_already_exists';
  end if;

  insert into public.profiles(user_id,organization_id,display_name,email,status)
  values(p_user_id,p_organization_id,nullif(trim(p_display_name),''),lower(trim(p_email)),'active')
  on conflict(user_id) do update
    set organization_id=excluded.organization_id,
        display_name=excluded.display_name,
        email=excluded.email,
        status='active',
        archived_at=null,
        updated_at=now();

  insert into public.internal_staff_onboarding(
    user_id,organization_id,intended_role,status,created_by,created_at,updated_at
  ) values(
    p_user_id,p_organization_id,p_role,'pending',p_created_by,now(),now()
  )
  on conflict(user_id) do update
    set organization_id=excluded.organization_id,
        intended_role=excluded.intended_role,
        status='pending',
        created_by=coalesce(public.internal_staff_onboarding.created_by,excluded.created_by),
        revoked_at=null,
        activated_at=null,
        updated_at=now();

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values(
    p_organization_id,p_created_by,'create_internal_staff_pending','user',p_user_id::text,'success',
    jsonb_build_object('intended_role',p_role::text,'email',lower(trim(p_email)))
  );
end
$$;

revoke all on function public.provision_internal_staff_pending(uuid,text,text,uuid,public.app_role,uuid) from public, anon, authenticated;
grant execute on function public.provision_internal_staff_pending(uuid,text,text,uuid,public.app_role,uuid) to service_role;

create or replace function public.claim_internal_staff_invitation_attempt(
  p_user_id uuid,
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_cooldown_seconds integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_last timestamptz;
  v_retry integer:=0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode='42501';
  end if;
  if p_cooldown_seconds < 0 or p_cooldown_seconds > 3600 then
    raise exception 'invalid_cooldown';
  end if;

  select last_invitation_attempt_at into v_last
  from public.internal_staff_onboarding
  where user_id=p_user_id and organization_id=p_organization_id and status='pending'
  for update;

  if not found then raise exception 'pending_onboarding_required'; end if;

  if v_last is not null and v_last + make_interval(secs=>p_cooldown_seconds) > now() then
    v_retry:=greatest(1,ceil(extract(epoch from (v_last + make_interval(secs=>p_cooldown_seconds) - now())))::integer);
    return jsonb_build_object('allowed',false,'retry_after_seconds',v_retry);
  end if;

  update public.internal_staff_onboarding
  set last_invitation_attempt_at=now(),updated_at=now()
  where user_id=p_user_id;

  return jsonb_build_object('allowed',true,'retry_after_seconds',0,'actor_user_id',p_actor_user_id);
end
$$;

revoke all on function public.claim_internal_staff_invitation_attempt(uuid,uuid,uuid,integer) from public, anon, authenticated;
grant execute on function public.claim_internal_staff_invitation_attempt(uuid,uuid,uuid,integer) to service_role;

create or replace function public.record_internal_staff_invitation_result(
  p_user_id uuid,
  p_organization_id uuid,
  p_actor_user_id uuid,
  p_status text,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode='42501';
  end if;
  if p_status not in ('sent','failed','not_configured') then
    raise exception 'invalid_delivery_status';
  end if;

  update public.internal_staff_onboarding
  set invited_at=case when p_status='sent' then now() else invited_at end,
      invite_count=invite_count + case when p_status='sent' then 1 else 0 end,
      last_delivery_status=p_status,
      last_delivery_error=case when p_error is null then null else left(p_error,240) end,
      updated_at=now()
  where user_id=p_user_id and organization_id=p_organization_id and status='pending';

  if not found then raise exception 'pending_onboarding_required'; end if;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values(
    p_organization_id,p_actor_user_id,'send_internal_staff_invitation','user',p_user_id::text,
    case when p_status='sent' then 'success' else 'failure' end,
    jsonb_build_object('delivery_status',p_status,'error',case when p_error is null then null else left(p_error,240) end)
  );
end
$$;

revoke all on function public.record_internal_staff_invitation_result(uuid,uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.record_internal_staff_invitation_result(uuid,uuid,uuid,text,text) to service_role;

create or replace function public.get_my_internal_staff_onboarding()
returns jsonb
language sql
stable
security definer
set search_path to 'public','pg_temp'
as $$
  select case when o.user_id is null then null else jsonb_build_object(
    'user_id',o.user_id,
    'organization_id',o.organization_id,
    'intended_role',o.intended_role::text,
    'status',o.status,
    'invited_at',o.invited_at,
    'activated_at',o.activated_at
  ) end
  from (select auth.uid() as user_id) me
  left join public.internal_staff_onboarding o on o.user_id=me.user_id;
$$;

revoke all on function public.get_my_internal_staff_onboarding() from public, anon;
grant execute on function public.get_my_internal_staff_onboarding() to authenticated, service_role;

create or replace function public.complete_internal_staff_onboarding()
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_user uuid:=auth.uid();
  v_org uuid;
  v_role public.app_role;
  v_status text;
  v_snapshot record;
  v_restored integer:=0;
  v_skipped integer:=0;
begin
  if v_user is null then raise exception 'not_authenticated'; end if;

  select organization_id,intended_role,status into v_org,v_role,v_status
  from public.internal_staff_onboarding
  where user_id=v_user
  for update;

  if not found then raise exception 'onboarding_not_found'; end if;
  if v_status='revoked' then raise exception 'onboarding_revoked'; end if;
  if v_status='active' then
    return jsonb_build_object('ok',true,'status','active','already_active',true);
  end if;

  if not exists(select 1 from public.profiles where user_id=v_user and status='active' and archived_at is null) then
    raise exception 'active_profile_required';
  end if;
  if exists(
    select 1 from public.user_roles
    where user_id=v_user and organization_id=v_org
      and role in ('admin','employee') and revoked_at is null
  ) then
    raise exception 'onboarding_role_already_active';
  end if;

  update public.user_roles
  set revoked_at=null
  where user_id=v_user and organization_id=v_org and role=v_role and revoked_at is not null;

  if not found then
    insert into public.user_roles(user_id,organization_id,role,created_by)
    values(v_user,v_org,v_role,v_user);
  end if;

  for v_snapshot in
    select * from public.internal_staff_onboarding_access_snapshot
    where user_id=v_user and organization_id=v_org and restored_at is null
    order by case when assignment_type='responsible' then 0 else 1 end, property_id
    for update
  loop
    if not exists(
      select 1 from public.properties_v2
      where id=v_snapshot.property_id and organization_id=v_org and archived_at is null
    ) then
      update public.internal_staff_onboarding_access_snapshot
      set restored_at=now(),restore_result='skipped_property_unavailable'
      where user_id=v_user and property_id=v_snapshot.property_id and assignment_type=v_snapshot.assignment_type;
      v_skipped:=v_skipped+1;
      continue;
    end if;

    if v_snapshot.valid_until is not null and v_snapshot.valid_until <= now() then
      update public.internal_staff_onboarding_access_snapshot
      set restored_at=now(),restore_result='skipped_expired'
      where user_id=v_user and property_id=v_snapshot.property_id and assignment_type=v_snapshot.assignment_type;
      v_skipped:=v_skipped+1;
      continue;
    end if;

    if v_snapshot.assignment_type='responsible' then
      if exists(
        select 1 from public.property_staff_access_v3
        where property_id=v_snapshot.property_id and assignment_type='responsible' and revoked_at is null
      ) then
        update public.internal_staff_onboarding_access_snapshot
        set restored_at=now(),restore_result='skipped_responsible_conflict'
        where user_id=v_user and property_id=v_snapshot.property_id and assignment_type=v_snapshot.assignment_type;
        v_skipped:=v_skipped+1;
      else
        insert into public.property_staff_access_v3(
          organization_id,property_id,employee_user_id,assignment_type,can_write,valid_from,valid_until,granted_by,revoked_at
        ) values(v_org,v_snapshot.property_id,v_user,'responsible',true,now(),v_snapshot.valid_until,v_user,null);
        update public.internal_staff_onboarding_access_snapshot
        set restored_at=now(),restore_result='restored'
        where user_id=v_user and property_id=v_snapshot.property_id and assignment_type=v_snapshot.assignment_type;
        v_restored:=v_restored+1;
      end if;
    else
      if exists(
        select 1 from public.property_staff_access_v3
        where property_id=v_snapshot.property_id and employee_user_id=v_user
          and assignment_type='responsible' and revoked_at is null
      ) or exists(
        select 1 from public.property_staff_access_v3
        where property_id=v_snapshot.property_id and employee_user_id=v_user
          and assignment_type='access' and revoked_at is null
      ) then
        update public.internal_staff_onboarding_access_snapshot
        set restored_at=now(),restore_result='skipped_existing_access'
        where user_id=v_user and property_id=v_snapshot.property_id and assignment_type=v_snapshot.assignment_type;
        v_skipped:=v_skipped+1;
      else
        insert into public.property_staff_access_v3(
          organization_id,property_id,employee_user_id,assignment_type,can_write,valid_from,valid_until,granted_by,revoked_at
        ) values(v_org,v_snapshot.property_id,v_user,'access',v_snapshot.can_write,now(),v_snapshot.valid_until,v_user,null);
        update public.internal_staff_onboarding_access_snapshot
        set restored_at=now(),restore_result='restored'
        where user_id=v_user and property_id=v_snapshot.property_id and assignment_type=v_snapshot.assignment_type;
        v_restored:=v_restored+1;
      end if;
    end if;
  end loop;

  update public.internal_staff_onboarding
  set status='active',activated_at=coalesce(activated_at,now()),revoked_at=null,updated_at=now()
  where user_id=v_user;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values(
    v_org,v_user,'complete_internal_staff_onboarding','user',v_user::text,'success',
    jsonb_build_object('role',v_role::text,'restored_property_assignments',v_restored,'skipped_property_assignments',v_skipped)
  );

  return jsonb_build_object(
    'ok',true,'status','active','role',v_role::text,
    'restored_property_assignments',v_restored,'skipped_property_assignments',v_skipped
  );
end
$$;

revoke all on function public.complete_internal_staff_onboarding() from public, anon;
grant execute on function public.complete_internal_staff_onboarding() to authenticated, service_role;

create or replace function public.get_permission_management_context(p_organization_id uuid default null::uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_actor uuid:=auth.uid();
  v_org uuid:=p_organization_id;
  v_is_root boolean:=false;
  v_is_admin boolean:=false;
  v_result jsonb;
begin
  if v_actor is null then raise exception 'not_authenticated'; end if;
  select exists(select 1 from public.user_roles where user_id=v_actor and role='root' and revoked_at is null) into v_is_root;
  if v_org is null then
    select organization_id into v_org from public.user_roles
    where user_id=v_actor and organization_id is not null and revoked_at is null
    order by case when role='admin' then 0 else 1 end,created_at limit 1;
  end if;
  if v_org is null then select organization_id into v_org from public.profiles where user_id=v_actor and archived_at is null; end if;
  if v_org is null then raise exception 'organization_required'; end if;
  select exists(select 1 from public.user_roles where user_id=v_actor and organization_id=v_org and role='admin' and revoked_at is null) into v_is_admin;
  if not v_is_root and not v_is_admin then raise exception 'not_authorized'; end if;

  select jsonb_build_object(
    'organization_id',v_org,
    'actor',jsonb_build_object('user_id',v_actor,'is_root',v_is_root,'is_admin',v_is_admin),
    'people',coalesce((
      select jsonb_agg(x order by x->>'display_name',x->>'email') from (
        select jsonb_build_object(
          'user_id',u.user_id,
          'display_name',p.display_name,
          'email',p.email,
          'profile_status',p.status,
          'roles',u.roles,
          'onboarding_status',u.onboarding_status,
          'onboarding_invited_at',u.invited_at,
          'onboarding_invite_count',u.invite_count,
          'onboarding_last_delivery_status',u.last_delivery_status,
          'onboarding_activated_at',u.activated_at
        ) x
        from (
          select ur.user_id,
                 jsonb_agg(ur.role::text order by ur.role::text) roles,
                 coalesce((select o.status from public.internal_staff_onboarding o where o.user_id=ur.user_id),'active') onboarding_status,
                 (select o.invited_at from public.internal_staff_onboarding o where o.user_id=ur.user_id) invited_at,
                 coalesce((select o.invite_count from public.internal_staff_onboarding o where o.user_id=ur.user_id),0) invite_count,
                 (select o.last_delivery_status from public.internal_staff_onboarding o where o.user_id=ur.user_id) last_delivery_status,
                 (select o.activated_at from public.internal_staff_onboarding o where o.user_id=ur.user_id) activated_at
          from public.user_roles ur
          where ur.organization_id=v_org and ur.revoked_at is null and ur.role in ('admin','employee')
          group by ur.user_id
          union all
          select o.user_id,jsonb_build_array(o.intended_role::text),o.status,o.invited_at,o.invite_count,o.last_delivery_status,o.activated_at
          from public.internal_staff_onboarding o
          where o.organization_id=v_org and o.status='pending'
            and not exists(
              select 1 from public.user_roles ur
              where ur.user_id=o.user_id and ur.organization_id=v_org
                and ur.role in ('admin','employee') and ur.revoked_at is null
            )
        ) u
        left join public.profiles p on p.user_id=u.user_id
      ) q
    ),'[]'::jsonb),
    'properties',coalesce((select jsonb_agg(jsonb_build_object(
      'id',pr.id,'name',pr.name,'address_line',pr.address_line,'city',pr.city,'status',pr.status,
      'responsible_user_id',sa.employee_user_id,'assignment_id',sa.id,
      'staff_access',coalesce((select jsonb_agg(jsonb_build_object('id',pa.id,'employee_user_id',pa.employee_user_id,'can_write',pa.can_write) order by pa.employee_user_id)
        from public.property_staff_access_v3 pa where pa.property_id=pr.id and pa.assignment_type='access' and pa.revoked_at is null),'[]'::jsonb)
    ) order by pr.name)
    from public.properties_v2 pr
    left join public.property_staff_access_v3 sa on sa.property_id=pr.id and sa.assignment_type='responsible' and sa.revoked_at is null
    where pr.organization_id=v_org and pr.archived_at is null),'[]'::jsonb),
    'capability_holders',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'capability',h.capability,'holder_user_id',h.holder_user_id,'granted_at',h.granted_at) order by h.capability)
      from public.admin_capability_holders h where h.organization_id=v_org and h.revoked_at is null),'[]'::jsonb),
    'pending_requests',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'capability',r.capability,'requester_user_id',r.requester_user_id,'requested_at',r.requested_at) order by r.requested_at)
      from public.admin_capability_requests r where r.organization_id=v_org and r.status='pending'),'[]'::jsonb)
  ) into v_result;
  return v_result;
end
$$;

revoke all on function public.get_permission_management_context(uuid) from public, anon;
grant execute on function public.get_permission_management_context(uuid) to authenticated, service_role;

create or replace function public.deactivate_internal_staff_user(p_organization_id uuid,p_target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_actor uuid:=auth.uid();
  v_role_count integer:=0;
  v_access_count integer:=0;
  v_capability_count integer:=0;
  v_request_count integer:=0;
  v_profile_archived boolean:=false;
  v_onboarding_revoked boolean:=false;
begin
  if v_actor is null then raise exception 'not_authenticated'; end if;
  if p_target_user_id is null or p_organization_id is null then raise exception 'invalid_staff_target'; end if;
  if p_target_user_id=v_actor then raise exception 'self_deactivation_not_allowed'; end if;
  if not public.can_manage_permissions(p_organization_id) then raise exception 'permission_management_required'; end if;

  if not exists(
    select 1 from public.user_roles ur
    where ur.user_id=p_target_user_id and ur.organization_id=p_organization_id
      and ur.role in ('admin','employee') and ur.revoked_at is null
  ) and not exists(
    select 1 from public.internal_staff_onboarding o
    where o.user_id=p_target_user_id and o.organization_id=p_organization_id and o.status='pending'
  ) then
    raise exception 'target_internal_staff_required';
  end if;

  if exists(
    select 1 from public.property_staff_access_v3 a
    join public.properties_v2 p on p.id=a.property_id
    where a.employee_user_id=p_target_user_id and a.assignment_type='responsible'
      and a.revoked_at is null and p.organization_id=p_organization_id and p.archived_at is null
  ) then raise exception 'staff_responsible_reassignment_required'; end if;

  if exists(
    select 1 from public.admin_capability_holders h
    where h.organization_id=p_organization_id and h.holder_user_id=p_target_user_id
      and h.capability='write_control' and h.revoked_at is null
  ) then raise exception 'staff_write_control_transfer_required'; end if;

  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text||':staff:'||p_target_user_id::text,0));

  update public.property_staff_access_v3
  set revoked_at=now()
  where employee_user_id=p_target_user_id and assignment_type='access' and revoked_at is null
    and property_id in (select id from public.properties_v2 where organization_id=p_organization_id);
  get diagnostics v_access_count = row_count;

  update public.admin_capability_requests
  set status='cancelled',decided_at=now(),decided_by=v_actor
  where organization_id=p_organization_id and requester_user_id=p_target_user_id and status='pending';
  get diagnostics v_request_count = row_count;

  update public.admin_capability_holders
  set revoked_at=now()
  where organization_id=p_organization_id and holder_user_id=p_target_user_id and revoked_at is null;
  get diagnostics v_capability_count = row_count;

  update public.user_roles
  set revoked_at=now()
  where user_id=p_target_user_id and organization_id=p_organization_id
    and role in ('admin','employee') and revoked_at is null;
  get diagnostics v_role_count = row_count;

  update public.internal_staff_onboarding
  set status='revoked',revoked_at=coalesce(revoked_at,now()),updated_at=now()
  where user_id=p_target_user_id and organization_id=p_organization_id and status<>'revoked';
  v_onboarding_revoked:=found;

  if not exists(select 1 from public.user_roles where user_id=p_target_user_id and revoked_at is null) then
    update public.profiles
    set status='archived',archived_at=coalesce(archived_at,now()),updated_at=now()
    where user_id=p_target_user_id;
    v_profile_archived:=found;
  end if;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values(
    p_organization_id,v_actor,'deactivate_internal_staff','user',p_target_user_id::text,'success',
    jsonb_build_object(
      'target_user_id',p_target_user_id,'revoked_roles',v_role_count,
      'revoked_property_access',v_access_count,'revoked_capabilities',v_capability_count,
      'cancelled_requests',v_request_count,'profile_archived',v_profile_archived,
      'onboarding_revoked',v_onboarding_revoked
    )
  );

  return jsonb_build_object(
    'ok',true,'target_user_id',p_target_user_id,'revoked_roles',v_role_count,
    'revoked_property_access',v_access_count,'revoked_capabilities',v_capability_count,
    'cancelled_requests',v_request_count,'profile_archived',v_profile_archived,
    'onboarding_revoked',v_onboarding_revoked
  );
end
$$;

revoke all on function public.deactivate_internal_staff_user(uuid,uuid) from public, anon;
grant execute on function public.deactivate_internal_staff_user(uuid,uuid) to authenticated, service_role;

create temporary table _internal_staff_onboarding_backfill on commit drop as
select ur.user_id,ur.organization_id,ur.role,ur.created_by
from public.user_roles ur
join auth.users au on au.id=ur.user_id
where ur.role='employee'::public.app_role
  and ur.revoked_at is null
  and au.last_sign_in_at is null
  and au.created_at >= timestamptz '2026-09-16 16:50:00+00'
  and au.created_at <  timestamptz '2026-09-16 17:10:00+00'
  and not exists(select 1 from public.internal_staff_onboarding o where o.user_id=ur.user_id)
  and not exists(select 1 from public.admin_capability_holders h where h.holder_user_id=ur.user_id and h.revoked_at is null);

insert into public.internal_staff_onboarding(user_id,organization_id,intended_role,status,created_by,created_at,updated_at)
select user_id,organization_id,role,'pending',created_by,now(),now()
from _internal_staff_onboarding_backfill
on conflict(user_id) do nothing;

insert into public.internal_staff_onboarding_access_snapshot(
  user_id,organization_id,property_id,assignment_type,can_write,valid_until,original_assignment_id
)
select a.employee_user_id,a.organization_id,a.property_id,a.assignment_type,a.can_write,a.valid_until,a.id
from public.property_staff_access_v3 a
join _internal_staff_onboarding_backfill b on b.user_id=a.employee_user_id and b.organization_id=a.organization_id
where a.revoked_at is null and a.assignment_type in ('responsible','access')
on conflict(user_id,property_id,assignment_type) do nothing;

update public.property_staff_access_v3 a
set revoked_at=now()
where a.revoked_at is null
  and exists(
    select 1 from _internal_staff_onboarding_backfill b
    where b.user_id=a.employee_user_id and b.organization_id=a.organization_id
  );

update public.user_roles ur
set revoked_at=now()
where ur.revoked_at is null
  and exists(
    select 1 from _internal_staff_onboarding_backfill b
    where b.user_id=ur.user_id and b.organization_id=ur.organization_id and b.role=ur.role
  );

insert into public.audit_log_v2(organization_id,actor_user_id,action,entity_type,entity_id,result,details)
select b.organization_id,b.created_by,'backfill_internal_staff_onboarding','user',b.user_id::text,'success',
       jsonb_build_object('reason','legacy_no_password_onboarding','intended_role',b.role::text)
from _internal_staff_onboarding_backfill b;
