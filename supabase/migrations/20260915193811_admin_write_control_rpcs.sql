create or replace function public.request_admin_write_control(p_organization_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_request_id uuid;
begin
 if v_actor is null then raise exception 'not_authenticated'; end if;
 if not exists(select 1 from public.user_roles where user_id=v_actor and organization_id=p_organization_id and role='admin' and revoked_at is null) then raise exception 'admin_required'; end if;
 if exists(select 1 from public.admin_capability_holders where organization_id=p_organization_id and capability='write_control' and holder_user_id=v_actor and revoked_at is null) then raise exception 'already_write_control_holder'; end if;
 select id into v_request_id from public.admin_capability_requests where organization_id=p_organization_id and capability='write_control' and requester_user_id=v_actor and status='pending';
 if v_request_id is not null then return v_request_id; end if;
 insert into public.admin_capability_requests(organization_id,capability,requester_user_id,status)
 values(p_organization_id,'write_control',v_actor,'pending') returning id into v_request_id;
 insert into public.audit_log_v2(organization_id,actor_user_id,action,entity_type,entity_id,result,details)
 values(p_organization_id,v_actor,'request_admin_write_control','admin_capability_request',v_request_id::text,'success',jsonb_build_object('capability','write_control'));
 return v_request_id;
end $$;
revoke all on function public.request_admin_write_control(uuid) from public;
grant execute on function public.request_admin_write_control(uuid) to authenticated;

create or replace function public.decide_admin_write_control_request(p_request_id uuid,p_accept boolean)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_org uuid; v_requester uuid; v_capability text; v_status text; v_current_holder uuid; v_is_root boolean:=false; v_result text;
begin
 if v_actor is null then raise exception 'not_authenticated'; end if;
 select organization_id,requester_user_id,capability,status into v_org,v_requester,v_capability,v_status
 from public.admin_capability_requests where id=p_request_id for update;
 if v_org is null then raise exception 'request_not_found'; end if;
 if v_status<>'pending' then raise exception 'request_not_pending'; end if;
 if v_capability<>'write_control' then raise exception 'invalid_capability'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_org::text||':write_control',0));
 select holder_user_id into v_current_holder from public.admin_capability_holders
 where organization_id=v_org and capability='write_control' and revoked_at is null for update;
 select exists(select 1 from public.user_roles where user_id=v_actor and role='root' and revoked_at is null) into v_is_root;
 if not v_is_root and v_current_holder is distinct from v_actor then raise exception 'current_holder_required'; end if;
 if p_accept then
   if not exists(select 1 from public.user_roles where user_id=v_requester and organization_id=v_org and role='admin' and revoked_at is null) then raise exception 'requester_no_longer_admin'; end if;
   update public.admin_capability_holders set revoked_at=now()
    where organization_id=v_org and capability='write_control' and revoked_at is null;
   insert into public.admin_capability_holders(organization_id,capability,holder_user_id,granted_by)
    values(v_org,'write_control',v_requester,v_actor);
   v_result:='approved';
 else
   v_result:='rejected';
 end if;
 update public.admin_capability_requests set status=v_result,decided_at=now(),decided_by=v_actor where id=p_request_id;
 insert into public.audit_log_v2(organization_id,actor_user_id,action,entity_type,entity_id,result,details)
 values(v_org,v_actor,'decide_admin_write_control_request','admin_capability_request',p_request_id::text,'success',
 jsonb_build_object('decision',v_result,'requester_user_id',v_requester,'previous_holder_user_id',v_current_holder));
 return v_result;
end $$;
revoke all on function public.decide_admin_write_control_request(uuid,boolean) from public;
grant execute on function public.decide_admin_write_control_request(uuid,boolean) to authenticated;
