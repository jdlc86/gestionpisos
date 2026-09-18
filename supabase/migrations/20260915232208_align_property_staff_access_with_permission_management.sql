create or replace function public.grant_property_staff_access_v3(p_property_id uuid,p_employee_user_id uuid,p_can_write boolean default false) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_org uuid; v_id uuid;
begin
 if v_actor is null then raise exception 'not_authenticated'; end if;
 select organization_id into v_org from public.properties_v2 where id=p_property_id and archived_at is null for update;
 if v_org is null then raise exception 'property_not_found_or_archived'; end if;
 if not public.can_manage_permissions(v_org) then raise exception 'permission_management_write_required'; end if;
 if not exists(select 1 from public.user_roles where user_id=p_employee_user_id and organization_id=v_org and role in ('employee','admin') and revoked_at is null) then raise exception 'target_not_eligible'; end if;
 if exists(select 1 from public.property_staff_access_v3 where property_id=p_property_id and employee_user_id=p_employee_user_id and assignment_type='responsible' and revoked_at is null) then raise exception 'target_is_responsible'; end if;
 select id into v_id from public.property_staff_access_v3 where property_id=p_property_id and employee_user_id=p_employee_user_id and assignment_type='access' and revoked_at is null for update;
 if v_id is not null then update public.property_staff_access_v3 set can_write=p_can_write where id=v_id;
 else insert into public.property_staff_access_v3(organization_id,property_id,employee_user_id,assignment_type,can_write,valid_from,valid_until,granted_by,revoked_at) values(v_org,p_property_id,p_employee_user_id,'access',p_can_write,now(),null,v_actor,null) returning id into v_id; end if;
 insert into public.audit_log_v2(organization_id,actor_user_id,action,entity_type,entity_id,result,details) values(v_org,v_actor,'grant_property_staff_access','property',p_property_id::text,'success',jsonb_build_object('employee_user_id',p_employee_user_id,'assignment_id',v_id,'can_write',p_can_write));
 return v_id;
end $$;
create or replace function public.revoke_property_staff_access_v3(p_property_id uuid,p_employee_user_id uuid) returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_org uuid; v_id uuid;
begin
 if v_actor is null then raise exception 'not_authenticated'; end if;
 select organization_id into v_org from public.properties_v2 where id=p_property_id and archived_at is null for update;
 if v_org is null then raise exception 'property_not_found_or_archived'; end if;
 if not public.can_manage_permissions(v_org) then raise exception 'permission_management_write_required'; end if;
 select id into v_id from public.property_staff_access_v3 where property_id=p_property_id and employee_user_id=p_employee_user_id and assignment_type='access' and revoked_at is null for update;
 if v_id is null then return false; end if;
 update public.property_staff_access_v3 set revoked_at=now() where id=v_id;
 insert into public.audit_log_v2(organization_id,actor_user_id,action,entity_type,entity_id,result,details) values(v_org,v_actor,'revoke_property_staff_access','property',p_property_id::text,'success',jsonb_build_object('employee_user_id',p_employee_user_id,'assignment_id',v_id));
 return true;
end $$;
