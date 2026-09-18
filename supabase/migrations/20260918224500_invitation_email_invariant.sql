-- GestionPisos · Invitation email invariant
-- One invitation/identity belongs to one canonical email. It may be revoked and
-- reprovisioned, but it is never silently transferred to a different address.

alter table public.internal_staff_onboarding
  add column if not exists invitation_email text;

update public.internal_staff_onboarding o
set invitation_email=lower(btrim(au.email))
from auth.users au
where au.id=o.user_id
  and o.invitation_email is null;

do $internal_staff_email_backfill_guard$
begin
  if exists(
    select 1
    from public.internal_staff_onboarding o
    left join auth.users au on au.id=o.user_id
    left join public.profiles p on p.user_id=o.user_id
    where o.invitation_email is null
       or au.email is null
       or p.email is null
       or lower(btrim(au.email)) is distinct from lower(btrim(o.invitation_email))
       or lower(btrim(p.email)) is distinct from lower(btrim(o.invitation_email))
  ) then
    raise exception 'internal_staff_invitation_email_backfill_inconsistent';
  end if;
end;
$internal_staff_email_backfill_guard$;

alter table public.internal_staff_onboarding
  alter column invitation_email set not null;

do $internal_staff_email_constraint$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.internal_staff_onboarding'::regclass
      and conname='internal_staff_onboarding_invitation_email_check'
  ) then
    alter table public.internal_staff_onboarding
      add constraint internal_staff_onboarding_invitation_email_check
      check (
        invitation_email=lower(btrim(invitation_email))
        and position('@' in invitation_email)>1
        and char_length(invitation_email)<=254
      );
  end if;
end;
$internal_staff_email_constraint$;

create or replace function private.enforce_internal_staff_invitation_email_v1()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_auth_email text;
  v_profile_email text;
begin
  select lower(btrim(email))
  into v_auth_email
  from auth.users
  where id=new.user_id;

  select lower(btrim(email))
  into v_profile_email
  from public.profiles
  where user_id=new.user_id;

  if tg_op='INSERT' then
    if new.invitation_email is null then
      new.invitation_email:=v_auth_email;
    else
      new.invitation_email:=lower(btrim(new.invitation_email));
    end if;
  elsif new.invitation_email is distinct from old.invitation_email then
    raise exception 'internal_staff_invitation_email_immutable'
      using errcode='55000';
  end if;

  if new.status in ('pending','active') then
    if v_auth_email is null
      or v_profile_email is null
      or new.invitation_email is null
      or v_auth_email is distinct from new.invitation_email
      or v_profile_email is distinct from new.invitation_email then
      raise exception 'internal_staff_invitation_email_mismatch'
        using errcode='55000';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_internal_staff_invitation_email_v1()
  from public,anon,authenticated;

drop trigger if exists internal_staff_invitation_email_guard
  on public.internal_staff_onboarding;
create trigger internal_staff_invitation_email_guard
before insert or update on public.internal_staff_onboarding
for each row execute function private.enforce_internal_staff_invitation_email_v1();

create or replace function private.guard_internal_staff_profile_email_change_v1()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_status text;
  v_invitation_email text;
begin
  if lower(btrim(coalesce(old.email,'')))=lower(btrim(coalesce(new.email,''))) then
    return new;
  end if;

  select status,invitation_email
  into v_status,v_invitation_email
  from public.internal_staff_onboarding
  where user_id=old.user_id
    and status in ('pending','active')
  limit 1;

  if v_status is null then
    return new;
  end if;

  if lower(btrim(coalesce(new.email,'')))=v_invitation_email then
    return new;
  end if;

  if v_status='pending' then
    raise exception 'internal_staff_pending_email_change_requires_reprovision'
      using errcode='55000';
  end if;

  raise exception 'internal_staff_active_email_change_requires_account_flow'
    using errcode='55000';
end;
$$;

revoke all on function private.guard_internal_staff_profile_email_change_v1()
  from public,anon,authenticated;

drop trigger if exists profiles_internal_staff_email_guard on public.profiles;
create trigger profiles_internal_staff_email_guard
before update of email on public.profiles
for each row execute function private.guard_internal_staff_profile_email_change_v1();

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
    'invitation_email',o.invitation_email,
    'profile_email',p.email,
    'auth_email',au.email,
    'email_consistent',
      lower(btrim(coalesce(o.invitation_email,'')))=lower(btrim(coalesce(p.email,'')))
      and lower(btrim(coalesce(o.invitation_email,'')))=lower(btrim(coalesce(au.email,''))),
    'invited_at',o.invited_at,
    'activated_at',o.activated_at
  ) end
  from (select auth.uid() as user_id) me
  left join public.internal_staff_onboarding o on o.user_id=me.user_id
  left join public.profiles p on p.user_id=me.user_id
  left join auth.users au on au.id=me.user_id;
$$;

revoke all on function public.get_my_internal_staff_onboarding() from public,anon;
grant execute on function public.get_my_internal_staff_onboarding()
  to authenticated,service_role;

alter table public.platform_operators
  add column if not exists identity_email text;

update public.platform_operators po
set identity_email=lower(btrim(au.email))
from auth.users au
where au.id=po.user_id
  and po.identity_email is null;

do $platform_operator_email_backfill_guard$
begin
  if exists(
    select 1
    from public.platform_operators po
    left join auth.users au on au.id=po.user_id
    where po.identity_email is null
       or au.email is null
       or lower(btrim(au.email)) is distinct from lower(btrim(po.identity_email))
  ) then
    raise exception 'platform_operator_identity_email_backfill_inconsistent';
  end if;
end;
$platform_operator_email_backfill_guard$;

alter table public.platform_operators
  alter column identity_email set not null;

do $platform_operator_email_constraint$
begin
  if not exists(
    select 1 from pg_constraint
    where conrelid='public.platform_operators'::regclass
      and conname='platform_operators_identity_email_check'
  ) then
    alter table public.platform_operators
      add constraint platform_operators_identity_email_check
      check (
        identity_email=lower(btrim(identity_email))
        and position('@' in identity_email)>1
        and char_length(identity_email)<=254
      );
  end if;
end;
$platform_operator_email_constraint$;

create or replace function private.enforce_platform_operator_identity_email_v1()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_auth_email text;
begin
  select lower(btrim(email))
  into v_auth_email
  from auth.users
  where id=new.user_id;

  if v_auth_email is null then
    raise exception 'platform_operator_auth_email_required'
      using errcode='55000';
  end if;

  if tg_op='INSERT' then
    if new.identity_email is null then
      new.identity_email:=v_auth_email;
    else
      new.identity_email:=lower(btrim(new.identity_email));
      if new.identity_email is distinct from v_auth_email then
        raise exception 'platform_operator_identity_email_mismatch'
          using errcode='55000';
      end if;
    end if;
    return new;
  end if;

  if new.identity_email is distinct from old.identity_email then
    raise exception 'platform_operator_identity_email_immutable'
      using errcode='55000';
  end if;

  if v_auth_email is distinct from old.identity_email then
    -- A compromised/drifted identity must still be possible to disable,
    -- but it cannot be reactivated or have capabilities modified.
    if old.active=true
      and new.active=false
      and new.display_name is not distinct from old.display_name
      and new.can_recover_root is not distinct from old.can_recover_root then
      return new;
    end if;

    raise exception 'platform_operator_email_change_requires_reprovision'
      using errcode='55000';
  end if;

  return new;
end;
$$;

revoke all on function private.enforce_platform_operator_identity_email_v1()
  from public,anon,authenticated;

drop trigger if exists platform_operator_identity_email_guard
  on public.platform_operators;
create trigger platform_operator_identity_email_guard
before insert or update on public.platform_operators
for each row execute function private.enforce_platform_operator_identity_email_v1();

comment on column public.internal_staff_onboarding.invitation_email is
  'Canonical email for this staff invitation. Immutable for the lifetime of the onboarding identity.';
comment on column public.platform_operators.identity_email is
  'Canonical Auth email bound to the dedicated platform-operator identity. Email changes require reprovisioning a new identity.';
comment on function private.enforce_internal_staff_invitation_email_v1() is
  'Enforces invitation_email == profile email == Auth email for pending/active internal staff.';
comment on function private.enforce_platform_operator_identity_email_v1() is
  'Prevents platform operator identities from silently moving to another Auth email; deactivation remains possible during drift.';
