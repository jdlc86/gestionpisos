create or replace function public.provision_employee_profile_role(p_user_id uuid,p_email text,p_display_name text,p_organization_id uuid,p_role public.app_role default 'employee')
returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.role() <> 'service_role' then raise exception 'service_role_required' using errcode='42501'; end if;
 if p_role not in ('admin','owner','employee','tenant') then raise exception 'invalid_provision_role' using errcode='22023'; end if;
 insert into public.profiles(user_id,organization_id,display_name,email,status)
 values(p_user_id,p_organization_id,nullif(trim(p_display_name),''),lower(trim(p_email)),'active')
 on conflict(user_id) do update set organization_id=excluded.organization_id,display_name=excluded.display_name,email=excluded.email,status='active',archived_at=null,updated_at=now();
 insert into public.user_roles(user_id,organization_id,role,created_by)
 values(p_user_id,p_organization_id,p_role,null)
 on conflict do nothing;
end; $$;
revoke all on function public.provision_employee_profile_role(uuid,text,text,uuid,public.app_role) from public,anon,authenticated;
grant execute on function public.provision_employee_profile_role(uuid,text,text,uuid,public.app_role) to service_role;
