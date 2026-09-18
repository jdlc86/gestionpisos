
create policy admin_capability_holders_read on public.admin_capability_holders
for select to authenticated
using (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    (select auth.jwt()->'app_metadata'->>'role') = 'admin'
    and organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
  )
);

create policy admin_capability_requests_read on public.admin_capability_requests
for select to authenticated
using (
  requester_user_id = (select auth.uid())
  or (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    (select auth.jwt()->'app_metadata'->>'role') = 'admin'
    and organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
  )
);

create policy admin_capability_requests_insert on public.admin_capability_requests
for insert to authenticated
with check (
  requester_user_id = (select auth.uid())
  and (select auth.jwt()->'app_metadata'->>'role') = 'admin'
  and organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
);
