-- Harden directly callable SECURITY DEFINER functions.
revoke execute on function public.request_admin_write_control(uuid) from public, anon;
revoke execute on function public.decide_admin_write_control_request(uuid,boolean) from public, anon;
grant execute on function public.request_admin_write_control(uuid) to authenticated;
grant execute on function public.decide_admin_write_control_request(uuid,boolean) to authenticated;

-- Trigger functions are not application RPCs and must not be directly executable by client roles.
revoke execute on function public.sync_tenant_status_from_occupancy_v2() from public, anon, authenticated;

-- Preserve trigger-safe search path while including pg_temp explicitly.
alter function public.sync_tenant_status_from_occupancy_v2() set search_path=public,pg_temp;
