-- Tenant lifecycle task/workflow core. Specialized modules remain authoritative.
create table if not exists public.tenant_tasks_v2 (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete restrict,
 tenant_id uuid not null references public.tenants_v2(id) on delete restrict, property_id uuid references public.properties_v2(id) on delete restrict,
 room_id uuid references public.rooms_v2(id) on delete restrict,
 task_type text not null check (task_type in ('key_pickup','key_delivery','check_in','check_out','cleaning','rent_payment','incident','generic')),
 origin text not null default 'manual' check (origin in ('automatic','manual')), title text not null, description text,
 status text not null default 'pending', due_at timestamptz, assigned_user_id uuid references auth.users(id) on delete set null,
 source_kind text, source_id uuid, created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists tenant_tasks_v2_tenant_idx on public.tenant_tasks_v2(tenant_id);
create index if not exists tenant_tasks_v2_open_idx on public.tenant_tasks_v2(tenant_id,due_at) where status not in ('completed','cancelled');
create table if not exists public.tenant_task_actions_v2 (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tenant_tasks_v2(id) on delete restrict,
 action_key text not null, label text not null, from_status text not null, to_status text not null,
 requires_note boolean not null default false, sort_order integer not null default 0, active boolean not null default true,
 unique(task_id,action_key,from_status)
);
create table if not exists public.tenant_task_history_v2 (
 id uuid primary key default gen_random_uuid(), task_id uuid not null references public.tenant_tasks_v2(id) on delete restrict,
 action_key text not null, action_label text not null, from_status text, to_status text not null, note text,
 actor_user_id uuid references auth.users(id) on delete set null, created_at timestamptz not null default now()
);
create index if not exists tenant_task_history_v2_task_idx on public.tenant_task_history_v2(task_id,created_at);
alter table public.tenant_tasks_v2 enable row level security;
alter table public.tenant_task_actions_v2 enable row level security;
alter table public.tenant_task_history_v2 enable row level security;
create or replace function public.apply_tenant_task_action_v2(p_task_id uuid,p_action_key text,p_note text default null)
returns public.tenant_tasks_v2 language plpgsql security invoker set search_path=public as $$
declare v_task public.tenant_tasks_v2; v_action public.tenant_task_actions_v2;
begin
 select * into v_task from public.tenant_tasks_v2 where id=p_task_id for update;
 if v_task.id is null then raise exception 'task_not_found' using errcode='P0002'; end if;
 select * into v_action from public.tenant_task_actions_v2 where task_id=p_task_id and action_key=p_action_key and from_status=v_task.status and active=true;
 if v_action.id is null then raise exception 'task_action_not_allowed' using errcode='22023'; end if;
 if v_action.requires_note and nullif(btrim(p_note),'') is null then raise exception 'task_action_note_required' using errcode='22023'; end if;
 update public.tenant_tasks_v2 set status=v_action.to_status,updated_at=now() where id=p_task_id returning * into v_task;
 insert into public.tenant_task_history_v2(task_id,action_key,action_label,from_status,to_status,note,actor_user_id)
 values(p_task_id,v_action.action_key,v_action.label,v_action.from_status,v_action.to_status,nullif(btrim(p_note),''),auth.uid());
 return v_task;
end $$;
grant execute on function public.apply_tenant_task_action_v2(uuid,text,text) to authenticated;
