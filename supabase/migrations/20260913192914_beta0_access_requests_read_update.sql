
create policy access_requests_self_read on public.access_requests
for select to authenticated
using (requester_user_id = (select auth.uid()));

create policy access_requests_admin_read on public.access_requests
for select to authenticated
using (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    (select auth.jwt()->'app_metadata'->>'role') = 'admin'
    and organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
  )
);

create policy access_requests_admin_update on public.access_requests
for update to authenticated
using (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    (select auth.jwt()->'app_metadata'->>'role') = 'admin'
    and organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
  )
)
with check (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    (select auth.jwt()->'app_metadata'->>'role') = 'admin'
    and organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
  )
);
