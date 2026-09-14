drop policy if exists properties_v2_insert on public.properties_v2;
create policy properties_v2_insert
on public.properties_v2
for insert to authenticated
with check (
  exists (
    select 1
    from public.owners o
    where o.id = properties_v2.owner_id
      and o.organization_id = properties_v2.organization_id
      and o.archived_at is null
  )
  and (
    ((select auth.jwt())->'app_metadata'->>'role') = 'root'
    or (
      ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
      and properties_v2.organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
      and exists (
        select 1
        from public.admin_capability_holders h
        where h.organization_id = properties_v2.organization_id
          and h.capability = 'property_lifecycle'
          and h.holder_user_id = (select auth.uid())
          and h.revoked_at is null
      )
    )
  )
);

drop policy if exists properties_v2_update on public.properties_v2;
create policy properties_v2_update
on public.properties_v2
for update to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and properties_v2.organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
    and exists (
      select 1
      from public.admin_capability_holders h
      where h.organization_id = properties_v2.organization_id
        and h.capability = 'property_lifecycle'
        and h.holder_user_id = (select auth.uid())
        and h.revoked_at is null
    )
  )
)
with check (
  exists (
    select 1
    from public.owners o
    where o.id = properties_v2.owner_id
      and o.organization_id = properties_v2.organization_id
      and o.archived_at is null
  )
  and (
    ((select auth.jwt())->'app_metadata'->>'role') = 'root'
    or (
      ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
      and properties_v2.organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
      and exists (
        select 1
        from public.admin_capability_holders h
        where h.organization_id = properties_v2.organization_id
          and h.capability = 'property_lifecycle'
          and h.holder_user_id = (select auth.uid())
          and h.revoked_at is null
      )
    )
  )
);

drop policy if exists properties_v2_read on public.properties_v2;
create policy properties_v2_read
on public.properties_v2
for select to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and properties_v2.organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
  or exists (
    select 1
    from public.owners o
    where o.id = properties_v2.owner_id
      and o.user_id = (select auth.uid())
      and o.archived_at is null
  )
  or exists (
    select 1
    from public.property_staff_access_v3 s
    where s.property_id = properties_v2.id
      and s.employee_user_id = (select auth.uid())
      and s.revoked_at is null
      and (s.valid_until is null or s.valid_until > now())
  )
  or exists (
    select 1
    from public.occupancies_v2 oc
    where oc.property_id = properties_v2.id
      and oc.user_id = (select auth.uid())
      and oc.status = 'active'
      and oc.starts_on <= current_date
      and (oc.ends_on is null or oc.ends_on >= current_date)
  )
);

drop policy if exists rooms_v2_read on public.rooms_v2;
create policy rooms_v2_read
on public.rooms_v2
for select to authenticated
using (
  exists (
    select 1
    from public.properties_v2 p
    where p.id = rooms_v2.property_id
      and (
        ((select auth.jwt())->'app_metadata'->>'role') = 'root'
        or (
          ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
          and p.organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
        )
        or exists (
          select 1
          from public.owners o
          where o.id = p.owner_id
            and o.user_id = (select auth.uid())
            and o.archived_at is null
        )
        or exists (
          select 1
          from public.property_staff_access_v3 s
          where s.property_id = p.id
            and s.employee_user_id = (select auth.uid())
            and s.revoked_at is null
            and (s.valid_until is null or s.valid_until > now())
        )
        or exists (
          select 1
          from public.occupancies_v2 oc
          where oc.property_id = p.id
            and oc.user_id = (select auth.uid())
            and oc.status = 'active'
            and oc.starts_on <= current_date
            and (oc.ends_on is null or oc.ends_on >= current_date)
        )
      )
  )
);
