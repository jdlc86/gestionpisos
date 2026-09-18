with preserved as (
  select u.id
  from auth.users u
  where coalesce(u.raw_app_meta_data->>'role','')='root'
  union
  select ur.user_id
  from public.user_roles ur
  where ur.role::text='root' and ur.revoked_at is null
  union
  select po.user_id
  from public.platform_operators po
), candidates as (
  select u.id,u.email,u.created_at
  from auth.users u
  where not exists (select 1 from preserved p where p.id=u.id)
), root_actor as (
  select u.id,
         nullif(u.raw_app_meta_data->>'organization_id','')::uuid as organization_id
  from auth.users u
  where coalesce(u.raw_app_meta_data->>'role','')='root'
  order by u.created_at
  limit 1
)
insert into public.audit_log_v2 (
  organization_id, actor_user_id, action, entity_type, entity_id, result, details
)
select
  r.organization_id,
  r.id,
  'test_auth_user_cleanup',
  'auth_users',
  'non_root_non_platform_operator',
  'success',
  jsonb_build_object(
    'reason','User requested removal of all Auth users except ROOT and technical platform operators',
    'deleted_users', coalesce((select jsonb_agg(jsonb_build_object('user_id',c.id,'email',c.email) order by c.created_at) from candidates c),'[]'::jsonb),
    'preserved_policy','ROOT identities and every identity registered in platform_operators'
  )
from root_actor r;

with preserved as (
  select u.id from auth.users u where coalesce(u.raw_app_meta_data->>'role','')='root'
  union select ur.user_id from public.user_roles ur where ur.role::text='root' and ur.revoked_at is null
  union select po.user_id from public.platform_operators po
), candidates as (
  select u.id from auth.users u where not exists (select 1 from preserved p where p.id=u.id)
)
delete from public.internal_staff_onboarding_access_snapshot s using candidates c where s.user_id=c.id;

with preserved as (
  select u.id from auth.users u where coalesce(u.raw_app_meta_data->>'role','')='root'
  union select ur.user_id from public.user_roles ur where ur.role::text='root' and ur.revoked_at is null
  union select po.user_id from public.platform_operators po
), candidates as (
  select u.id from auth.users u where not exists (select 1 from preserved p where p.id=u.id)
)
delete from public.internal_staff_onboarding s using candidates c where s.user_id=c.id;

with preserved as (
  select u.id from auth.users u where coalesce(u.raw_app_meta_data->>'role','')='root'
  union select ur.user_id from public.user_roles ur where ur.role::text='root' and ur.revoked_at is null
  union select po.user_id from public.platform_operators po
), candidates as (
  select u.id from auth.users u where not exists (select 1 from preserved p where p.id=u.id)
)
delete from public.external_account_onboarding e using candidates c where e.auth_user_id=c.id;

with preserved as (
  select u.id from auth.users u where coalesce(u.raw_app_meta_data->>'role','')='root'
  union select ur.user_id from public.user_roles ur where ur.role::text='root' and ur.revoked_at is null
  union select po.user_id from public.platform_operators po
), candidates as (
  select u.id from auth.users u where not exists (select 1 from preserved p where p.id=u.id)
)
delete from public.property_staff_access_v2 p using candidates c where p.employee_user_id=c.id;

with preserved as (
  select u.id from auth.users u where coalesce(u.raw_app_meta_data->>'role','')='root'
  union select ur.user_id from public.user_roles ur where ur.role::text='root' and ur.revoked_at is null
  union select po.user_id from public.platform_operators po
), candidates as (
  select u.id from auth.users u where not exists (select 1 from preserved p where p.id=u.id)
)
delete from public.property_staff_access_v3 p using candidates c where p.employee_user_id=c.id;

with preserved as (
  select u.id from auth.users u where coalesce(u.raw_app_meta_data->>'role','')='root'
  union select ur.user_id from public.user_roles ur where ur.role::text='root' and ur.revoked_at is null
  union select po.user_id from public.platform_operators po
), candidates as (
  select u.id from auth.users u where not exists (select 1 from preserved p where p.id=u.id)
)
delete from public.property_staff_assignments p using candidates c where p.employee_user_id=c.id;

with preserved as (
  select u.id from auth.users u where coalesce(u.raw_app_meta_data->>'role','')='root'
  union select ur.user_id from public.user_roles ur where ur.role::text='root' and ur.revoked_at is null
  union select po.user_id from public.platform_operators po
), candidates as (
  select u.id from auth.users u where not exists (select 1 from preserved p where p.id=u.id)
)
delete from public.admin_capability_requests r using candidates c where r.requester_user_id=c.id;

with preserved as (
  select u.id from auth.users u where coalesce(u.raw_app_meta_data->>'role','')='root'
  union select ur.user_id from public.user_roles ur where ur.role::text='root' and ur.revoked_at is null
  union select po.user_id from public.platform_operators po
), candidates as (
  select u.id from auth.users u where not exists (select 1 from preserved p where p.id=u.id)
)
delete from public.admin_capability_holders h using candidates c where h.holder_user_id=c.id;

with preserved as (
  select u.id from auth.users u where coalesce(u.raw_app_meta_data->>'role','')='root'
  union select ur.user_id from public.user_roles ur where ur.role::text='root' and ur.revoked_at is null
  union select po.user_id from public.platform_operators po
), candidates as (
  select u.id from auth.users u where not exists (select 1 from preserved p where p.id=u.id)
)
delete from public.user_roles r using candidates c where r.user_id=c.id;

with preserved as (
  select u.id from auth.users u where coalesce(u.raw_app_meta_data->>'role','')='root'
  union select ur.user_id from public.user_roles ur where ur.role::text='root' and ur.revoked_at is null
  union select po.user_id from public.platform_operators po
), candidates as (
  select u.id from auth.users u where not exists (select 1 from preserved p where p.id=u.id)
)
delete from public.profiles p using candidates c where p.user_id=c.id;

with preserved as (
  select u.id from auth.users u where coalesce(u.raw_app_meta_data->>'role','')='root'
  union select ur.user_id from public.user_roles ur where ur.role::text='root' and ur.revoked_at is null
  union select po.user_id from public.platform_operators po
), candidates as (
  select u.id from auth.users u where not exists (select 1 from preserved p where p.id=u.id)
)
delete from auth.users u using candidates c where u.id=c.id;
