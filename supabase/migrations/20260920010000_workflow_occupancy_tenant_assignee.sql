-- GestionPisos · Flujos · asignación manual al inquilino del destino
-- Permite que un flujo con ámbito occupancy asigne la ejecución al inquilino
-- activo de esa misma ocupación. No habilita inquilinos ajenos ni amplía permisos
-- de administración del workflow.

create or replace function private.workflow_resolve_execution_assignee_v1(
  p_application_id uuid,
  p_requested_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_org uuid;
  v_scope_type text;
  v_property_id uuid;
  v_occupancy_id uuid;
  v_spec jsonb;
  v_assignment_type text;
  v_assigned_user uuid;
begin
  select
    wa.organization_id,
    wa.scope_type,
    wa.property_id,
    wa.occupancy_id,
    wv.spec
  into
    v_org,
    v_scope_type,
    v_property_id,
    v_occupancy_id,
    v_spec
  from public.workflow_applications_v2 wa
  join public.workflow_definition_versions_v2 wv
    on wv.id=wa.definition_version_id
   and wv.definition_id=wa.definition_id
   and wv.organization_id=wa.organization_id
  where wa.id=p_application_id
    and wa.status='configured';

  if v_org is null then
    raise exception 'workflow_application_not_executable' using errcode='55000';
  end if;

  v_assignment_type:=nullif(v_spec->>'assignmentType','');

  if v_assignment_type='manual' then
    if p_requested_user_id is null then
      raise exception 'workflow_manual_assignee_required' using errcode='22023';
    end if;

    if exists(
      select 1
      from public.user_roles ur
      where ur.user_id=p_requested_user_id
        and ur.role='root'
        and ur.revoked_at is null
    ) then
      v_assigned_user:=p_requested_user_id;
    elsif exists(
      select 1
      from public.user_roles ur
      where ur.user_id=p_requested_user_id
        and ur.organization_id=v_org
        and ur.role='admin'
        and ur.revoked_at is null
    ) then
      v_assigned_user:=p_requested_user_id;
    elsif exists(
      select 1
      from public.user_roles ur
      where ur.user_id=p_requested_user_id
        and ur.organization_id=v_org
        and ur.role='employee'
        and ur.revoked_at is null
    ) and (
      v_property_id is null
      or exists(
        select 1
        from public.property_staff_access_v3 a
        where a.property_id=v_property_id
          and a.employee_user_id=p_requested_user_id
          and a.revoked_at is null
          and (a.valid_until is null or a.valid_until>now())
          and a.can_write=true
          and a.assignment_type in ('responsible','access')
      )
    ) then
      v_assigned_user:=p_requested_user_id;
    elsif v_scope_type='occupancy'
      and v_occupancy_id is not null
      and exists(
        select 1
        from public.occupancies_v2 o
        join public.tenants_v2 t
          on t.id=o.tenant_id
         and t.organization_id=o.organization_id
        where o.id=v_occupancy_id
          and o.organization_id=v_org
          and o.property_id=v_property_id
          and o.status='active'
          and o.starts_on<=current_date
          and (o.ends_on is null or o.ends_on>=current_date)
          and o.user_id=p_requested_user_id
          and t.user_id=p_requested_user_id
          and t.status='active'
          and t.archived_at is null
      )
    then
      v_assigned_user:=p_requested_user_id;
    else
      raise exception 'workflow_manual_assignee_not_eligible' using errcode='42501';
    end if;

  elsif v_assignment_type='property_responsible' then
    if p_requested_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved' using errcode='22023';
    end if;

    if v_property_id is null then
      raise exception 'workflow_property_responsible_scope_required' using errcode='22023';
    end if;

    select a.employee_user_id
    into v_assigned_user
    from public.property_staff_access_v3 a
    join public.user_roles ur
      on ur.user_id=a.employee_user_id
     and ur.organization_id=v_org
     and ur.role in ('employee','admin')
     and ur.revoked_at is null
    where a.property_id=v_property_id
      and a.assignment_type='responsible'
      and a.revoked_at is null
      and (a.valid_until is null or a.valid_until>now())
      and a.can_write=true
    limit 1;

    if v_assigned_user is null then
      raise exception 'workflow_property_responsible_unavailable' using errcode='55000';
    end if;

  elsif v_assignment_type in ('fixed_person','role','active_occupants_rotation') then
    raise exception 'workflow_assignment_not_supported' using errcode='0A000';
  else
    raise exception 'workflow_assignment_invalid' using errcode='22023';
  end if;

  return v_assigned_user;
end;
$$;

revoke all on function private.workflow_resolve_execution_assignee_v1(uuid,uuid)
  from public,anon,authenticated;

comment on function private.workflow_resolve_execution_assignee_v1(uuid,uuid) is
  'Resuelve el asignado de una ejecución. En manual admite ROOT/ADMIN/empleado elegible y, para scope occupancy, únicamente el inquilino activo de esa ocupación.';
