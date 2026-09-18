create policy tenant_tasks_v2_root_all on public.tenant_tasks_v2 for all to authenticated using (((auth.jwt()->'app_metadata'->>'role')='root')) with check (((auth.jwt()->'app_metadata'->>'role')='root'));
create policy tenant_tasks_v2_admin_org_all on public.tenant_tasks_v2 for all to authenticated using (((auth.jwt()->'app_metadata'->>'role')='admin') and organization_id=((auth.jwt()->'app_metadata'->>'organization_id')::uuid)) with check (((auth.jwt()->'app_metadata'->>'role')='admin') and organization_id=((auth.jwt()->'app_metadata'->>'organization_id')::uuid));
create policy tenant_task_actions_v2_scope on public.tenant_task_actions_v2 for all to authenticated using (exists(select 1 from public.tenant_tasks_v2 t where t.id=task_id)) with check (exists(select 1 from public.tenant_tasks_v2 t where t.id=task_id));
create policy tenant_task_history_v2_scope on public.tenant_task_history_v2 for select to authenticated using (exists(select 1 from public.tenant_tasks_v2 t where t.id=task_id));
create policy tenant_task_history_v2_insert_scope on public.tenant_task_history_v2 for insert to authenticated with check (exists(select 1 from public.tenant_tasks_v2 t where t.id=task_id));
create policy tenant_task_templates_read on public.tenant_task_workflow_templates_v2 for select to authenticated using (true);

create or replace function public.create_tenant_task_v2(
 p_tenant_id uuid,p_task_type text,p_title text,p_description text default null,p_due_at timestamptz default null,
 p_assigned_user_id uuid default null,p_property_id uuid default null,p_room_id uuid default null,p_origin text default 'manual',
 p_source_kind text default null,p_source_id uuid default null)
returns public.tenant_tasks_v2 language plpgsql security invoker set search_path=public as $$
declare v_tenant public.tenants_v2; v_task public.tenant_tasks_v2; v_initial text;
begin
 select * into v_tenant from public.tenants_v2 where id=p_tenant_id;
 if v_tenant.id is null then raise exception 'tenant_not_found' using errcode='P0002'; end if;
 v_initial:=case p_task_type when 'key_pickup' then 'requested' when 'key_delivery' then 'requested' when 'check_in' then 'scheduled' when 'check_out' then 'scheduled' when 'cleaning' then 'assigned' when 'rent_payment' then 'pending' when 'rent_claim' then 'draft' when 'damage_claim' then 'draft' when 'deposit' then 'pending' when 'incident' then 'open' when 'generic' then 'pending' else null end;
 if v_initial is null then raise exception 'task_type_invalid' using errcode='22023'; end if;
 insert into public.tenant_tasks_v2(organization_id,tenant_id,property_id,room_id,task_type,origin,title,description,status,due_at,assigned_user_id,source_kind,source_id,created_by)
 values(v_tenant.organization_id,p_tenant_id,p_property_id,p_room_id,p_task_type,p_origin,p_title,p_description,v_initial,p_due_at,p_assigned_user_id,p_source_kind,p_source_id,auth.uid()) returning * into v_task;
 insert into public.tenant_task_history_v2(task_id,action_key,action_label,from_status,to_status,note,actor_user_id)
 values(v_task.id,'create',case when p_origin='automatic' then 'Creada automáticamente' else 'Creada manualmente' end,null,v_initial,null,auth.uid());
 return v_task;
end $$;
grant execute on function public.create_tenant_task_v2(uuid,text,text,text,timestamptz,uuid,uuid,uuid,text,text,uuid) to authenticated;
