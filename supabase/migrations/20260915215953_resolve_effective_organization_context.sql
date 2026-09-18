create or replace function public.get_effective_organization_id()
returns uuid
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_count integer;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode='42501';
  end if;

  select p.organization_id into v_org
  from public.profiles p
  where p.user_id = v_user and p.status = 'active';

  if v_org is not null then
    return v_org;
  end if;

  if exists (
    select 1 from public.user_roles ur
    where ur.user_id=v_user and ur.role='root' and ur.revoked_at is null
  ) then
    select count(*), min(o.id) into v_count, v_org
    from public.organizations o
    where o.status='active';

    if v_count = 1 then
      return v_org;
    end if;
    if v_count = 0 then
      raise exception 'organization_missing' using errcode='P0001';
    end if;
    raise exception 'organization_selection_required' using errcode='P0001';
  end if;

  raise exception 'organization_missing' using errcode='P0001';
end;
$$;
revoke all on function public.get_effective_organization_id() from public;
revoke all on function public.get_effective_organization_id() from anon;
grant execute on function public.get_effective_organization_id() to authenticated;
comment on function public.get_effective_organization_id() is 'Returns authenticated user effective organization. Active profile wins; global root may fall back only when exactly one active organization exists.';
