-- Workflow templates and central task creator already applied to production as tenant_task_initial_workflows.
create table if not exists public.tenant_task_workflow_templates_v2 (
 task_type text not null, action_key text not null, label text not null, from_status text not null, to_status text not null,
 requires_note boolean not null default false, sort_order integer not null default 0,
 primary key(task_type,action_key,from_status)
);
alter table public.tenant_task_workflow_templates_v2 enable row level security;
-- Canonical initial workflows are intentionally idempotent.
insert into public.tenant_task_workflow_templates_v2 values
('key_pickup','accept','Aceptar','requested','accepted',false,10),('key_pickup','reject','Rechazar','requested','rejected',true,20),('key_pickup','complete','Confirmar recogida','accepted','completed',false,10),
('key_delivery','accept','Aceptar','requested','accepted',false,10),('key_delivery','reject','Rechazar','requested','rejected',true,20),('key_delivery','complete','Confirmar entrega','accepted','completed',false,10),
('check_in','confirm','Confirmar entrada','scheduled','completed',false,10),('check_in','reschedule','Reprogramar','scheduled','scheduled',true,20),
('check_out','confirm','Confirmar salida','scheduled','completed',false,10),('check_out','reschedule','Reprogramar','scheduled','scheduled',true,20),
('cleaning','accept','Aceptar','assigned','accepted',false,10),('cleaning','request_change','Solicitar cambio','assigned','change_requested',true,20),('cleaning','start','Iniciar','accepted','in_progress',false,10),('cleaning','submit','Finalizar y enviar','in_progress','submitted',false,10),('cleaning','approve','Aprobar','submitted','completed',false,10),('cleaning','reject','Rechazar revisión','submitted','rejected',true,20),
('rent_payment','register_payment','Registrar pago','pending','completed',false,10),('rent_payment','request_payment','Solicitar pago','pending','requested',false,20),('rent_payment','postpone','Aplazar','pending','postponed',true,30),('rent_payment','register_payment','Registrar pago','requested','completed',false,10),('rent_payment','postpone','Aplazar','requested','postponed',true,20),
('incident','accept','Aceptar gestión','open','in_progress',false,10),('incident','request_info','Solicitar información','open','waiting_info',true,20),('incident','request_info','Solicitar información','in_progress','waiting_info',true,20),('incident','resume','Continuar gestión','waiting_info','in_progress',false,10),('incident','resolve','Resolver','in_progress','completed',true,20),
('generic','accept','Aceptar','pending','accepted',false,10),('generic','reject','Rechazar','pending','rejected',true,20),('generic','request_info','Solicitar información','pending','waiting_info',true,30),('generic','complete','Completar','accepted','completed',false,10),('generic','request_info','Solicitar información','accepted','waiting_info',true,20),('generic','resume','Continuar','waiting_info','accepted',false,10)
on conflict(task_type,action_key,from_status) do update set label=excluded.label,to_status=excluded.to_status,requires_note=excluded.requires_note,sort_order=excluded.sort_order;
create or replace function public.seed_tenant_task_actions_v2() returns trigger language plpgsql set search_path=public as $$ begin
 insert into public.tenant_task_actions_v2(task_id,action_key,label,from_status,to_status,requires_note,sort_order)
 select new.id,w.action_key,w.label,w.from_status,w.to_status,w.requires_note,w.sort_order from public.tenant_task_workflow_templates_v2 w where w.task_type=new.task_type
 on conflict(task_id,action_key,from_status) do nothing; return new; end $$;
drop trigger if exists tenant_task_seed_actions_v2 on public.tenant_tasks_v2;
create trigger tenant_task_seed_actions_v2 after insert on public.tenant_tasks_v2 for each row execute function public.seed_tenant_task_actions_v2();
