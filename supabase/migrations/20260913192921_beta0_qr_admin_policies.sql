
create policy property_qr_tokens_admin_read on public.property_qr_tokens
for select to authenticated
using (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or exists (
    select 1
    from public.properties_v2 p
    where p.id = property_id
      and (select auth.jwt()->'app_metadata'->>'role') = 'admin'
      and p.organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
  )
);

create policy property_qr_tokens_admin_insert on public.property_qr_tokens
for insert to authenticated
with check (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or exists (
    select 1
    from public.properties_v2 p
    where p.id = property_id
      and (select auth.jwt()->'app_metadata'->>'role') = 'admin'
      and p.organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
  )
);

create policy property_qr_tokens_admin_update on public.property_qr_tokens
for update to authenticated
using (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or exists (
    select 1
    from public.properties_v2 p
    where p.id = property_id
      and (select auth.jwt()->'app_metadata'->>'role') = 'admin'
      and p.organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
  )
)
with check (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or exists (
    select 1
    from public.properties_v2 p
    where p.id = property_id
      and (select auth.jwt()->'app_metadata'->>'role') = 'admin'
      and p.organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
  )
);
