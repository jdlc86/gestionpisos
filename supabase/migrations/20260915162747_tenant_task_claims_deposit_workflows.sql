alter table public.tenant_tasks_v2 drop constraint if exists tenant_tasks_v2_task_type_check;
alter table public.tenant_tasks_v2 add constraint tenant_tasks_v2_task_type_check check (task_type in ('key_pickup','key_delivery','check_in','check_out','cleaning','rent_payment','rent_claim','damage_claim','deposit','incident','generic'));

insert into public.tenant_task_workflow_templates_v2(task_type,action_key,label,from_status,to_status,requires_note,sort_order) values
('rent_claim','notify','Notificar reclamación','draft','claimed',false,10),
('rent_claim','accept','Aceptar','claimed','accepted',false,10),
('rent_claim','reject','Rechazar','claimed','disputed',true,20),
('rent_claim','request_info','Solicitar información','claimed','waiting_info',true,30),
('rent_claim','resume','Continuar reclamación','waiting_info','claimed',false,10),
('rent_claim','resolve','Resolver','accepted','completed',true,10),
('rent_claim','resolve','Resolver','disputed','completed',true,10),
('damage_claim','notify','Notificar reclamación','draft','claimed',false,10),
('damage_claim','accept','Aceptar','claimed','accepted',false,10),
('damage_claim','reject','Rechazar','claimed','disputed',true,20),
('damage_claim','request_info','Solicitar información','claimed','waiting_info',true,30),
('damage_claim','resume','Continuar reclamación','waiting_info','claimed',false,10),
('damage_claim','resolve','Resolver','accepted','completed',true,10),
('damage_claim','resolve','Resolver','disputed','completed',true,10),
('deposit','register_receipt','Registrar recepción','pending','received',false,10),
('deposit','start_review','Iniciar revisión','received','under_review',false,10),
('deposit','request_info','Solicitar información','under_review','waiting_info',true,20),
('deposit','resume','Continuar revisión','waiting_info','under_review',false,10),
('deposit','refund','Devolver fianza','under_review','refunded',false,10),
('deposit','partial_hold','Retener parcialmente','under_review','partially_held',true,20),
('deposit','hold','Retener fianza','under_review','held',true,30)
on conflict(task_type,action_key,from_status) do update set label=excluded.label,to_status=excluded.to_status,requires_note=excluded.requires_note,sort_order=excluded.sort_order;

create or replace function public.create_tenant_task_v2(
 p_tenant_id uuid,p_task_type text,p_title text,p_description text default null,p_due_at timestamptz default null,
 p_assigned_user_id uuid default null,p_property_id uuid default null,p_room_id uuid default null,p_origin text default 'manual',
 p_source_kind text default null,p_source_id uuid default null)
returns public.tenant_tasks_v2 language plpgsql security invoker set search_path=public as $$
declare v_tenant public.tenants_v2; v_task public.tenant_tasks_v2; v_initial text;
begin
 select * into v_tenant from public.tenants_v2 where id=p_tenant_id;
 if v_tenant.id is null then raise exception 'tenant_not_found' using errcode='P0002'; end if;
 v_initial:=case p_task_type
 when 'key_pickup' then 'requested' when 'key_delivery' then 'requested'
 when 'check_in' then 'scheduled' when 'check_out' then 'scheduled'
 when 'cleaning' then 'assigned' when 'rent_payment' then 'pending'
 when 'rent_claim' then 'draft' when 'damage_claim' then 'draft'
 when 'deposit' then 'pending' when 'incident' then 'open' when 'generic' then 'pending'
 else null end;
 if v_initial is null then raise exception 'task_type_invalid' using errcode='22023'; end if;
 insert into public.tenant_tasks_v2(organization_id,tenant_id,property_id,room_id,task_type,origin,title,description,status,due_at,assigned_user_id,source_kind,source_id,created_by)
 values(v_tenant.organization_id,p_tenant_id,p_property_id,p_room_id,p_task_type,p_origin,p_title,p_description,v_initial,p_due_at,p_assigned_user_id,p_source_kind,p_source_id,auth.uid())
 returning * into v_task;
 insert into public.tenant_task_history_v2(task_id,action_key,action_label,from_status,to_status,note,actor_user_id)
 values(v_task.id,'create',case when p_origin='automatic' then 'Creada automáticamente' else 'Creada manualmente' end,null,v_initial,null,auth.uid());
 return v_task;
end $$;
