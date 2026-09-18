create table if not exists public.tenant_task_workflow_templates_v2 (
 task_type text not null,
 action_key text not null,
 label text not null,
 from_status text not null,
 to_status text not null,
 requires_note boolean not null default false,
 sort_order integer not null default 0,
 primary key(task_type,action_key,from_status)
);
alter table public.tenant_task_workflow_templates_v2 enable row level security;

insert into public.tenant_task_workflow_templates_v2(task_type,action_key,label,from_status,to_status,requires_note,sort_order) values
('key_pickup','accept','Aceptar','requested','accepted',false,10),
('key_pickup','reject','Rechazar','requested','rejected',true,20),
('key_pickup','complete','Confirmar recogida','accepted','completed',false,10),
('key_delivery','accept','Aceptar','requested','accepted',false,10),
('key_delivery','reject','Rechazar','requested','rejected',true,20),
('key_delivery','complete','Confirmar entrega','accepted','completed',false,10),
('check_in','confirm','Confirmar entrada','scheduled','completed',false,10),
('check_in','reschedule','Reprogramar','scheduled','scheduled',true,20),
('check_out','confirm','Confirmar salida','scheduled','completed',false,10),
('check_out','reschedule','Reprogramar','scheduled','scheduled',true,20),
('cleaning','accept','Aceptar','assigned','accepted',false,10),
('cleaning','request_change','Solicitar cambio','assigned','change_requested',true,20),
('cleaning','start','Iniciar','accepted','in_progress',false,10),
('cleaning','submit','Finalizar y enviar','in_progress','submitted',false,10),
('cleaning','approve','Aprobar','submitted','completed',false,10),
('cleaning','reject','Rechazar revisión','submitted','rejected',true,20),
('rent_payment','register_payment','Registrar pago','pending','completed',false,10),
('rent_payment','request_payment','Solicitar pago','pending','requested',false,20),
('rent_payment','postpone','Aplazar','pending','postponed',true,30),
('rent_payment','register_payment','Registrar pago','requested','completed',false,10),
('rent_payment','postpone','Aplazar','requested','postponed',true,20),
('incident','accept','Aceptar gestión','open','in_progress',false,10),
('incident','request_info','Solicitar información','open','waiting_info',true,20),
('incident','request_info','Solicitar información','in_progress','waiting_info',true,20),
('incident','resume','Continuar gestión','waiting_info','in_progress',false,10),
('incident','resolve','Resolver','in_progress','completed',true,20),
('generic','accept','Aceptar','pending','accepted',false,10),
('generic','reject','Rechazar','pending','rejected',true,20),
('generic','request_info','Solicitar información','pending','waiting_info',true,30),
('generic','complete','Completar','accepted','completed',false,10),
('generic','request_info','Solicitar información','accepted','waiting_info',true,20),
('generic','resume','Continuar','waiting_info','accepted',false,10)
on conflict(task_type,action_key,from_status) do update set label=excluded.label,to_status=excluded.to_status,requires_note=excluded.requires_note,sort_order=excluded.sort_order;

create or replace function public.seed_tenant_task_actions_v2()
returns trigger language plpgsql set search_path=public as $$
begin
 insert into public.tenant_task_actions_v2(task_id,action_key,label,from_status,to_status,requires_note,sort_order)
 select new.id,w.action_key,w.label,w.from_status,w.to_status,w.requires_note,w.sort_order
 from public.tenant_task_workflow_templates_v2 w where w.task_type=new.task_type
 on conflict(task_id,action_key,from_status) do nothing;
 return new;
end $$;
drop trigger if exists tenant_task_seed_actions_v2 on public.tenant_tasks_v2;
create trigger tenant_task_seed_actions_v2 after insert on public.tenant_tasks_v2 for each row execute function public.seed_tenant_task_actions_v2();

create or replace function public.create_tenant_task_v2(
 p_tenant_id uuid,p_task_type text,p_title text,p_description text default null,p_due_at timestamptz default null,
 p_assigned_user_id uuid default null,p_property_id uuid default null,p_room_id uuid default null,p_origin text default 'manual',
 p_source_kind text default null,p_source_id uuid default null)
returns public.tenant_tasks_v2 language plpgsql security invoker set search_path=public as $$
declare v_tenant public.tenants_v2; v_task public.tenant_tasks_v2; v_initial text;
begin
 select * into v_tenant from public.tenants_v2 where id=p_tenant_id;
 if v_tenant.id is null then raise exception 'tenant_not_found' using errcode='P0002'; end if;
 v_initial:=case p_task_type when 'key_pickup' then 'requested' when 'key_delivery' then 'requested'
 when 'check_in' then 'scheduled' when 'check_out' then 'scheduled' when 'cleaning' then 'assigned'
 when 'rent_payment' then 'pending' when 'incident' then 'open' when 'generic' then 'pending'
 else null end;
 if v_initial is null then raise exception 'task_type_invalid' using errcode='22023'; end if;
 insert into public.tenant_tasks_v2(organization_id,tenant_id,property_id,room_id,task_type,origin,title,description,status,due_at,assigned_user_id,source_kind,source_id,created_by)
 values(v_tenant.organization_id,p_tenant_id,p_property_id,p_room_id,p_task_type,p_origin,p_title,p_description,v_initial,p_due_at,p_assigned_user_id,p_source_kind,p_source_id,auth.uid())
 returning * into v_task;
 insert into public.tenant_task_history_v2(task_id,action_key,action_label,from_status,to_status,note,actor_user_id)
 values(v_task.id,'create',case when p_origin='automatic' then 'Creada automáticamente' else 'Creada manualmente' end,null,v_initial,null,auth.uid());
 return v_task;
end $$;
grant execute on function public.create_tenant_task_v2(uuid,text,text,text,timestamptz,uuid,uuid,uuid,text,text,uuid) to authenticated;
