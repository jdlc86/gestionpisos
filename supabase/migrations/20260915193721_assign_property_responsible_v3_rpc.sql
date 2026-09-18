create or replace function public.assign_property_responsible_v3(p_property_id uuid,p_employee_user_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_org uuid; v_id uuid; v_old uuid;
begin
 if v_actor is null then raise exception 'not_authenticated'; end if;
 select organization_id into v_org from public.properties_v2 where id=p_property_id and archived_at is null for update;
 if v_org is null then raise exception 'property_not_found_or_archived'; end if;
 if not exists(select 1 from public.user_roles where user_id=v_actor and role='root' and revoked_at is null) then
   if not exists(select 1 from public.user_roles where user_id=v_actor and organization_id=v_org and role='admin' and revoked_at is null) then raise exception 'not_authorized'; end if;
   if not exists(select 1 from public.admin_capability_holders where organization_id=v_org and capability='property_lifecycle' and holder_user_id=v_actor and revoked_at is null) then raise exception 'property_lifecycle_required'; end if;
 end if;
 if not exists(select 1 from public.user_roles where user_id=p_employee_user_id and organization_id=v_org and role in ('employee','admin') and revoked_at is null) then raise exception 'target_not_eligible'; end if;
 select id,employee_user_id into v_id,v_old from public.property_staff_access_v3 where property_id=p_property_id and assignment_type='responsible' and revoked_at is null for update;
 if v_id is not null and v_old=p_employee_user_id then return v_id; end if;
 update public.property_staff_access_v3 set revoked_at=now() where property_id=p_property_id and assignment_type='responsible' and revoked_at is null;
 insert into public.property_staff_access_v3(organization_id,property_id,employee_user_id,assignment_type,can_write,valid_from,valid_until,granted_by,revoked_at)
 values(v_org,p_property_id,p_employee_user_id,'responsible',true,now(),null,v_actor,null) returning id into v_id;
 insert into public.audit_log_v2(organization_id,actor_user_id,action,entity_type,entity_id,result,details)
 values(v_org,v_actor,'assign_property_responsible','property',p_property_id::text,'success',jsonb_build_object('responsible_user_id',p_employee_user_id,'assignment_id',v_id,'previous_responsible_user_id',v_old));
 return v_id;
end $$;
revoke all on function public.assign_property_responsible_v3(uuid,uuid) from public;
grant execute on function public.assign_property_responsible_v3(uuid,uuid) to authenticated;
