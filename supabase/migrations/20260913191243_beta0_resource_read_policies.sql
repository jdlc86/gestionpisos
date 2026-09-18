
create policy properties_read_scope on public.properties
for select to authenticated
using (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
    and (select auth.jwt()->'app_metadata'->>'role') = 'admin'
  )
  or exists (
    select 1 from public.owners o
    where o.id = owner_id
      and o.user_id = (select auth.uid())
      and o.archived_at is null
  )
  or exists (
    select 1 from public.property_staff_assignments psa
    where psa.property_id = id
      and psa.employee_user_id = (select auth.uid())
      and psa.revoked_at is null
      and (psa.valid_until is null or psa.valid_until > now())
  )
  or exists (
    select 1 from public.tenancies t
    where t.property_id = id
      and t.user_id = (select auth.uid())
      and t.status = 'active'
      and t.archived_at is null
      and t.starts_on <= current_date
      and (t.ends_on is null or t.ends_on >= current_date)
  )
);

create policy rooms_read_scope on public.rooms
for select to authenticated
using (
  exists (
    select 1 from public.properties p
    where p.id = property_id
  )
);

create policy tenancies_read_scope on public.tenancies
for select to authenticated
using (
  user_id = (select auth.uid())
  or (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
    and (select auth.jwt()->'app_metadata'->>'role') = 'admin'
  )
);

create policy staff_assignments_read_scope on public.property_staff_assignments
for select to authenticated
using (
  employee_user_id = (select auth.uid())
  or (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or exists (
    select 1 from public.properties p
    where p.id = property_id
      and p.organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
      and (select auth.jwt()->'app_metadata'->>'role') = 'admin'
  )
);
