create policy cleaning_plans_root_admin_read on public.cleaning_plans_v2
  for select to authenticated
  using (
    ((select auth.jwt())->'app_metadata'->>'role')='root'
    or (
      ((select auth.jwt())->'app_metadata'->>'role')='admin'
      and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
    )
  );

  create policy cleaning_tasks_root_admin_read on public.cleaning_tasks_v2
  for select to authenticated
  using (
    ((select auth.jwt())->'app_metadata'->>'role')='root'
    or (
      ((select auth.jwt())->'app_metadata'->>'role')='admin'
      and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
    )
  );

  create policy cleaning_debts_root_admin_read on public.cleaning_debts_v2
  for select to authenticated
  using (
    ((select auth.jwt())->'app_metadata'->>'role')='root'
    or (
      ((select auth.jwt())->'app_metadata'->>'role')='admin'
      and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
    )
  );
