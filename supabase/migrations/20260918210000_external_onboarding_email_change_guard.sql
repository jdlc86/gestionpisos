-- GestionPisos · External onboarding · safe email changes
-- A pending external invitation must be revoked before the business email can change.
-- Revocation is completed only after the pending Auth identity has been soft-deleted server-side.

create or replace function public.revoke_external_account_onboarding_v1(
  p_auth_user_id uuid,
  p_actor_user_id uuid,
  p_reason text,
  p_replacement_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_row public.external_account_onboarding;
  v_deleted_at timestamptz;
  v_replacement_email text:=nullif(lower(btrim(p_replacement_email)),'');
  v_subject_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode='42501';
  end if;
  if p_auth_user_id is null or p_actor_user_id is null then
    raise exception 'invalid_external_onboarding_revoke_target' using errcode='22023';
  end if;
  if p_reason <> 'email_changed' then
    raise exception 'invalid_external_onboarding_revoke_reason' using errcode='22023';
  end if;

  select *
  into v_row
  from public.external_account_onboarding
  where auth_user_id=p_auth_user_id
  order by created_at desc
  limit 1
  for update;

  if v_row.id is null then
    raise exception 'external_onboarding_not_found' using errcode='P0002';
  end if;

  if v_row.status='revoked' then
    return jsonb_build_object(
      'ok',true,
      'status','revoked',
      'already_revoked',true,
      'subject_type',v_row.subject_type,
      'subject_id',coalesce(v_row.owner_id,v_row.tenant_id),
      'old_email',v_row.email,
      'replacement_email',v_replacement_email
    );
  end if;

  if v_row.status<>'pending' then
    raise exception 'pending_external_onboarding_required' using errcode='55000';
  end if;

  if v_replacement_email is null
    or v_replacement_email=lower(btrim(v_row.email)) then
    raise exception 'external_replacement_email_invalid' using errcode='22023';
  end if;

  select deleted_at
  into v_deleted_at
  from auth.users
  where id=p_auth_user_id;

  if v_deleted_at is null then
    raise exception 'external_auth_identity_not_disabled' using errcode='55000';
  end if;

  v_subject_id:=coalesce(v_row.owner_id,v_row.tenant_id);

  update public.external_account_onboarding
  set status='revoked',
      revoked_at=coalesce(revoked_at,now()),
      updated_at=now()
  where id=v_row.id;

  -- A pending external identity has no operational role. Archive its profile so
  -- it cannot remain as an apparently active identity after Auth is disabled.
  if not exists(
    select 1 from public.user_roles
    where user_id=p_auth_user_id and revoked_at is null
  )
  and not exists(
    select 1 from public.internal_staff_onboarding
    where user_id=p_auth_user_id and status in ('pending','active')
  ) then
    update public.profiles
    set status='archived',
        archived_at=coalesce(archived_at,now()),
        updated_at=now()
    where user_id=p_auth_user_id;
  end if;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_row.organization_id,
    p_actor_user_id,
    'revoke_external_account_invitation',
    v_row.subject_type,
    v_subject_id::text,
    'success',
    jsonb_build_object(
      'auth_user_id',p_auth_user_id,
      'reason',p_reason,
      'old_email',v_row.email,
      'replacement_email',v_replacement_email
    )
  );

  return jsonb_build_object(
    'ok',true,
    'status','revoked',
    'already_revoked',false,
    'subject_type',v_row.subject_type,
    'subject_id',v_subject_id,
    'old_email',v_row.email,
    'replacement_email',v_replacement_email
  );
end
$$;

revoke all on function public.revoke_external_account_onboarding_v1(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public.revoke_external_account_onboarding_v1(uuid,uuid,text,text)
  to service_role;

create or replace function private.guard_external_subject_email_change_v1()
returns trigger
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $$
declare
  v_subject_type text;
  v_onboarding_status text;
begin
  if lower(btrim(coalesce(old.email,'')))=lower(btrim(coalesce(new.email,''))) then
    return new;
  end if;

  if tg_table_name='owners' then
    v_subject_type:='owner';
    select o.status
    into v_onboarding_status
    from public.external_account_onboarding o
    where o.owner_id=old.id and o.status in ('pending','active')
    order by o.created_at desc
    limit 1;
  elsif tg_table_name='tenants_v2' then
    v_subject_type:='tenant';
    select o.status
    into v_onboarding_status
    from public.external_account_onboarding o
    where o.tenant_id=old.id and o.status in ('pending','active')
    order by o.created_at desc
    limit 1;
  else
    raise exception 'external_email_guard_invalid_table' using errcode='55000';
  end if;

  if v_onboarding_status='pending' then
    raise exception 'external_onboarding_email_change_requires_revocation'
      using errcode='55000',
      detail=format('%s:%s',v_subject_type,old.id);
  end if;

  if v_onboarding_status='active' then
    raise exception 'external_active_account_email_change_requires_account_flow'
      using errcode='55000',
      detail=format('%s:%s',v_subject_type,old.id);
  end if;

  return new;
end
$$;

revoke all on function private.guard_external_subject_email_change_v1()
  from public,anon,authenticated;

drop trigger if exists owners_external_onboarding_email_guard on public.owners;
create trigger owners_external_onboarding_email_guard
before update of email on public.owners
for each row execute function private.guard_external_subject_email_change_v1();

drop trigger if exists tenants_external_onboarding_email_guard on public.tenants_v2;
create trigger tenants_external_onboarding_email_guard
before update of email on public.tenants_v2
for each row execute function private.guard_external_subject_email_change_v1();

-- Surface the email tied to the current onboarding so the UI can distinguish
-- a real pending invitation from a stale invitation created for an old address.
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
    'email',o.email,'status',o.status,'invited_at',o.invited_at,'invite_count',o.invite_count,
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

comment on function public.revoke_external_account_onboarding_v1(uuid,uuid,text,text) is
  'Revoca un onboarding externo pendiente solo después de que la identidad Auth se haya deshabilitado; conserva histórico y audita el cambio de email.';
comment on function private.guard_external_subject_email_change_v1() is
  'Impide cambiar el email de OWNER/TENANT mientras exista onboarding pending/active sin resolver explícitamente su identidad Auth.';
