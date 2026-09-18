create policy incidents_root_admin_read on public.incidents_v2
  for select to authenticated
  using (
    ((select auth.jwt())->'app_metadata'->>'role')='root'
    or (
      ((select auth.jwt())->'app_metadata'->>'role')='admin'
      and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
    )
  );

  create policy incident_updates_root_admin_read on public.incident_updates_v2
  for select to authenticated
  using (
    exists (
      select 1 from public.incidents_v2 i
      where i.id=incident_id
      and (
        ((select auth.jwt())->'app_metadata'->>'role')='root'
        or (
          ((select auth.jwt())->'app_metadata'->>'role')='admin'
          and i.organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
        )
      )
    )
  );

  create policy incident_evidence_root_admin_read on public.incident_evidence_v2
  for select to authenticated
  using (
    exists (
      select 1 from public.incidents_v2 i
      where i.id=incident_id
      and (
        ((select auth.jwt())->'app_metadata'->>'role')='root'
        or (
          ((select auth.jwt())->'app_metadata'->>'role')='admin'
          and i.organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
        )
      )
    )
  );
