-- Tenant operational RPCs must enforce the same property-scoped authorization as RLS.
create or replace function public.create_tenant_task_v2(p_tenant_id uuid,p_task_type text,p_title text,p_description text default null,p_due_at timestamptz default null,p_assigned_user_id uuid default null,p_property_id uuid default null,p_room_id uuid default null,p_origin text default 'manual',p_source_kind text default null,p_source_id uuid default null)
returns public.tenant_tasks_v2 language plpgsql security definer set search_path=public,pg_temp as $$
declare v_tenant public.tenants_v2; v_task public.tenant_tasks_v2; v_initial text; v_property uuid:=p_property_id;
begin
 if auth.uid() is null then raise exception 'not_authenticated' using errcode='42501'; end if;
 select * into v_tenant from public.tenants_v2 where id=p_tenant_id;
 if v_tenant.id is null then raise exception 'tenant_not_found' using errcode='P0002'; end if;
 if v_property is null then select o.property_id into v_property from public.occupancies_v2 o where o.tenant_id=p_tenant_id and o.status in ('active','blocked') order by o.created_at desc limit 1; end if;
 if v_property is null or not public.can_operate_property_v3(v_property,true) then raise exception 'property_write_required' using errcode='42501'; end if;
 if not exists(select 1 from public.properties_v2 p where p.id=v_property and p.organization_id=v_tenant.organization_id and p.archived_at is null) then raise exception 'property_tenant_scope_mismatch' using errcode='42501'; end if;
 if p_room_id is not null and not exists(select 1 from public.rooms_v2 r where r.id=p_room_id and r.property_id=v_property and r.archived_at is null) then raise exception 'room_property_scope_mismatch' using errcode='42501'; end if;
 v_initial:=case p_task_type when 'key_pickup' then 'requested' when 'key_delivery' then 'requested' when 'check_in' then 'scheduled' when 'check_out' then 'scheduled' when 'cleaning' then 'assigned' when 'rent_payment' then 'pending' when 'rent_claim' then 'draft' when 'damage_claim' then 'draft' when 'deposit' then 'pending' when 'incident' then 'open' when 'generic' then 'pending' else null end;
 if v_initial is null then raise exception 'task_type_invalid' using errcode='22023'; end if;
 insert into public.tenant_tasks_v2(organization_id,tenant_id,property_id,room_id,task_type,origin,title,description,status,due_at,assigned_user_id,source_kind,source_id,created_by)
 values(v_tenant.organization_id,p_tenant_id,v_property,p_room_id,p_task_type,p_origin,p_title,p_description,v_initial,p_due_at,p_assigned_user_id,p_source_kind,p_source_id,auth.uid()) returning * into v_task;
 insert into public.tenant_task_history_v2(task_id,action_key,action_label,from_status,to_status,note,actor_user_id) values(v_task.id,'create',case when p_origin='automatic' then 'Creada automáticamente' else 'Creada manualmente' end,null,v_initial,null,auth.uid());
 return v_task;
end $$;

create or replace function public.apply_tenant_task_action_v2(p_task_id uuid,p_action_key text,p_note text default null)
returns public.tenant_tasks_v2 language plpgsql security definer set search_path=public,pg_temp as $$
declare v_task public.tenant_tasks_v2; v_action public.tenant_task_actions_v2; v_tenant_user uuid;
begin
 if auth.uid() is null then raise exception 'not_authenticated' using errcode='42501'; end if;
 select * into v_task from public.tenant_tasks_v2 where id=p_task_id for update;
 if v_task.id is null then raise exception 'task_not_found' using errcode='P0002'; end if;
 select * into v_action from public.tenant_task_actions_v2 where task_id=p_task_id and action_key=p_action_key and from_status=v_task.status and active=true;
 if v_action.id is null then raise exception 'task_action_not_allowed' using errcode='22023'; end if;
 select user_id into v_tenant_user from public.tenants_v2 where id=v_task.tenant_id;
 if v_action.actor='agency' and not public.can_operate_property_v3(v_task.property_id,true) then raise exception 'task_action_actor_forbidden' using errcode='42501'; end if;
 if v_action.actor='tenant' and auth.uid() is distinct from v_tenant_user then raise exception 'task_action_actor_forbidden' using errcode='42501'; end if;
 if v_action.actor='assignee' and auth.uid() is distinct from v_task.assigned_user_id then raise exception 'task_action_actor_forbidden' using errcode='42501'; end if;
 if v_action.actor='system' then raise exception 'task_action_actor_forbidden' using errcode='42501'; end if;
 if v_action.requires_note and nullif(btrim(p_note),'') is null then raise exception 'task_action_note_required' using errcode='22023'; end if;
 update public.tenant_tasks_v2 set status=v_action.to_status,updated_at=now() where id=p_task_id returning * into v_task;
 insert into public.tenant_task_history_v2(task_id,action_key,action_label,from_status,to_status,note,actor_user_id) values(p_task_id,v_action.action_key,v_action.label,v_action.from_status,v_action.to_status,nullif(btrim(p_note),''),auth.uid());
 return v_task;
end $$;

create or replace function public.offboard_tenant_occupancy_v2(p_occupancy_id uuid,p_ends_on date)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_tenant_id uuid; v_property_id uuid; v_status public.record_status;
begin
 if auth.uid() is null then raise exception 'not_authenticated' using errcode='42501'; end if;
 if p_ends_on is null or p_ends_on<current_date then raise exception 'offboarding_end_invalid' using errcode='22023'; end if;
 select tenant_id,property_id,status into v_tenant_id,v_property_id,v_status from public.occupancies_v2 where id=p_occupancy_id for update;
 if v_tenant_id is null then raise exception 'occupancy_not_found' using errcode='P0002'; end if;
 if not public.can_operate_property_v3(v_property_id,true) then raise exception 'property_write_required' using errcode='42501'; end if;
 if v_status not in ('active','blocked') then raise exception 'offboarding_invalid_state' using errcode='22023'; end if;
 update public.occupancies_v2 set status='archived',ends_on=p_ends_on,starts_on=case when v_status='blocked' then null else starts_on end where id=p_occupancy_id;
 update public.tenants_v2 set status='archived',archived_at=coalesce(archived_at,now()),deletion_requested_at=coalesce(deletion_requested_at,now()),deletion_requested_by=coalesce(deletion_requested_by,auth.uid()),updated_at=now() where id=v_tenant_id;
end $$;

revoke all on function public.create_tenant_task_v2(uuid,text,text,text,timestamptz,uuid,uuid,uuid,text,text,uuid) from public;
revoke all on function public.apply_tenant_task_action_v2(uuid,text,text) from public;
revoke all on function public.offboard_tenant_occupancy_v2(uuid,date) from public;
grant execute on function public.create_tenant_task_v2(uuid,text,text,text,timestamptz,uuid,uuid,uuid,text,text,uuid) to authenticated;
grant execute on function public.apply_tenant_task_action_v2(uuid,text,text) to authenticated;
grant execute on function public.offboard_tenant_occupancy_v2(uuid,date) to authenticated;
