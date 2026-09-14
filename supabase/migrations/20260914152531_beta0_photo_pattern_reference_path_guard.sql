drop policy if exists photo_patterns_root_admin_insert on public.photo_patterns_v2;
create policy photo_patterns_root_admin_insert
on public.photo_patterns_v2
for insert to authenticated
with check (
  photo_patterns_v2.created_by = (select auth.uid())
  and photo_patterns_v2.reference_storage_path = (
    photo_patterns_v2.organization_id::text || '/patterns/' ||
    photo_patterns_v2.id::text || '/reference.jpg'
  )
  and exists (
    select 1
    from public.properties_v2 p
    where p.id = photo_patterns_v2.property_id
      and p.organization_id = photo_patterns_v2.organization_id
      and p.status <> 'archived'
      and (
        ((select auth.jwt())->'app_metadata'->>'role') = 'root'
        or (
          ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
          and p.organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
        )
      )
  )
);

drop policy if exists photo_patterns_root_admin_update on public.photo_patterns_v2;
create policy photo_patterns_root_admin_update
on public.photo_patterns_v2
for update to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and photo_patterns_v2.organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
)
with check (
  photo_patterns_v2.reference_storage_path = (
    photo_patterns_v2.organization_id::text || '/patterns/' ||
    photo_patterns_v2.id::text || '/reference.jpg'
  )
  and exists (
    select 1
    from public.properties_v2 p
    where p.id = photo_patterns_v2.property_id
      and p.organization_id = photo_patterns_v2.organization_id
      and p.status <> 'archived'
      and (
        ((select auth.jwt())->'app_metadata'->>'role') = 'root'
        or (
          ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
          and p.organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
        )
      )
  )
);
