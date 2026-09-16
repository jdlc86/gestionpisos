-- Professional onboarding for external owner and tenant identities.
-- Business records remain independent from Auth until an explicit welcome is sent.

create table if not exists public.external_account_onboarding (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  subject_type text not null,
  owner_id uuid references public.owners(id) on delete restrict,
  tenant_id uuid references public.tenants_v2(id) on delete restrict,
  auth_user_id uuid not null unique references auth.users(id) on delete restrict,
  email text not null,
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
  constraint external_account_onboarding_subject_type_check check (subject_type in ('owner','tenant')),
  constraint external_account_onboarding_role_check check (intended_role in ('owner'::public.app_role,'tenant'::public.app_role)),
  constraint external_account_onboarding_status_check check (status in ('pending','active','revoked')),
  constraint external_account_onboarding_invite_count_check check (invite_count >= 0),
  constraint external_account_onboarding_subject_check check (
    (subject_type='owner' and owner_id is not null and tenant_id is null and intended_role='owner'::public.app_role)
    or
    (subject_type='tenant' and tenant_id is not null and owner_id is null and intended_role='tenant'::public.app_role)
  )
);

create unique index if not exists external_account_onboarding_current_owner_uidx
  on public.external_account_onboarding(owner_id)
  where owner_id is not null and status in ('pending','active');
create unique index if not exists external_account_onboarding_current_tenant_uidx
  on public.external_account_onboarding(tenant_id)
  where tenant_id is not null and status in ('pending','active');
create unique index if not exists external_account_onboarding_current_email_uidx
  on public.external_account_onboarding(lower(btrim(email)))
  where status in ('pending','active');
create index if not exists external_account_onboarding_org_status_idx
  on public.external_account_onboarding(organization_id,status);

alter table public.external_account_onboarding enable row level security;
revoke all on table public.external_account_onboarding from public, anon, authenticated;
grant select,insert,update,delete on table public.external_account_onboarding to service_role;

create or replace function public.provision_external_account_pending(
  p_auth_user_id uuid,
  p_subject_type text,
  p_subject_id uuid,
  p_created_by uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_org uuid;
  v_email text;
  v_name text;
  v_role public.app_role;
  v_onboarding_id uuid;
begin
  if auth.role() <> 'service_role' then raise exception 'service_role_required' using errcode='42501'; end if;
  if p_auth_user_id is null or p_subject_id is null or p_created_by is null then raise exception 'invalid_external_onboarding_target'; end if;

  if p_subject_type='owner' then
    select organization_id,lower(btrim(email)),full_name
      into v_org,v_email,v_name
    from public.owners
    where id=p_subject_id and archived_at is null and status='active' and email is not null and btrim(email)<>'';
    v_role:='owner'::public.app_role;
  elsif p_subject_type='tenant' then
    select organization_id,lower(btrim(email)),full_name
      into v_org,v_email,v_name
    from public.tenants_v2
    where id=p_subject_id and archived_at is null and status='active';
    v_role:='tenant'::public.app_role;
  else
    raise exception 'invalid_external_subject_type';
  end if;

  if v_org is null or v_email is null or v_email='' then raise exception 'external_subject_not_available'; end if;

  if exists(select 1 from public.user_roles where user_id=p_auth_user_id and revoked_at is null) then
    raise exception 'auth_identity_role_conflict';
  end if;
  if exists(select 1 from public.internal_staff_onboarding where user_id=p_auth_user_id and status in ('pending','active')) then
    raise exception 'auth_identity_internal_conflict';
  end if;
  if exists(
    select 1 from public.external_account_onboarding
    where status in ('pending','active')
      and lower(btrim(email))=v_email
      and auth_user_id<>p_auth_user_id
  ) then raise exception 'external_email_identity_conflict'; end if;

  insert into public.profiles(user_id,organization_id,display_name,email,status)
  values(p_auth_user_id,v_org,nullif(btrim(v_name),''),v_email,'active')
  on conflict(user_id) do update
    set organization_id=excluded.organization_id,
        display_name=excluded.display_name,
        email=excluded.email,
        status='active',archived_at=null,updated_at=now();

  insert into public.external_account_onboarding(
    organization_id,subject_type,owner_id,tenant_id,auth_user_id,email,intended_role,status,created_by
  ) values(
    v_org,p_subject_type,
    case when p_subject_type='owner' then p_subject_id else null end,
    case when p_subject_type='tenant' then p_subject_id else null end,
    p_auth_user_id,v_email,v_role,'pending',p_created_by
  ) returning id into v_onboarding_id;

  insert into public.audit_log_v2(organization_id,actor_user_id,action,entity_type,entity_id,result,details)
  values(v_org,p_created_by,'create_external_account_pending',p_subject_type,p_subject_id::text,'success',
    jsonb_build_object('auth_user_id',p_auth_user_id,'email',v_email,'role',v_role::text));

  return jsonb_build_object('id',v_onboarding_id,'organization_id',v_org,'email',v_email,'display_name',v_name,'role',v_role::text);
end
$$;
revoke all on function public.provision_external_account_pending(uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.provision_external_account_pending(uuid,text,uuid,uuid) to service_role;

create or replace function public.claim_external_invitation_attempt(
  p_auth_user_id uuid,
  p_actor_user_id uuid,
  p_cooldown_seconds integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare v_last timestamptz; v_retry integer:=0;
begin
  if auth.role() <> 'service_role' then raise exception 'service_role_required' using errcode='42501'; end if;
  if p_cooldown_seconds < 0 or p_cooldown_seconds > 3600 then raise exception 'invalid_cooldown'; end if;
  select last_invitation_attempt_at into v_last
  from public.external_account_onboarding
  where auth_user_id=p_auth_user_id and status='pending'
  for update;
  if not found then raise exception 'pending_external_onboarding_required'; end if;
  if v_last is not null and v_last + make_interval(secs=>p_cooldown_seconds) > now() then
    v_retry:=greatest(1,ceil(extract(epoch from (v_last + make_interval(secs=>p_cooldown_seconds)-now())))::integer);
    return jsonb_build_object('allowed',false,'retry_after_seconds',v_retry);
  end if;
  update public.external_account_onboarding set last_invitation_attempt_at=now(),updated_at=now()
  where auth_user_id=p_auth_user_id;
  return jsonb_build_object('allowed',true,'retry_after_seconds',0,'actor_user_id',p_actor_user_id);
end
$$;
revoke all on function public.claim_external_invitation_attempt(uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.claim_external_invitation_attempt(uuid,uuid,integer) to service_role;

create or replace function public.record_external_invitation_result(
  p_auth_user_id uuid,
  p_actor_user_id uuid,
  p_status text,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare v_org uuid; v_subject_type text; v_subject_id uuid;
begin
  if auth.role() <> 'service_role' then raise exception 'service_role_required' using errcode='42501'; end if;
  if p_status not in ('sent','failed','not_configured') then raise exception 'invalid_delivery_status'; end if;
  update public.external_account_onboarding
  set invited_at=case when p_status='sent' then now() else invited_at end,
      invite_count=invite_count+case when p_status='sent' then 1 else 0 end,
      last_delivery_status=p_status,
      last_delivery_error=case when p_error is null then null else left(p_error,240) end,
      updated_at=now()
  where auth_user_id=p_auth_user_id and status='pending'
  returning organization_id,subject_type,coalesce(owner_id,tenant_id) into v_org,v_subject_type,v_subject_id;
  if not found then raise exception 'pending_external_onboarding_required'; end if;
  insert into public.audit_log_v2(organization_id,actor_user_id,action,entity_type,entity_id,result,details)
  values(v_org,p_actor_user_id,'send_external_account_invitation',v_subject_type,v_subject_id::text,
    case when p_status='sent' then 'success' else 'failure' end,
    jsonb_build_object('auth_user_id',p_auth_user_id,'delivery_status',p_status,'error',case when p_error is null then null else left(p_error,240) end));
end
$$;
revoke all on function public.record_external_invitation_result(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.record_external_invitation_result(uuid,uuid,text,text) to service_role;

create or replace function public.get_my_external_account_onboarding()
returns jsonb
language sql
stable
security definer
set search_path to 'public','pg_temp'
as $$
  select case when o.id is null then null else jsonb_build_object(
    'id',o.id,'organization_id',o.organization_id,'subject_type',o.subject_type,
    'subject_id',coalesce(o.owner_id,o.tenant_id),'intended_role',o.intended_role::text,
    'status',o.status,'invited_at',o.invited_at,'activated_at',o.activated_at
  ) end
  from (select auth.uid() user_id) me
  left join lateral (
    select * from public.external_account_onboarding x
    where x.auth_user_id=me.user_id and x.status in ('pending','active')
    order by x.created_at desc limit 1
  ) o on true;
$$;
revoke all on function public.get_my_external_account_onboarding() from public,anon;
grant execute on function public.get_my_external_account_onboarding() to authenticated,service_role;

create or replace function public.complete_external_account_onboarding(p_auth_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_row public.external_account_onboarding;
  v_current_email text;
  v_subject_email text;
  v_role_count integer:=0;
begin
  if auth.role() <> 'service_role' then raise exception 'service_role_required' using errcode='42501'; end if;
  if p_auth_user_id is null then raise exception 'invalid_external_auth_user'; end if;

  select * into v_row from public.external_account_onboarding
  where auth_user_id=p_auth_user_id and status in ('pending','active')
  order by created_at desc limit 1 for update;
  if v_row.id is null then raise exception 'external_onboarding_not_found'; end if;
  if v_row.status='active' then
    return jsonb_build_object('ok',true,'status','active','already_active',true,'role',v_row.intended_role::text,'organization_id',v_row.organization_id);
  end if;

  select lower(btrim(email)) into v_current_email from auth.users where id=p_auth_user_id and deleted_at is null;
  if v_current_email is null or v_current_email<>lower(btrim(v_row.email)) then raise exception 'external_auth_email_mismatch'; end if;

  if exists(select 1 from public.internal_staff_onboarding where user_id=p_auth_user_id and status in ('pending','active')) then
    raise exception 'auth_identity_internal_conflict';
  end if;
  if exists(
    select 1 from public.user_roles
    where user_id=p_auth_user_id and revoked_at is null
      and (organization_id is distinct from v_row.organization_id or role<>v_row.intended_role)
  ) then raise exception 'auth_identity_role_conflict'; end if;

  if v_row.subject_type='owner' then
    select lower(btrim(email)) into v_subject_email from public.owners
    where id=v_row.owner_id and organization_id=v_row.organization_id and status='active' and archived_at is null for update;
    if v_subject_email is null or v_subject_email<>lower(btrim(v_row.email)) then raise exception 'owner_onboarding_subject_changed'; end if;
    if exists(select 1 from public.owners where id=v_row.owner_id and user_id is not null and user_id<>p_auth_user_id) then
      raise exception 'owner_auth_identity_conflict';
    end if;
    if exists(select 1 from public.tenants_v2 where user_id=p_auth_user_id and archived_at is null) then raise exception 'auth_identity_role_conflict'; end if;
    update public.owners set user_id=p_auth_user_id,updated_at=now() where id=v_row.owner_id;
  else
    select lower(btrim(email)) into v_subject_email from public.tenants_v2
    where id=v_row.tenant_id and organization_id=v_row.organization_id and status='active' and archived_at is null for update;
    if v_subject_email is null or v_subject_email<>lower(btrim(v_row.email)) then raise exception 'tenant_onboarding_subject_changed'; end if;
    if exists(select 1 from public.tenants_v2 where id=v_row.tenant_id and user_id is not null and user_id<>p_auth_user_id) then
      raise exception 'tenant_auth_identity_conflict';
    end if;
    if exists(select 1 from public.owners where user_id=p_auth_user_id and archived_at is null) then raise exception 'auth_identity_role_conflict'; end if;
    if exists(select 1 from public.occupancies_v2 where tenant_id=v_row.tenant_id and user_id is not null and user_id<>p_auth_user_id) then
      raise exception 'occupancy_auth_identity_conflict';
    end if;
    update public.tenants_v2 set user_id=p_auth_user_id,updated_at=now() where id=v_row.tenant_id;
    update public.occupancies_v2 set user_id=p_auth_user_id where tenant_id=v_row.tenant_id and (user_id is null or user_id=p_auth_user_id);
  end if;

  update public.user_roles set revoked_at=null
  where user_id=p_auth_user_id and organization_id=v_row.organization_id and role=v_row.intended_role and revoked_at is not null;
  get diagnostics v_role_count = row_count;
  if v_role_count=0 and not exists(
    select 1 from public.user_roles where user_id=p_auth_user_id and organization_id=v_row.organization_id and role=v_row.intended_role and revoked_at is null
  ) then
    insert into public.user_roles(user_id,organization_id,role,created_by)
    values(p_auth_user_id,v_row.organization_id,v_row.intended_role,p_auth_user_id);
  end if;

  update public.external_account_onboarding
  set status='active',activated_at=coalesce(activated_at,now()),updated_at=now()
  where id=v_row.id;

  insert into public.audit_log_v2(organization_id,actor_user_id,action,entity_type,entity_id,result,details)
  values(v_row.organization_id,p_auth_user_id,'complete_external_account_onboarding',v_row.subject_type,
    coalesce(v_row.owner_id,v_row.tenant_id)::text,'success',
    jsonb_build_object('auth_user_id',p_auth_user_id,'role',v_row.intended_role::text));

  return jsonb_build_object('ok',true,'status','active','role',v_row.intended_role::text,
    'organization_id',v_row.organization_id,'subject_type',v_row.subject_type,'subject_id',coalesce(v_row.owner_id,v_row.tenant_id));
end
$$;
revoke all on function public.complete_external_account_onboarding(uuid) from public,anon,authenticated;
grant execute on function public.complete_external_account_onboarding(uuid) to service_role;

create or replace function public.get_external_onboarding_statuses(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','pg_temp'
as $$
declare v_actor uuid:=auth.uid(); v_full boolean:=false; v_result jsonb;
begin
  if v_actor is null then raise exception 'not_authenticated'; end if;
  select exists(select 1 from public.user_roles where user_id=v_actor and role='root' and revoked_at is null)
    or exists(select 1 from public.user_roles where user_id=v_actor and organization_id=p_organization_id and role='admin' and revoked_at is null)
    into v_full;
  if not v_full and not exists(
    select 1 from public.property_staff_access_v3 a
    where a.organization_id=p_organization_id and a.employee_user_id=v_actor and a.revoked_at is null
      and (a.valid_until is null or a.valid_until>now())
  ) then raise exception 'not_authorized'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,'subject_type',o.subject_type,'subject_id',coalesce(o.owner_id,o.tenant_id),
    'status',o.status,'invited_at',o.invited_at,'invite_count',o.invite_count,
    'activated_at',o.activated_at,'last_delivery_status',o.last_delivery_status
  ) order by o.created_at),'[]'::jsonb) into v_result
  from public.external_account_onboarding o
  where o.organization_id=p_organization_id and o.status in ('pending','active')
    and (
      v_full
      or (o.subject_type='tenant' and exists(
        select 1 from public.occupancies_v2 oc
        where oc.tenant_id=o.tenant_id and public.can_operate_property_v3(oc.property_id,false)
      ))
    );
  return v_result;
end
$$;
revoke all on function public.get_external_onboarding_statuses(uuid) from public,anon;
grant execute on function public.get_external_onboarding_statuses(uuid) to authenticated,service_role;

-- External tenants can read their own canonical identity and documents after activation.
drop policy if exists tenants_v2_self_read on public.tenants_v2;
create policy tenants_v2_self_read on public.tenants_v2 for select to authenticated
using(user_id=auth.uid());

drop policy if exists tenant_documents_v2_tenant_self_read on public.tenant_documents_v2;
create policy tenant_documents_v2_tenant_self_read on public.tenant_documents_v2 for select to authenticated
using(exists(select 1 from public.tenants_v2 t where t.id=tenant_documents_v2.tenant_id and t.user_id=auth.uid() and t.archived_at is null));
