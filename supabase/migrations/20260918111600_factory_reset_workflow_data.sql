-- GestionPisos · Factory reset · incluir datos operativos del motor de workflows
-- Mantiene la semántica de 20260917194500 y añade explícitamente las nuevas tablas.

create or replace function public.factory_reset_test_data_service(
  p_actor_user_id uuid,
  p_operator_user_id uuid,
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reset_at timestamptz := now();
  v_profile_organization_id uuid;
  v_active_organization_count integer := 0;
begin
  perform set_config('lock_timeout', '5s', true);
  perform set_config('statement_timeout', '30s', true);

  if p_actor_user_id is null or p_operator_user_id is null or p_organization_id is null then
    raise exception 'factory_reset_invalid_protected_identity';
  end if;

  if p_actor_user_id = p_operator_user_id then
    raise exception 'factory_reset_operator_must_be_independent';
  end if;

  -- ROOT is intentionally allowed to be global (organization_id = null).
  -- This matches get_effective_organization_id(): an active profile wins;
  -- otherwise a global ROOT may operate only when exactly one organization is active.
  if not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = p_actor_user_id
      and lower(ur.role::text) = 'root'
      and ur.revoked_at is null
  ) then
    raise exception 'factory_reset_root_required';
  end if;

  if not exists (
    select 1
    from public.organizations o
    where o.id = p_organization_id
      and lower(o.status::text) = 'active'
  ) then
    raise exception 'factory_reset_active_organization_required';
  end if;

  select p.organization_id
    into v_profile_organization_id
  from public.profiles p
  where p.user_id = p_actor_user_id
    and lower(p.status::text) = 'active'
  limit 1;

  if v_profile_organization_id is not null then
    if v_profile_organization_id <> p_organization_id then
      raise exception 'factory_reset_root_organization_mismatch';
    end if;
  else
    select count(*)
      into v_active_organization_count
    from public.organizations o
    where lower(o.status::text) = 'active';

    if v_active_organization_count <> 1 then
      raise exception 'factory_reset_root_organization_ambiguous';
    end if;
  end if;

  if not exists (
    select 1
    from public.platform_operators po
    where po.user_id = p_operator_user_id
      and po.active = true
      and po.can_recover_root = true
  ) then
    raise exception 'factory_reset_root_recovery_operator_required';
  end if;

  truncate table
    public.access_requests,
    public.admin_capability_holders,
    public.admin_capability_requests,
    public.audit_log_v2,
    public.broadcasts_v2,
    public.claims_v2,
    public.cleaning_audit_items_v2,
    public.cleaning_audit_policies_v2,
    public.cleaning_audits_v2,
    public.cleaning_debts_v2,
    public.cleaning_photo_request_policies_v2,
    public.cleaning_photo_requests_v2,
    public.cleaning_plans_v2,
    public.cleaning_swap_requests_v2,
    public.cleaning_tasks_v2,
    public.external_account_onboarding,
    public.incident_evidence_v2,
    public.incident_updates_v2,
    public.incidents_v2,
    public.internal_staff_onboarding,
    public.internal_staff_onboarding_access_snapshot,
    public.notifications_v2,
    public.occupancies_v2,
    public.owners,
    public.payment_obligations_v2,
    public.photo_patterns_v2,
    public.photo_verification_items_v2,
    public.photo_verification_runs_v2,
    public.properties,
    public.properties_v2,
    public.property_qr_tokens,
    public.property_staff_access_v2,
    public.property_staff_access_v3,
    public.property_staff_assignments,
    public.random_photo_requests_v2,
    public.reminder_rules_v2,
    public.rooms,
    public.rooms_v2,
    public.tenancies,
    public.tenant_documents_v2,
    public.tenant_privacy_events_v2,
    public.tenant_task_actions_v2,
    public.tenant_task_history_v2,
    public.tenant_tasks_v2,
    public.tenants_v2,
    public.verification_policies_v2,
    public.workflow_execution_events_v2,
    public.workflow_executions_v2,
    public.workflow_applications_v2,
    public.workflow_definition_versions_v2,
    public.workflow_definitions_v2
  restart identity;

  delete from public.platform_operators
  where user_id <> p_operator_user_id;

  delete from public.profiles
  where user_id <> p_actor_user_id;

  delete from public.user_roles
  where user_id <> p_actor_user_id;

  delete from public.organizations
  where id <> p_organization_id;

  insert into public.audit_log_v2 (
    organization_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    result,
    details
  ) values (
    p_organization_id,
    p_actor_user_id,
    'factory_reset_completed',
    'organization',
    p_organization_id::text,
    'success',
    jsonb_build_object(
      'mode', 'test_factory_reset',
      'preserved_root_user_id', p_actor_user_id,
      'preserved_operator_user_id', p_operator_user_id,
      'historical_audit_cleared', true,
      'static_workflow_templates_preserved', true,
      'completed_at', v_reset_at
    )
  );

  return jsonb_build_object(
    'ok', true,
    'completed_at', v_reset_at,
    'preserved_root_user_id', p_actor_user_id,
    'preserved_operator_user_id', p_operator_user_id,
    'preserved_organization_id', p_organization_id
  );
end;
$$;

revoke all on function public.factory_reset_test_data_service(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.factory_reset_test_data_service(uuid, uuid, uuid) to service_role;

comment on function public.factory_reset_test_data_service(uuid, uuid, uuid) is
  'Service-role-only destructive test reset. Supports global ROOT using the same effective-organization rule as get_effective_organization_id; preserves ROOT, one ROOT-recovery operator, the active organization and static task templates while clearing workflow definitions, applications, executions, events and materialized tasks.';
