
create policy organizations_read_privileged on public.organizations
for select to authenticated
using (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
    and (select auth.jwt()->'app_metadata'->>'role') = 'admin'
  )
);

create policy profiles_read_scope on public.profiles
for select to authenticated
using (
  user_id = (select auth.uid())
  or (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
    and (select auth.jwt()->'app_metadata'->>'role') = 'admin'
  )
);

create policy user_roles_read_scope on public.user_roles
for select to authenticated
using (
  user_id = (select auth.uid())
  or (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
    and (select auth.jwt()->'app_metadata'->>'role') = 'admin'
  )
);

create policy owners_read_scope on public.owners
for select to authenticated
using (
  user_id = (select auth.uid())
  or (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
    and (select auth.jwt()->'app_metadata'->>'role') = 'admin'
  )
);
