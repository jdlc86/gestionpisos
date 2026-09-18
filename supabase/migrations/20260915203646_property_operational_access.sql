-- Central authorization primitive for property-scoped operational work.
create or replace function public.can_operate_property_v3(p_property_id uuid, p_require_write boolean default true)
returns boolean language sql stable security definer set search_path=public,pg_temp
as $$
 select exists(
   select 1 from public.properties_v2 p
   where p.id=p_property_id and p.archived_at is null and (
     exists(select 1 from public.user_roles r where r.user_id=auth.uid() and r.role='root' and r.revoked_at is null)
     or exists(select 1 from public.user_roles r where r.user_id=auth.uid() and r.organization_id=p.organization_id and r.role='admin' and r.revoked_at is null)
     or exists(select 1 from public.property_staff_access_v3 s where s.property_id=p.id and s.employee_user_id=auth.uid() and s.revoked_at is null and (s.valid_until is null or s.valid_until>now()) and (not p_require_write or s.can_write))
   )
 )
$$;
revoke all on function public.can_operate_property_v3(uuid,boolean) from public;
revoke execute on function public.can_operate_property_v3(uuid,boolean) from anon;
grant execute on function public.can_operate_property_v3(uuid,boolean) to authenticated;

-- Task definitions remain agency-controlled, but action rows must never be writable merely because a task exists.
drop policy if exists tenant_task_actions_v2_scope on public.tenant_task_actions_v2;
create policy tenant_task_actions_v2_read_scope on public.tenant_task_actions_v2 for select to authenticated
using (exists(select 1 from public.tenant_tasks_v2 t where t.id=task_id and (
  public.can_operate_property_v3(t.property_id,false)
  or t.assigned_user_id=auth.uid()
  or exists(select 1 from public.tenants_v2 tn where tn.id=t.tenant_id and tn.user_id=auth.uid())
)));
create policy tenant_task_actions_v2_write_scope on public.tenant_task_actions_v2 for all to authenticated
using (exists(select 1 from public.tenant_tasks_v2 t where t.id=task_id and public.can_operate_property_v3(t.property_id,true)))
with check (exists(select 1 from public.tenant_tasks_v2 t where t.id=task_id and public.can_operate_property_v3(t.property_id,true)));

-- Responsible/delegated writers may manage occupancy records only for their property.
create policy occupancies_v2_property_operator_read on public.occupancies_v2 for select to authenticated
using (public.can_operate_property_v3(property_id,false));
create policy occupancies_v2_property_operator_insert on public.occupancies_v2 for insert to authenticated
with check (public.can_operate_property_v3(property_id,true));
create policy occupancies_v2_property_operator_update on public.occupancies_v2 for update to authenticated
using (public.can_operate_property_v3(property_id,true)) with check (public.can_operate_property_v3(property_id,true));

-- Tenant identity is visible to an operator only through an occupancy in an authorized property.
create policy tenants_v2_property_operator_read on public.tenants_v2 for select to authenticated
using (exists(select 1 from public.occupancies_v2 o where o.tenant_id=tenants_v2.id and public.can_operate_property_v3(o.property_id,false)));

-- Tenant documents inherit the tenant's property scope. Writes require write delegation.
create policy tenant_documents_v2_property_operator_read on public.tenant_documents_v2 for select to authenticated
using (exists(select 1 from public.occupancies_v2 o where o.tenant_id=tenant_documents_v2.tenant_id and public.can_operate_property_v3(o.property_id,false)));
create policy tenant_documents_v2_property_operator_insert on public.tenant_documents_v2 for insert to authenticated
with check (uploaded_by=auth.uid() and exists(select 1 from public.occupancies_v2 o where o.tenant_id=tenant_documents_v2.tenant_id and o.organization_id=tenant_documents_v2.organization_id and public.can_operate_property_v3(o.property_id,true)));
create policy tenant_documents_v2_property_operator_update on public.tenant_documents_v2 for update to authenticated
using (exists(select 1 from public.occupancies_v2 o where o.tenant_id=tenant_documents_v2.tenant_id and public.can_operate_property_v3(o.property_id,true)))
with check (exists(select 1 from public.occupancies_v2 o where o.tenant_id=tenant_documents_v2.tenant_id and o.organization_id=tenant_documents_v2.organization_id and public.can_operate_property_v3(o.property_id,true)));
create policy tenant_documents_v2_property_operator_delete on public.tenant_documents_v2 for delete to authenticated
using (exists(select 1 from public.occupancies_v2 o where o.tenant_id=tenant_documents_v2.tenant_id and public.can_operate_property_v3(o.property_id,true)));
