
create policy verification_policies_admin_read
on public.verification_policies_v2
for select to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy photo_patterns_scope_read
on public.photo_patterns_v2
for select to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
  or exists (
    select 1 from public.occupancies_v2 o
    where o.property_id = photo_patterns_v2.property_id
      and o.user_id = (select auth.uid())
      and o.status = 'active'
      and o.starts_on <= current_date
      and (o.ends_on is null or o.ends_on >= current_date)
  )
  or exists (
    select 1 from public.property_staff_access_v3 s
    where s.property_id = photo_patterns_v2.property_id
      and s.employee_user_id = (select auth.uid())
      and s.revoked_at is null
      and (s.valid_until is null or s.valid_until > now())
  )
);

create policy photo_runs_actor_read
on public.photo_verification_runs_v2
for select to authenticated
using (
  actor_user_id = (select auth.uid())
  or ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy photo_runs_actor_insert
on public.photo_verification_runs_v2
for insert to authenticated
with check (
  actor_user_id = (select auth.uid())
);

create policy photo_items_actor_read
on public.photo_verification_items_v2
for select to authenticated
using (
  exists (
    select 1 from public.photo_verification_runs_v2 r
    where r.id = run_id
      and (
        r.actor_user_id = (select auth.uid())
        or ((select auth.jwt())->'app_metadata'->>'role')='root'
        or (
          ((select auth.jwt())->'app_metadata'->>'role')='admin'
          and r.organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
        )
      )
  )
);

create policy random_photo_requests_assignee_read
on public.random_photo_requests_v2
for select to authenticated
using (
  assigned_user_id = (select auth.uid())
  or ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);
