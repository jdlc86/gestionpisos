-- Allow only the trusted Edge Function service role to invoke pattern lifecycle helpers.
-- Browser roles remain explicitly denied.

grant usage on schema private to service_role;
grant execute on function private.photo_pattern_usage_v2(uuid) to service_role;
grant execute on function private.delete_or_retire_photo_pattern_v2(uuid) to service_role;

revoke execute on function private.photo_pattern_usage_v2(uuid) from public, anon, authenticated;
revoke execute on function private.delete_or_retire_photo_pattern_v2(uuid) from public, anon, authenticated;
