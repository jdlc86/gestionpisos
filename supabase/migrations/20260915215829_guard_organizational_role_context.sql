create or replace function public.assert_organizational_role_context()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.revoked_at is null and new.role <> 'root' and new.organization_id is null then
    raise exception 'organization_required_for_role' using errcode='23514';
  end if;
  return new;
end;
$$;
drop trigger if exists user_roles_require_organization on public.user_roles;
create trigger user_roles_require_organization
before insert or update of role, organization_id, revoked_at on public.user_roles
for each row execute function public.assert_organizational_role_context();
comment on function public.assert_organizational_role_context() is 'Prevents active organization-scoped roles from existing without organization context; root remains globally representable.';
