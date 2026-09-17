-- GestionPisos · Flujos de Trabajo · persistencia de definiciones (fase 3)
-- Riesgo R3: nuevas tablas sensibles + RLS + RPC de escritura.
-- Este incremento persiste solo borradores. No publica versiones ni crea ejecuciones/tareas.

create table if not exists public.workflow_definitions_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  name text not null check (char_length(btrim(name)) between 3 and 80),
  flow_type text not null check (flow_type in ('cleaning','inspection','maintenance','checkin','checkout','custom')),
  description text,
  scope_type text not null check (scope_type in ('organization','property','room','occupancy')),
  trigger_type text not null check (trigger_type in ('manual','recurring','scheduled_once','event')),
  assignment_type text not null check (assignment_type in ('property_responsible','active_occupants_rotation','fixed_person','role','manual')),
  close_type text not null check (close_type in ('auto','human_review','domain_adapter')),
  status text not null default 'draft' check (status in ('draft','published','paused','archived')),
  draft_spec jsonb not null check (jsonb_typeof(draft_spec) = 'object'),
  revision bigint not null default 1 check (revision > 0),
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  check (description is null or char_length(description) <= 400),
  check ((status = 'archived') = (archived_at is not null))
);

create index if not exists workflow_definitions_v2_org_status_idx
  on public.workflow_definitions_v2 (organization_id, status, updated_at desc);

create table if not exists public.workflow_definition_versions_v2 (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null references public.workflow_definitions_v2(id),
  organization_id uuid not null references public.organizations(id),
  version integer not null check (version > 0),
  spec jsonb not null check (jsonb_typeof(spec) = 'object'),
  published_by uuid not null,
  published_at timestamptz not null default now(),
  unique (definition_id, version)
);

create index if not exists workflow_definition_versions_v2_org_definition_idx
  on public.workflow_definition_versions_v2 (organization_id, definition_id, version desc);

alter table public.workflow_definitions_v2 enable row level security;
alter table public.workflow_definition_versions_v2 enable row level security;

revoke all on public.workflow_definitions_v2 from anon;
revoke all on public.workflow_definition_versions_v2 from anon;
revoke insert, update, delete, truncate, references, trigger on public.workflow_definitions_v2 from authenticated;
revoke insert, update, delete, truncate, references, trigger on public.workflow_definition_versions_v2 from authenticated;
grant select on public.workflow_definitions_v2 to authenticated;
grant select on public.workflow_definition_versions_v2 to authenticated;

create or replace function public.workflow_can_read_definitions_v1(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null
    and (
      exists (
        select 1
        from public.user_roles ur
        where ur.user_id = auth.uid()
          and ur.role = 'root'
          and ur.revoked_at is null
      )
      or exists (
        select 1
        from public.user_roles ur
        where ur.user_id = auth.uid()
          and ur.organization_id = p_organization_id
          and ur.role = 'admin'
          and ur.revoked_at is null
      )
    );
$$;

revoke all on function public.workflow_can_read_definitions_v1(uuid) from public;
grant execute on function public.workflow_can_read_definitions_v1(uuid) to authenticated;

create policy workflow_definitions_v2_read_authorized
on public.workflow_definitions_v2
for select
to authenticated
using (public.workflow_can_read_definitions_v1(organization_id));

create policy workflow_definition_versions_v2_read_authorized
on public.workflow_definition_versions_v2
for select
to authenticated
using (public.workflow_can_read_definitions_v1(organization_id));

create or replace function public.save_workflow_definition_draft_v1(
  p_spec jsonb,
  p_definition_id uuid default null,
  p_expected_revision bigint default null
)
returns table(definition_id uuid, revision bigint, updated_at timestamptz)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_org uuid;
  v_role public.app_role;
  v_name text;
  v_flow_type text;
  v_description text;
  v_scope_type text;
  v_trigger_type text;
  v_recurrence text;
  v_assignment_type text;
  v_close_type text;
  v_steps jsonb;
  v_notifications jsonb;
  v_sanitized jsonb;
  v_current_revision bigint;
  v_id uuid;
  v_updated_at timestamptz;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select ur.role, ur.organization_id
  into v_role, v_org
  from public.user_roles ur
  where ur.user_id = v_actor
    and ur.revoked_at is null
    and ur.role in ('root','admin')
  order by case when ur.role = 'root' then 0 else 1 end
  limit 1;

  if v_role is null then
    raise exception 'workflow_author_role_required' using errcode = '42501';
  end if;

  if v_role = 'root' and v_org is null then
    select o.id
    into v_org
    from public.organizations o
    where o.status = 'active'
    order by o.created_at
    limit 1;

    if v_org is null then
      raise exception 'organization_missing';
    end if;

    if (select count(*) from public.organizations o where o.status = 'active') <> 1 then
      raise exception 'organization_selection_required';
    end if;
  end if;

  if v_org is null then
    raise exception 'organization_missing';
  end if;

  if p_spec is null or jsonb_typeof(p_spec) <> 'object' then
    raise exception 'workflow_spec_object_required' using errcode = '22023';
  end if;

  v_name := btrim(coalesce(p_spec ->> 'flowName',''));
  v_flow_type := p_spec ->> 'flowType';
  v_description := nullif(btrim(coalesce(p_spec ->> 'flowDescription','')), '');
  v_scope_type := p_spec ->> 'scopeType';
  v_trigger_type := p_spec ->> 'triggerType';
  v_recurrence := nullif(p_spec ->> 'recurrence','');
  v_assignment_type := p_spec ->> 'assignmentType';
  v_close_type := p_spec ->> 'closeType';
  v_steps := coalesce(p_spec -> 'steps', '{}'::jsonb);
  v_notifications := coalesce(p_spec -> 'notifications', '{}'::jsonb);

  if char_length(v_name) < 3 or char_length(v_name) > 80 then
    raise exception 'workflow_name_invalid' using errcode = '22023';
  end if;
  if v_flow_type not in ('cleaning','inspection','maintenance','checkin','checkout','custom') then
    raise exception 'workflow_type_invalid' using errcode = '22023';
  end if;
  if v_description is not null and char_length(v_description) > 400 then
    raise exception 'workflow_description_too_long' using errcode = '22023';
  end if;
  if v_scope_type not in ('organization','property','room','occupancy') then
    raise exception 'workflow_scope_invalid' using errcode = '22023';
  end if;
  if v_trigger_type not in ('manual','recurring','scheduled_once','event') then
    raise exception 'workflow_trigger_invalid' using errcode = '22023';
  end if;
  if v_trigger_type = 'recurring' and v_recurrence not in ('weekly','biweekly','monthly','custom') then
    raise exception 'workflow_recurrence_invalid' using errcode = '22023';
  end if;
  if v_trigger_type <> 'recurring' then
    v_recurrence := null;
  end if;
  if v_assignment_type not in ('property_responsible','active_occupants_rotation','fixed_person','role','manual') then
    raise exception 'workflow_assignment_invalid' using errcode = '22023';
  end if;
  if v_close_type not in ('auto','human_review','domain_adapter') then
    raise exception 'workflow_close_invalid' using errcode = '22023';
  end if;
  if jsonb_typeof(v_steps) <> 'object' or jsonb_typeof(v_notifications) <> 'object' then
    raise exception 'workflow_nested_spec_invalid' using errcode = '22023';
  end if;

  v_sanitized := jsonb_build_object(
    'flowName', v_name,
    'flowType', v_flow_type,
    'flowDescription', coalesce(v_description,''),
    'scopeType', v_scope_type,
    'triggerType', v_trigger_type,
    'recurrence', coalesce(v_recurrence,''),
    'assignmentType', v_assignment_type,
    'steps', jsonb_build_object(
      'accept', coalesce((v_steps ->> 'accept')::boolean, false),
      'photo', coalesce((v_steps ->> 'photo')::boolean, false),
      'checklist', coalesce((v_steps ->> 'checklist')::boolean, false),
      'document', coalesce((v_steps ->> 'document')::boolean, false)
    ),
    'closeType', v_close_type,
    'notifications', jsonb_build_object(
      'onCreate', coalesce((v_notifications ->> 'onCreate')::boolean, false),
      'onClose', coalesce((v_notifications ->> 'onClose')::boolean, false)
    )
  );

  if p_definition_id is null then
    insert into public.workflow_definitions_v2 (
      organization_id, name, flow_type, description, scope_type,
      trigger_type, assignment_type, close_type, status, draft_spec,
      created_by, updated_by
    ) values (
      v_org, v_name, v_flow_type, v_description, v_scope_type,
      v_trigger_type, v_assignment_type, v_close_type, 'draft', v_sanitized,
      v_actor, v_actor
    )
    returning id, workflow_definitions_v2.revision, workflow_definitions_v2.updated_at
    into v_id, v_current_revision, v_updated_at;

    insert into public.audit_log_v2 (
      organization_id, actor_user_id, action, entity_type, entity_id, result, details
    ) values (
      v_org, v_actor, 'workflow_draft_created', 'workflow_definition', v_id::text, 'success',
      jsonb_build_object('flow_type',v_flow_type,'scope_type',v_scope_type,'revision',v_current_revision)
    );
  else
    select wd.revision
    into v_current_revision
    from public.workflow_definitions_v2 wd
    where wd.id = p_definition_id
      and wd.organization_id = v_org
    for update;

    if v_current_revision is null then
      raise exception 'workflow_definition_not_found' using errcode = 'P0002';
    end if;

    if not exists (
      select 1 from public.workflow_definitions_v2 wd
      where wd.id = p_definition_id and wd.status = 'draft'
    ) then
      raise exception 'workflow_definition_not_editable' using errcode = '55000';
    end if;

    if p_expected_revision is not null and p_expected_revision <> v_current_revision then
      raise exception 'workflow_draft_conflict' using errcode = '40001';
    end if;

    update public.workflow_definitions_v2 wd
    set name = v_name,
        flow_type = v_flow_type,
        description = v_description,
        scope_type = v_scope_type,
        trigger_type = v_trigger_type,
        assignment_type = v_assignment_type,
        close_type = v_close_type,
        draft_spec = v_sanitized,
        revision = wd.revision + 1,
        updated_by = v_actor,
        updated_at = now()
    where wd.id = p_definition_id
    returning wd.id, wd.revision, wd.updated_at
    into v_id, v_current_revision, v_updated_at;

    insert into public.audit_log_v2 (
      organization_id, actor_user_id, action, entity_type, entity_id, result, details
    ) values (
      v_org, v_actor, 'workflow_draft_updated', 'workflow_definition', v_id::text, 'success',
      jsonb_build_object('flow_type',v_flow_type,'scope_type',v_scope_type,'revision',v_current_revision)
    );
  end if;

  return query select v_id, v_current_revision, v_updated_at;
end;
$$;

revoke all on function public.save_workflow_definition_draft_v1(jsonb, uuid, bigint) from public;
grant execute on function public.save_workflow_definition_draft_v1(jsonb, uuid, bigint) to authenticated;

comment on table public.workflow_definitions_v2 is
  'Definiciones estables de Flujos de Trabajo. Fase 3: borradores persistentes; publicación se añade en incremento posterior.';
comment on table public.workflow_definition_versions_v2 is
  'Versiones publicadas e inmutables de una definición. La tabla se crea antes del endpoint de publicación; sin políticas de escritura cliente.';
