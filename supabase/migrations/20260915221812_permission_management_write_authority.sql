alter table public.admin_capability_holders drop constraint if exists admin_capability_holders_capability_check;
alter table public.admin_capability_holders add constraint admin_capability_holders_capability_check
check (capability in ('property_lifecycle','permission_management'));

create unique index if not exists admin_capability_one_active_holder
on public.admin_capability_holders(organization_id,capability)
where revoked_at is null;

create or replace function public.can_manage_permissions(p_organization_id uuid)
returns boolean
language sql
security definer
stable
set search_path=public
as $$
  select exists(
    select 1 from public.user_roles ur
    where ur.user_id=auth.uid() and ur.role='root' and ur.revoked_at is null
  ) or exists(
    select 1
    from public.user_roles ur
    join public.admin_capability_holders h
      on h.organization_id=ur.organization_id
     and h.holder_user_id=ur.user_id
     and h.capability='permission_management'
     and h.revoked_at is null
    where ur.user_id=auth.uid()
      and ur.organization_id=p_organization_id
      and ur.role='admin'
      and ur.revoked_at is null
  );
$$;
revoke all on function public.can_manage_permissions(uuid) from public, anon;
grant execute on function public.can_manage_permissions(uuid) to authenticated;
