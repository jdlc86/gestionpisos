-- GestionPisos · WF-03 · swap/deuda de Limpieza sobre el motor transversal
-- El swap legacy sigue siendo la autoridad del intercambio entre ocupantes,
-- pero una limpieza enlazada debe mantener el mismo asignado/estado en:
-- cleaning_tasks_v2 + workflow_executions_v2 + tenant_tasks_v2.
-- La deuda sigue siendo una unidad no monetaria por swap aceptado.

create or replace function private.workflow_apply_cleaning_swap_accept_v1(
  p_swap_request_id uuid,
  p_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $workflow_cleaning_swap$
declare
  v_swap public.cleaning_swap_requests_v2;
  v_cleaning public.cleaning_tasks_v2;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_existing_event public.workflow_execution_events_v2;
  v_debt public.cleaning_debts_v2;
  v_from_workflow_status text;
  v_from_domain_status text;
begin
  select *
  into v_swap
  from public.cleaning_swap_requests_v2
  where id=p_swap_request_id
  for update;

  if v_swap.id is null then
    raise exception 'cleaning_swap_not_found' using errcode='P0002';
  end if;

  if p_actor_user_id is null
    or p_actor_user_id is distinct from v_swap.target_user_id then
    raise exception 'cleaning_swap_actor_forbidden' using errcode='42501';
  end if;

  select *
  into v_cleaning
  from public.cleaning_tasks_v2
  where id=v_swap.cleaning_task_id
  for update;

  if v_cleaning.id is null then
    raise exception 'cleaning_task_not_found' using errcode='P0002';
  end if;

  if not exists (
    select 1
    from public.occupancies_v2 o
    where o.property_id=v_cleaning.property_id
      and o.user_id=v_swap.target_user_id
      and o.status='active'
      and o.starts_on<=current_date
      and (o.ends_on is null or o.ends_on>=current_date)
  ) then
    raise exception 'target no longer occupies property' using errcode='55000';
  end if;

  -- Reintento interno ya aplicado: no crear segunda deuda/evento.
  if v_swap.status='accepted'
    and v_cleaning.assigned_user_id=v_swap.target_user_id then
    if v_cleaning.workflow_execution_id is null then
      if exists(
        select 1
        from public.cleaning_debts_v2 d
        where d.swap_request_id=v_swap.id
          and d.debtor_user_id=v_swap.requester_user_id
          and d.creditor_user_id=v_swap.target_user_id
          and d.source_task_id=v_cleaning.id
      ) then
        return jsonb_build_object(
          'ok',true,
          'workflow_linked',false,
          'applied_new',false,
          'cleaning_status',v_cleaning.status
        );
      end if;
    else
      select *
      into v_execution
      from public.workflow_executions_v2
      where id=v_cleaning.workflow_execution_id
      for update;

      select *
      into v_task
      from public.tenant_tasks_v2
      where source_kind='workflow_execution'
        and source_id=v_execution.id
      for update;

      select *
      into v_existing_event
      from public.workflow_execution_events_v2 ev
      where ev.execution_id=v_execution.id
        and ev.event_type='domain_adapter_assignee_changed'
        and ev.details->>'swap_request_id'=v_swap.id::text
      order by ev.id
      limit 1;

      if v_execution.id is not null
        and v_task.id is not null
        and v_execution.assigned_user_id=v_swap.target_user_id
        and v_task.assigned_user_id=v_swap.target_user_id
        and v_execution.status='active'
        and v_task.status='active'
        and v_cleaning.status='accepted'
        and v_existing_event.id is not null
        and exists(
          select 1
          from public.cleaning_debts_v2 d
          where d.swap_request_id=v_swap.id
            and d.debtor_user_id=v_swap.requester_user_id
            and d.creditor_user_id=v_swap.target_user_id
            and d.source_task_id=v_cleaning.id
        ) then
        return jsonb_build_object(
          'ok',true,
          'workflow_linked',true,
          'applied_new',false,
          'cleaning_status',v_cleaning.status,
          'task_status',v_task.status,
          'execution_status',v_execution.status,
          'assigned_user_id',v_execution.assigned_user_id
        );
      end if;
    end if;

    raise exception 'cleaning_swap_retry_state_mismatch' using errcode='55000';
  end if;

  if v_swap.status<>'pending' then
    raise exception 'cleaning_swap_not_pending' using errcode='55000';
  end if;

  if v_cleaning.assigned_user_id is distinct from v_swap.requester_user_id then
    raise exception 'task assignee changed' using errcode='55000';
  end if;

  if v_cleaning.status not in ('pending','accepted') then
    raise exception 'task cannot be swapped in current state' using errcode='55000';
  end if;

  v_from_domain_status:=v_cleaning.status;

  -- Legacy sin vínculo: conservar exactamente el comportamiento existente.
  if v_cleaning.workflow_execution_id is null then
    update public.cleaning_tasks_v2
    set assigned_user_id=v_swap.target_user_id,
        status='accepted',
        updated_at=now()
    where id=v_cleaning.id
    returning * into v_cleaning;

    insert into public.cleaning_debts_v2(
      organization_id,property_id,debtor_user_id,creditor_user_id,
      source_task_id,swap_request_id,amount,status
    ) values (
      v_cleaning.organization_id,
      v_cleaning.property_id,
      v_swap.requester_user_id,
      v_swap.target_user_id,
      v_cleaning.id,
      v_swap.id,
      1,
      'open'
    )
    on conflict do nothing
    returning * into v_debt;

    if v_debt.id is null then
      select *
      into v_debt
      from public.cleaning_debts_v2
      where swap_request_id=v_swap.id;
    end if;

    return jsonb_build_object(
      'ok',true,
      'workflow_linked',false,
      'applied_new',true,
      'cleaning_status',v_cleaning.status,
      'assigned_user_id',v_cleaning.assigned_user_id,
      'debt_id',v_debt.id
    );
  end if;

  select *
  into v_execution
  from public.workflow_executions_v2
  where id=v_cleaning.workflow_execution_id
  for update;

  if v_execution.id is null
    or coalesce(v_execution.spec_snapshot->>'flowType','')<>'cleaning'
    or coalesce(v_execution.spec_snapshot->>'closeType','')<>'domain_adapter'
    or v_execution.organization_id<>v_cleaning.organization_id
    or v_execution.property_id is distinct from v_cleaning.property_id
    or v_execution.room_id is distinct from v_cleaning.room_id then
    raise exception 'workflow_cleaning_swap_identity_mismatch' using errcode='55000';
  end if;

  select *
  into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id
  for update;

  if v_task.id is null
    or v_task.organization_id<>v_execution.organization_id
    or v_task.property_id is distinct from v_execution.property_id
    or v_task.room_id is distinct from v_execution.room_id
    or v_task.assigned_user_id is distinct from v_execution.assigned_user_id
    or v_execution.assigned_user_id is distinct from v_swap.requester_user_id then
    raise exception 'workflow_cleaning_swap_task_mismatch' using errcode='55000';
  end if;

  v_from_workflow_status:=v_execution.status;

  if v_task.status is distinct from v_execution.status then
    raise exception 'workflow_task_execution_state_mismatch' using errcode='55000';
  end if;

  if v_cleaning.status='pending' then
    if v_execution.status<>'pending' then
      raise exception 'workflow_cleaning_swap_state_mismatch' using errcode='55000';
    end if;
  elsif v_cleaning.status='accepted' then
    if v_execution.status<>'active' then
      raise exception 'workflow_cleaning_swap_state_mismatch' using errcode='55000';
    end if;
  end if;

  update public.cleaning_tasks_v2
  set assigned_user_id=v_swap.target_user_id,
      status='accepted',
      updated_at=now()
  where id=v_cleaning.id
  returning * into v_cleaning;

  update public.tenant_tasks_v2
  set assigned_user_id=v_swap.target_user_id,
      status='active',
      updated_at=now()
  where id=v_task.id
  returning * into v_task;

  update public.workflow_executions_v2 as e
  set assigned_user_id=v_swap.target_user_id,
      status='active',
      started_at=coalesce(e.started_at,now()),
      updated_at=now()
  where id=v_execution.id
  returning * into v_execution;

  insert into public.cleaning_debts_v2(
    organization_id,property_id,debtor_user_id,creditor_user_id,
    source_task_id,swap_request_id,amount,status
  ) values (
    v_cleaning.organization_id,
    v_cleaning.property_id,
    v_swap.requester_user_id,
    v_swap.target_user_id,
    v_cleaning.id,
    v_swap.id,
    1,
    'open'
  )
  on conflict do nothing
  returning * into v_debt;

  if v_debt.id is null then
    select *
    into v_debt
    from public.cleaning_debts_v2
    where swap_request_id=v_swap.id;
  end if;

  insert into public.tenant_task_history_v2(
    task_id,action_key,action_label,from_status,to_status,note,actor_user_id
  ) values (
    v_task.id,
    'cleaning_swap_accepted',
    'Cambio de limpieza aceptado',
    v_from_workflow_status,
    'active',
    'Responsabilidad transferida por cambio entre ocupantes.',
    p_actor_user_id
  );

  insert into public.workflow_execution_events_v2(
    execution_id,organization_id,event_type,from_status,to_status,actor_user_id,details
  ) values (
    v_execution.id,
    v_execution.organization_id,
    'domain_adapter_assignee_changed',
    v_from_workflow_status,
    'active',
    p_actor_user_id,
    jsonb_build_object(
      'adapter','cleaning',
      'cleaning_task_id',v_cleaning.id,
      'swap_request_id',v_swap.id,
      'debt_id',v_debt.id,
      'from_assigned_user_id',v_swap.requester_user_id,
      'to_assigned_user_id',v_swap.target_user_id,
      'domain_from_status',v_from_domain_status,
      'domain_to_status','accepted',
      'debt_units',1
    )
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_execution.organization_id,
    p_actor_user_id,
    'workflow_cleaning_swap_accepted',
    'workflow_execution',
    v_execution.id::text,
    'success',
    jsonb_build_object(
      'cleaning_task_id',v_cleaning.id,
      'swap_request_id',v_swap.id,
      'debt_id',v_debt.id,
      'from_assigned_user_id',v_swap.requester_user_id,
      'to_assigned_user_id',v_swap.target_user_id,
      'from_status',v_from_workflow_status,
      'to_status','active',
      'debt_units',1
    )
  );

  return jsonb_build_object(
    'ok',true,
    'workflow_linked',true,
    'applied_new',true,
    'cleaning_status',v_cleaning.status,
    'task_status',v_task.status,
    'execution_status',v_execution.status,
    'assigned_user_id',v_execution.assigned_user_id,
    'debt_id',v_debt.id
  );
end;
$workflow_cleaning_swap$;

revoke all on function private.workflow_apply_cleaning_swap_accept_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

create or replace function private.apply_cleaning_swap_decision()
returns trigger
language plpgsql
security definer
set search_path=''
as $workflow_cleaning_swap_trigger$
begin
  if old.status<>'pending' then
    raise exception 'only pending requests can be decided';
  end if;

  if new.cleaning_task_id is distinct from old.cleaning_task_id
    or new.requester_user_id is distinct from old.requester_user_id
    or new.target_user_id is distinct from old.target_user_id
    or new.requested_at is distinct from old.requested_at then
    raise exception 'swap request identity is immutable';
  end if;

  if new.status not in ('accepted','rejected','cancelled') then
    raise exception 'invalid swap decision';
  end if;

  if new.status in ('accepted','rejected')
    and auth.uid() is distinct from old.target_user_id then
    raise exception 'only target can accept or reject';
  end if;

  if new.status='cancelled'
    and auth.uid() is distinct from old.requester_user_id then
    raise exception 'only requester can cancel';
  end if;

  new.decided_at:=coalesce(new.decided_at,now());
  new.decided_by:=auth.uid();

  if new.status='accepted' then
    perform private.workflow_apply_cleaning_swap_accept_v1(
      old.id,
      auth.uid()
    );
  end if;

  return new;
end;
$workflow_cleaning_swap_trigger$;

revoke all on function private.apply_cleaning_swap_decision()
  from public,anon,authenticated,service_role;

comment on function private.workflow_apply_cleaning_swap_accept_v1(uuid,uuid) is
  'Aplica idempotentemente un swap aceptado de Limpieza; si el expediente está enlazado sincroniza asignado/estado con workflow y mantiene una deuda legacy de 1 unidad.';
comment on function private.apply_cleaning_swap_decision() is
  'Valida la decisión de swap y delega la aceptación al adaptador WF-03 sin cambiar el contrato legacy para tareas no enlazadas.';
