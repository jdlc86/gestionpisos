create or replace function public.get_permission_management_context(p_organization_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
 v_actor uuid:=auth.uid();
 v_org uuid:=p_organization_id;
 v_is_root boolean:=false;
 v_is_admin boolean:=false;
 v_result jsonb;
begin
 if v_actor is null then raise exception 'not_authenticated'; end if;
 select exists(select 1 from public.user_roles where user_id=v_actor and role='root' and revoked_at is null) into v_is_root;
 if v_org is null then
   select organization_id into v_org from public.user_roles
   where user_id=v_actor and organization_id is not null and revoked_at is null
   order by case when role='admin' then 0 else 1 end, created_at limit 1;
 end if;
 if v_org is null then
   select organization_id into v_org from public.profiles where user_id=v_actor and archived_at is null;
 end if;
 if v_org is null then raise exception 'organization_required'; end if;
 select exists(select 1 from public.user_roles where user_id=v_actor and organization_id=v_org and role='admin' and revoked_at is null) into v_is_admin;
 if not v_is_root and not v_is_admin then raise exception 'not_authorized'; end if;

 select jsonb_build_object(
   'organization_id',v_org,
   'actor',jsonb_build_object('user_id',v_actor,'is_root',v_is_root,'is_admin',v_is_admin),
   'people',coalesce((select jsonb_agg(x order by x->>'display_name',x->>'email') from (
      select jsonb_build_object('user_id',u.user_id,'display_name',p.display_name,'email',p.email,'profile_status',p.status,'roles',u.roles) x
      from (
        select ur.user_id,jsonb_agg(ur.role::text order by ur.role::text) roles
        from public.user_roles ur where ur.organization_id=v_org and ur.revoked_at is null group by ur.user_id
      ) u left join public.profiles p on p.user_id=u.user_id
   ) q),'[]'::jsonb),
   'properties',coalesce((select jsonb_agg(jsonb_build_object(
       'id',pr.id,'name',pr.name,'address_line',pr.address_line,'city',pr.city,'status',pr.status,
       'responsible_user_id',sa.employee_user_id,'assignment_id',sa.id
     ) order by pr.name)
     from public.properties_v2 pr
     left join public.property_staff_access_v3 sa on sa.property_id=pr.id and sa.assignment_type='responsible' and sa.revoked_at is null
     where pr.organization_id=v_org and pr.archived_at is null),'[]'::jsonb),
   'capability_holders',coalesce((select jsonb_agg(jsonb_build_object(
       'id',h.id,'capability',h.capability,'holder_user_id',h.holder_user_id,'granted_at',h.granted_at
     ) order by h.capability)
     from public.admin_capability_holders h where h.organization_id=v_org and h.revoked_at is null),'[]'::jsonb),
   'pending_requests',coalesce((select jsonb_agg(jsonb_build_object(
       'id',r.id,'capability',r.capability,'requester_user_id',r.requester_user_id,'requested_at',r.requested_at
     ) order by r.requested_at)
     from public.admin_capability_requests r where r.organization_id=v_org and r.status='pending'),'[]'::jsonb)
 ) into v_result;
 return v_result;
end $$;
revoke all on function public.get_permission_management_context(uuid) from public;
grant execute on function public.get_permission_management_context(uuid) to authenticated;
