create or replace function public.apply_photo_verification_review_v2(
  p_run_id uuid,
  p_actor_user_id uuid,
  p_decision text,
  p_rejection_reason text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_run public.photo_verification_runs_v2%rowtype;
  v_now timestamptz := now();
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'invalid decision';
  end if;

  if p_decision = 'rejected' and nullif(btrim(p_rejection_reason),'') is null then
    raise exception 'rejection reason required';
  end if;

  select * into v_run
  from public.photo_verification_runs_v2
  where id = p_run_id
  for update;

  if not found then
    raise exception 'run not found';
  end if;

  if v_run.status not in ('submitted','manual_review','ai_review') then
    raise exception 'run is not reviewable';
  end if;

  update public.photo_verification_items_v2
  set manual_result = p_decision,
      reviewed_by = p_actor_user_id,
      reviewed_at = v_now
  where run_id = p_run_id;

  if not found then
    raise exception 'run has no items';
  end if;

  update public.photo_verification_runs_v2
  set status = p_decision,
      reviewed_by = p_actor_user_id,
      reviewed_at = v_now,
      rejection_reason = case when p_decision = 'rejected' then btrim(p_rejection_reason) else null end
  where id = p_run_id;

  insert into public.audit_log_v2(
    organization_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    result,
    details
  )
  values (
    v_run.organization_id,
    p_actor_user_id,
    'review_photo_verification',
    'photo_verification_run',
    p_run_id::text,
    'success',
    jsonb_build_object(
      'decision', p_decision,
      'rejection_reason', case when p_decision = 'rejected' then btrim(p_rejection_reason) else null end
    )
  );

  return jsonb_build_object(
    'id', p_run_id,
    'status', p_decision,
    'reviewed_at', v_now,
    'reviewed_by', p_actor_user_id
  );
end;
$$;

revoke all on function public.apply_photo_verification_review_v2(uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.apply_photo_verification_review_v2(uuid,uuid,text,text) to service_role;
