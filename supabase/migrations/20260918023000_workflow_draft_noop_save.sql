-- GestionPisos · Flujos de Trabajo · guardado idempotente de borradores
-- Riesgo R3: una pulsacion repetida de Guardar sin cambios no debe fabricar revisiones.

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
  v_authoring_version integer := 1;
  v_sanitized jsonb;
  v_authoring_complete boolean := false;
  v_current_revision bigint;
  v_existing_spec jsonb;
  v_existing_complete boolean;
  v_existing_updated_at timestamptz;
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
  v_flow_type := nullif(p_spec ->> 'flowType','');
  v_description := nullif(btrim(coalesce(p_spec ->> 'flowDescription','')), '');
  v_scope_type := nullif(p_spec ->> 'scopeType','');
  v_trigger_type := nullif(p_spec ->> 'triggerType','');
  v_recurrence := nullif(p_spec ->> 'recurrence','');
  v_assignment_type := nullif(p_spec ->> 'assignmentType','');
  v_close_type := nullif(p_spec ->> 'closeType','');
  v_steps := coalesce(p_spec -> 'steps', '{}'::jsonb);
  v_notifications := coalesce(p_spec -> 'notifications', '{}'::jsonb);

  if coalesce(p_spec ->> 'authoringVersion','') ~ '^[0-9]+$' then
    v_authoring_version := greatest(1, (p_spec ->> 'authoringVersion')::integer);
  end if;

  -- Los clientes anteriores a v2 enviaban opciones seleccionadas por defecto.
  -- Se conservan nombre/descripcion, pero esas opciones no se aceptan como decisiones.
  if v_authoring_version < 2 then
    v_flow_type := null;
    v_scope_type := null;
    v_trigger_type := null;
    v_recurrence := null;
    v_assignment_type := null;
    v_close_type := null;
    v_steps := '{}'::jsonb;
    v_notifications := '{}'::jsonb;
  end if;

  if char_length(v_name) < 3 or char_length(v_name) > 80 then
    raise exception 'workflow_name_invalid' using errcode = '22023';
  end if;
  if v_flow_type is not null and v_flow_type not in ('cleaning','inspection','maintenance','checkin','checkout','custom') then
    raise exception 'workflow_type_invalid' using errcode = '22023';
  end if;
  if v_description is not null and char_length(v_description) > 400 then
    raise exception 'workflow_description_too_long' using errcode = '22023';
  end if;
  if v_scope_type is not null and v_scope_type not in ('organization','property','room','occupancy') then
    raise exception 'workflow_scope_invalid' using errcode = '22023';
  end if;
  if v_trigger_type is not null and v_trigger_type not in ('manual','recurring','scheduled_once','event') then
    raise exception 'workflow_trigger_invalid' using errcode = '22023';
  end if;
  if v_trigger_type = 'recurring' and v_recurrence is not null and v_recurrence not in ('weekly','biweekly','monthly','custom') then
    raise exception 'workflow_recurrence_invalid' using errcode = '22023';
  end if;
  if v_trigger_type is distinct from 'recurring' then
    v_recurrence := null;
  end if;
  if v_assignment_type is not null and v_assignment_type not in ('property_responsible','active_occupants_rotation','fixed_person','role','manual') then
    raise exception 'workflow_assignment_invalid' using errcode = '22023';
  end if;
  if v_close_type is not null and v_close_type not in ('auto','human_review','domain_adapter') then
    raise exception 'workflow_close_invalid' using errcode = '22023';
  end if;
  if jsonb_typeof(v_steps) <> 'object' or jsonb_typeof(v_notifications) <> 'object' then
    raise exception 'workflow_nested_spec_invalid' using errcode = '22023';
  end if;

  if (v_steps ? 'accept' and jsonb_typeof(v_steps -> 'accept') <> 'boolean')
    or (v_steps ? 'photo' and jsonb_typeof(v_steps -> 'photo') <> 'boolean')
    or (v_steps ? 'checklist' and jsonb_typeof(v_steps -> 'checklist') <> 'boolean')
    or (v_steps ? 'document' and jsonb_typeof(v_steps -> 'document') <> 'boolean')
    or (v_notifications ? 'onCreate' and jsonb_typeof(v_notifications -> 'onCreate') <> 'boolean')
    or (v_notifications ? 'onClose' and jsonb_typeof(v_notifications -> 'onClose') <> 'boolean') then
    raise exception 'workflow_nested_spec_invalid' using errcode = '22023';
  end if;

  v_sanitized := jsonb_build_object(
    'authoringVersion', v_authoring_version,
    'flowName', v_name,
    'flowType', coalesce(v_flow_type,''),
    'flowDescription', coalesce(v_description,''),
    'scopeType', coalesce(v_scope_type,''),
    'triggerType', coalesce(v_trigger_type,''),
    'recurrence', coalesce(v_recurrence,''),
    'assignmentType', coalesce(v_assignment_type,''),
    'steps', jsonb_build_object(
      'accept', coalesce((v_steps ->> 'accept')::boolean, false),
      'photo', coalesce((v_steps ->> 'photo')::boolean, false),
      'checklist', coalesce((v_steps ->> 'checklist')::boolean, false),
      'document', coalesce((v_steps ->> 'document')::boolean, false)
    ),
    'closeType', coalesce(v_close_type,''),
    'notifications', jsonb_build_object(
      'onCreate', coalesce((v_notifications ->> 'onCreate')::boolean, false),
      'onClose', coalesce((v_notifications ->> 'onClose')::boolean, false)
    )
  );

  v_authoring_complete := public.workflow_authoring_complete_v1(v_sanitized);

  if p_definition_id is null then
    insert into public.workflow_definitions_v2 (
      organization_id, name, flow_type, description, scope_type,
      trigger_type, assignment_type, close_type, status, draft_spec,
      authoring_complete, created_by, updated_by
    ) values (
      v_org, v_name, v_flow_type, v_description, v_scope_type,
      v_trigger_type, v_assignment_type, v_close_type, 'draft', v_sanitized,
      v_authoring_complete, v_actor, v_actor
    )
    returning id, workflow_definitions_v2.revision, workflow_definitions_v2.updated_at
    into v_id, v_current_revision, v_updated_at;

    insert into public.audit_log_v2 (
      organization_id, actor_user_id, action, entity_type, entity_id, result, details
    ) values (
      v_org, v_actor, 'workflow_draft_created', 'workflow_definition', v_id::text, 'success',
      jsonb_build_object(
        'flow_type',v_flow_type,
        'scope_type',v_scope_type,
        'revision',v_current_revision,
        'authoring_complete',v_authoring_complete
      )
    );
  else
    select wd.revision, wd.draft_spec, wd.authoring_complete, wd.updated_at
    into v_current_revision, v_existing_spec, v_existing_complete, v_existing_updated_at
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

    -- Guardar sin cambios es idempotente: no crea una revision ficticia,
    -- no altera updated_at y no genera un evento de auditoria de actualizacion.
    if v_existing_spec = v_sanitized
      and v_existing_complete = v_authoring_complete then
      v_id := p_definition_id;
      v_updated_at := v_existing_updated_at;
      return query select v_id, v_current_revision, v_updated_at;
      return;
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
        authoring_complete = v_authoring_complete,
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
      jsonb_build_object(
        'flow_type',v_flow_type,
        'scope_type',v_scope_type,
        'revision',v_current_revision,
        'authoring_complete',v_authoring_complete
      )
    );
  end if;

  return query select v_id, v_current_revision, v_updated_at;
end;
$$;

revoke execute on function public.save_workflow_definition_draft_v1(jsonb, uuid, bigint) from public;
revoke execute on function public.save_workflow_definition_draft_v1(jsonb, uuid, bigint) from anon;
grant execute on function public.save_workflow_definition_draft_v1(jsonb, uuid, bigint) to authenticated;


comment on function public.save_workflow_definition_draft_v1(jsonb, uuid, bigint) is
  'Guarda borradores de flujo. Si la especificacion saneada no cambia, devuelve la revision existente sin tocar updated_at ni auditoria.';
