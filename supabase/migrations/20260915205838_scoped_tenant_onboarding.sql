create or replace function public.create_tenant_occupancy_v3(p_property_id uuid,p_room_id uuid,p_full_name text,p_document_type text,p_document_number text,p_email text,p_starts_on date,p_ends_on date default null,p_indefinite boolean default true)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_org uuid; v_tenant public.tenants_v2; v_occ public.occupancies_v2; v_email text:=lower(btrim(p_email)); v_doc text:=upper(btrim(p_document_number));
begin
 if auth.uid() is null then raise exception 'not_authenticated' using errcode='42501'; end if;
 select organization_id into v_org from public.properties_v2 where id=p_property_id and archived_at is null;
 if v_org is null then raise exception 'property_not_found' using errcode='P0002'; end if;
 if not public.can_operate_property_v3(p_property_id,true) then raise exception 'property_write_required' using errcode='42501'; end if;
 if not exists(select 1 from public.rooms_v2 where id=p_room_id and property_id=p_property_id and archived_at is null) then raise exception 'room_property_mismatch' using errcode='42501'; end if;
 if p_starts_on is null or (not p_indefinite and p_ends_on is null) or (p_ends_on is not null and p_ends_on<p_starts_on) then raise exception 'occupancy_dates_invalid' using errcode='22023'; end if;
 select * into v_tenant from public.tenants_v2 where organization_id=v_org and document_type=p_document_type and document_number=v_doc for update;
 if v_tenant.id is null then
   if exists(select 1 from public.tenants_v2 where organization_id=v_org and lower(email)=v_email) then raise exception 'tenant_email_identity_conflict' using errcode='23505'; end if;
   insert into public.tenants_v2(organization_id,full_name,document_type,document_number,email,status)
   values(v_org,btrim(p_full_name),p_document_type,v_doc,v_email,'active') returning * into v_tenant;
 else
   if lower(v_tenant.email)<>v_email then raise exception 'tenant_document_identity_conflict' using errcode='23505'; end if;
   update public.tenants_v2 set full_name=btrim(p_full_name),status='active',archived_at=null,updated_at=now() where id=v_tenant.id returning * into v_tenant;
 end if;
 insert into public.occupancies_v2(organization_id,tenant_id,property_id,room_id,occupant_email,starts_on,ends_on,status)
 values(v_org,v_tenant.id,p_property_id,p_room_id,v_email,p_starts_on,case when p_indefinite then null else p_ends_on end,'active') returning * into v_occ;
 return jsonb_build_object('tenant_id',v_tenant.id,'occupancy_id',v_occ.id);
end $$;
revoke all on function public.create_tenant_occupancy_v3(uuid,uuid,text,text,text,text,date,date,boolean) from public,anon;
grant execute on function public.create_tenant_occupancy_v3(uuid,uuid,text,text,text,text,date,date,boolean) to authenticated;
