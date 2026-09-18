
create policy occupancies_v2_insert on public.occupancies_v2
for insert to authenticated
with check (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    (select auth.jwt()->'app_metadata'->>'role') = 'admin'
    and organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
  )
);

create policy occupancies_v2_update on public.occupancies_v2
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
