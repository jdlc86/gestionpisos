create or replace function public.manage_photo_pattern_lifecycle_v2(p_pattern_id uuid)
returns jsonb
language sql
security definer
set search_path=public,private,pg_temp
as $$
  select private.delete_or_retire_photo_pattern_v2(p_pattern_id);
$$;

revoke all on function public.manage_photo_pattern_lifecycle_v2(uuid) from public,anon,authenticated;
grant execute on function public.manage_photo_pattern_lifecycle_v2(uuid) to service_role;

comment on function public.manage_photo_pattern_lifecycle_v2(uuid) is
'Service-role-only PostgREST wrapper for private photo-pattern lifecycle logic.';
