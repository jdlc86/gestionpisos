create or replace function public.manage_platform_operator_service(
  p_action text,
  p_target_user_id uuid,
  p_display_name text,
  p_active boolean,
  p_can_recover_root boolean,
  p_actor_user_id uuid,
  p_organization_id uuid,
  p_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing public.platform_operators%rowtype;
  v_had_existing boolean := false;
  v_event_action text;
  v_root_recovery_count integer := 0;
begin
  if p_action not in ('upsert', 'update') then
    raise exception 'unsupported_action';
  end if;

  if p_target_user_id is null or p_actor_user_id is null then
    raise exception 'invalid_actor_or_target';
  end if;

  if p_target_user_id = p_actor_user_id then
    raise exception 'self_operator_forbidden';
  end if;

  if char_length(trim(coalesce(p_display_name, ''))) < 2 then
    raise exception 'display_name_required';
  end if;

  select *
    into v_existing
  from public.platform_operators
  where user_id = p_target_user_id
  for update;

  v_had_existing := found;

  if p_action = 'update' and not v_had_existing then
    raise exception 'operator_not_found';
  end if;

  if p_action = 'upsert' then
    insert into public.platform_operators (
      user_id,
      display_name,
      active,
      can_recover_root,
      created_by,
      updated_at
    ) values (
      p_target_user_id,
      trim(p_display_name),
      coalesce(p_active, true),
      coalesce(p_can_recover_root, false),
      p_actor_user_id,
      now()
    )
    on conflict (user_id) do update set
      display_name = excluded.display_name,
      active = excluded.active,
      can_recover_root = excluded.can_recover_root,
      updated_at = now();

    v_event_action := case when v_had_existing then 'platform_operator_reactivated' else 'platform_operator_created' end;
  else
    update public.platform_operators
    set display_name = trim(p_display_name),
        active = coalesce(p_active, active),
        can_recover_root = coalesce(p_can_recover_root, can_recover_root),
        updated_at = now()
    where user_id = p_target_user_id;

    v_event_action := 'platform_operator_updated';
  end if;

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
    v_event_action,
    'platform_operator',
    p_target_user_id::text,
    'success',
    jsonb_build_object(
      'email', coalesce(p_email, ''),
      'previous', case when v_had_existing then jsonb_build_object(
        'display_name', v_existing.display_name,
        'active', v_existing.active,
        'can_recover_root', v_existing.can_recover_root
      ) else null end,
      'next', jsonb_build_object(
        'display_name', trim(p_display_name),
        'active', coalesce(p_active, true),
        'can_recover_root', coalesce(p_can_recover_root, false)
      ),
      'actor_role', 'root',
      'changed_at', now()
    )
  );

  select count(*)::integer
    into v_root_recovery_count
  from public.platform_operators
  where active = true
    and can_recover_root = true;

  return jsonb_build_object(
    'ok', true,
    'event_action', v_event_action,
    'active_root_recovery_count', v_root_recovery_count,
    'warning', case when v_root_recovery_count = 0 then 'no_active_root_recovery_operator' else null end
  );
end;
$$;

revoke all on function public.manage_platform_operator_service(text, uuid, text, boolean, boolean, uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.manage_platform_operator_service(text, uuid, text, boolean, boolean, uuid, uuid, text) to service_role;

comment on function public.manage_platform_operator_service(text, uuid, text, boolean, boolean, uuid, uuid, text) is
  'Service-role-only atomic mutation + audit for ROOT-managed emergency platform operators.';
