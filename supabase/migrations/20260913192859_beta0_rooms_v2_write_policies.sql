
create policy rooms_v2_insert on public.rooms_v2
for insert to authenticated
with check (
  exists (
    select 1
    from public.properties_v2 p
    where p.id = property_id
      and (
        (select auth.jwt()->'app_metadata'->>'role') = 'root'
        or (
          (select auth.jwt()->'app_metadata'->>'role') = 'admin'
          and p.organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
        )
        or exists (
          select 1
          from public.property_staff_access_v3 s
          where s.property_id = p.id
            and s.employee_user_id = (select auth.uid())
            and s.can_write = true
            and s.revoked_at is null
            and (s.valid_until is null or s.valid_until > now())
        )
      )
  )
);

create policy rooms_v2_update on public.rooms_v2
for update to authenticated
using (
  exists (
    select 1
    from public.properties_v2 p
    where p.id = property_id
      and (
        (select auth.jwt()->'app_metadata'->>'role') = 'root'
        or (
          (select auth.jwt()->'app_metadata'->>'role') = 'admin'
          and p.organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
        )
        or exists (
          select 1
          from public.property_staff_access_v3 s
          where s.property_id = p.id
            and s.employee_user_id = (select auth.uid())
            and s.can_write = true
            and s.revoked_at is null
            and (s.valid_until is null or s.valid_until > now())
        )
      )
  )
)
with check (
  exists (
    select 1
    from public.properties_v2 p
    where p.id = property_id
      and (
        (select auth.jwt()->'app_metadata'->>'role') = 'root'
        or (
          (select auth.jwt()->'app_metadata'->>'role') = 'admin'
          and p.organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
        )
        or exists (
          select 1
          from public.property_staff_access_v3 s
          where s.property_id = p.id
            and s.employee_user_id = (select auth.uid())
            and s.can_write = true
            and s.revoked_at is null
            and (s.valid_until is null or s.valid_until > now())
        )
      )
  )
);

create policy rooms_v2_delete on public.rooms_v2
for delete to authenticated
using (
  exists (
    select 1
    from public.properties_v2 p
    where p.id = property_id
      and (
        (select auth.jwt()->'app_metadata'->>'role') = 'root'
        or (
          (select auth.jwt()->'app_metadata'->>'role') = 'admin'
          and p.organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
        )
      )
  )
);
