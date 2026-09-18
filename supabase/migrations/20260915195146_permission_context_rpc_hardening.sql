revoke execute on function public.get_permission_management_context(uuid) from public;
revoke execute on function public.get_permission_management_context(uuid) from anon;
grant execute on function public.get_permission_management_context(uuid) to authenticated;
