create policy payment_obligations_self_read on public.payment_obligations_v2
for select to authenticated
using (tenant_user_id = (select auth.uid()));

create policy payment_obligations_admin_read on public.payment_obligations_v2
for select to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy reminder_rules_admin_read on public.reminder_rules_v2
for select to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy reminder_rules_admin_write on public.reminder_rules_v2
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

create policy claims_self_read on public.claims_v2
for select to authenticated
using (tenant_user_id = (select auth.uid()));

create policy claims_admin_read on public.claims_v2
for select to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy claims_admin_write on public.claims_v2
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