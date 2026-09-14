create policy verification_policies_root_admin_insert
on public.verification_policies_v2
for insert to authenticated
with check (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy verification_policies_root_admin_update
on public.verification_policies_v2
for update to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
)
with check (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy photo_patterns_root_admin_insert
on public.photo_patterns_v2
for insert to authenticated
with check (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy photo_patterns_root_admin_update
on public.photo_patterns_v2
for update to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
)
with check (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy photo_items_actor_insert
on public.photo_verification_items_v2
for insert to authenticated
with check (
  exists (
    select 1
    from public.photo_verification_runs_v2 r
    where r.id = run_id
      and r.actor_user_id = (select auth.uid())
  )
);

create policy random_photo_requests_root_admin_insert
on public.random_photo_requests_v2
for insert to authenticated
with check (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy random_photo_requests_root_admin_update
on public.random_photo_requests_v2
for update to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
)
with check (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);
