alter table public.tenant_task_workflow_templates_v2 add column if not exists actor text not null default 'agency' check(actor in ('agency','tenant','assignee','system'));
alter table public.tenant_task_actions_v2 add column if not exists actor text not null default 'agency' check(actor in ('agency','tenant','assignee','system'));

-- Request/response actions belong to the tenant where the task is explicitly a request to them.
update public.tenant_task_workflow_templates_v2 set actor='tenant'
where (task_type in ('key_pickup','key_delivery') and action_key in ('accept','reject'))
   or (task_type in ('rent_claim','damage_claim') and action_key in ('accept','reject'))
   or (task_type='generic' and action_key in ('accept','reject','request_info','resume','complete'));
-- Cleaning execution belongs to the assigned worker; review remains agency.
update public.tenant_task_workflow_templates_v2 set actor='assignee'
where task_type='cleaning' and action_key in ('accept','request_change','start','submit');
-- Explicit system transitions can later use actor=system; none are enabled yet.

update public.tenant_task_actions_v2 a set actor=w.actor
from public.tenant_task_workflow_templates_v2 w
where w.task_type=(select t.task_type from public.tenant_tasks_v2 t where t.id=a.task_id)
 and w.action_key=a.action_key and w.from_status=a.from_status;

create or replace function public.seed_tenant_task_actions_v2() returns trigger language plpgsql set search_path=public as $$
begin
 insert into public.tenant_task_actions_v2(task_id,action_key,label,from_status,to_status,requires_note,sort_order,actor)
 select new.id,w.action_key,w.label,w.from_status,w.to_status,w.requires_note,w.sort_order,w.actor
 from public.tenant_task_workflow_templates_v2 w where w.task_type=new.task_type
 on conflict(task_id,action_key,from_status) do nothing; return new;
end $$;

create or replace function public.apply_tenant_task_action_v2(p_task_id uuid,p_action_key text,p_note text default null)
returns public.tenant_tasks_v2 language plpgsql security invoker set search_path=public as $$
declare v_task public.tenant_tasks_v2; v_action public.tenant_task_actions_v2; v_role text; v_tenant_user uuid;
begin
 select * into v_task from public.tenant_tasks_v2 where id=p_task_id for update;
 if v_task.id is null then raise exception 'task_not_found' using errcode='P0002'; end if;
 select * into v_action from public.tenant_task_actions_v2 where task_id=p_task_id and action_key=p_action_key and from_status=v_task.status and active=true;
 if v_action.id is null then raise exception 'task_action_not_allowed' using errcode='22023'; end if;
 v_role:=coalesce(auth.jwt()->'app_metadata'->>'role','');
 select user_id into v_tenant_user from public.tenants_v2 where id=v_task.tenant_id;
 if v_action.actor='agency' and v_role not in ('admin','root') then raise exception 'task_action_actor_forbidden' using errcode='42501'; end if;
 if v_action.actor='tenant' and auth.uid() is distinct from v_tenant_user then raise exception 'task_action_actor_forbidden' using errcode='42501'; end if;
 if v_action.actor='assignee' and auth.uid() is distinct from v_task.assigned_user_id then raise exception 'task_action_actor_forbidden' using errcode='42501'; end if;
 if v_action.actor='system' then raise exception 'task_action_actor_forbidden' using errcode='42501'; end if;
 if v_action.requires_note and nullif(btrim(p_note),'') is null then raise exception 'task_action_note_required' using errcode='22023'; end if;
 update public.tenant_tasks_v2 set status=v_action.to_status,updated_at=now() where id=p_task_id returning * into v_task;
 insert into public.tenant_task_history_v2(task_id,action_key,action_label,from_status,to_status,note,actor_user_id)
 values(p_task_id,v_action.action_key,v_action.label,v_action.from_status,v_action.to_status,nullif(btrim(p_note),''),auth.uid());
 return v_task;
end $$;
