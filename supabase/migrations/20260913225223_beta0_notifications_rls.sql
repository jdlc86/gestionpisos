create policy notifications_self_read on public.notifications_v2
for select to authenticated
using (recipient_user_id = (select auth.uid()));

create policy notifications_self_update on public.notifications_v2
for update to authenticated
using (recipient_user_id = (select auth.uid()))
with check (recipient_user_id = (select auth.uid()));

create policy broadcasts_root_admin_read on public.broadcasts_v2
for select to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy broadcasts_root_admin_insert on public.broadcasts_v2
for insert to authenticated
with check (
  ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy broadcasts_root_admin_update on public.broadcasts_v2
for update to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
)
with check (
  ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);