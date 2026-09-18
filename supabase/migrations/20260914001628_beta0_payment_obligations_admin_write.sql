
create policy payment_obligations_admin_write on public.payment_obligations_v2
for all to authenticated
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
