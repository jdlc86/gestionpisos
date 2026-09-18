
create policy properties_v2_insert on public.properties_v2
for insert to authenticated
with check (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    (select auth.jwt()->'app_metadata'->>'role') = 'admin'
    and organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
    and exists (
      select 1
      from public.admin_capability_holders h
      where h.organization_id = organization_id
        and h.capability = 'property_lifecycle'
        and h.holder_user_id = (select auth.uid())
        and h.revoked_at is null
    )
  )
);

create policy properties_v2_update on public.properties_v2
for update to authenticated
using (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    (select auth.jwt()->'app_metadata'->>'role') = 'admin'
    and organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
    and exists (
      select 1
      from public.admin_capability_holders h
      where h.organization_id = organization_id
        and h.capability = 'property_lifecycle'
        and h.holder_user_id = (select auth.uid())
        and h.revoked_at is null
    )
  )
)
with check (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    (select auth.jwt()->'app_metadata'->>'role') = 'admin'
    and organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
    and exists (
      select 1
      from public.admin_capability_holders h
      where h.organization_id = organization_id
        and h.capability = 'property_lifecycle'
        and h.holder_user_id = (select auth.uid())
        and h.revoked_at is null
    )
  )
);
