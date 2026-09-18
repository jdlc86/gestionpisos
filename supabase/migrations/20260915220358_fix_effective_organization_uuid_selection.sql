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

  if v_org is not null then return v_org; end if;

  if exists (select 1 from public.user_roles ur where ur.user_id=v_user and ur.role='root' and ur.revoked_at is null) then
    select count(*) into v_count from public.organizations o where o.status='active';
    if v_count = 1 then
      select o.id into v_org from public.organizations o where o.status='active' limit 1;
      return v_org;
    end if;
    if v_count = 0 then raise exception 'organization_missing' using errcode='P0001'; end if;
    raise exception 'organization_selection_required' using errcode='P0001';
  end if;

  raise exception 'organization_missing' using errcode='P0001';
end;
$$;
