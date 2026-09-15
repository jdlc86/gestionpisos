-- PUBLIC revoke alone does not remove privileges previously granted directly to anon.
revoke execute on function public.create_tenant_task_v2(uuid,text,text,text,timestamptz,uuid,uuid,uuid,text,text,uuid) from anon;
revoke execute on function public.apply_tenant_task_action_v2(uuid,text,text) from anon;
revoke execute on function public.offboard_tenant_occupancy_v2(uuid,date) from anon;
grant execute on function public.create_tenant_task_v2(uuid,text,text,text,timestamptz,uuid,uuid,uuid,text,text,uuid) to authenticated;
grant execute on function public.apply_tenant_task_action_v2(uuid,text,text) to authenticated;
grant execute on function public.offboard_tenant_occupancy_v2(uuid,date) to authenticated;
