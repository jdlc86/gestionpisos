-- GestionPisos · WF-07 · enlace de ejecuciones a fianza y daños

create or replace function private.workflow_wf07_seed_deposit_receipt_actions_v1(
  p_execution_id uuid
)
returns void
language plpgsql
security definer
set search_path=''
as $wf07_seed_receipt$
declare
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
begin
  select * into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id;

  if v_execution.id is null
    or v_execution.spec_snapshot->>'flowType'<>'deposit_receipt'
    or v_execution.spec_snapshot->>'closeType'<>'domain_adapter'
    or v_execution.security_deposit_id is null then
    return;
  end if;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id;

  if v_task.id is null then
    raise exception 'workflow_wf07_task_missing' using errcode='55000';
  end if;

  insert into public.tenant_task_actions_v2(
    task_id,action_key,label,from_status,to_status,
    requires_note,sort_order,active,actor
  ) values (
    v_task.id,'register_receipt','Registrar recepción',
    'pending','completed',false,10,true,'assignee'
  )
  on conflict(task_id,action_key,from_status)
  do update set
    label=excluded.label,to_status=excluded.to_status,
    requires_note=excluded.requires_note,sort_order=excluded.sort_order,
    active=true,actor=excluded.actor;
end;
$wf07_seed_receipt$;

revoke all on function private.workflow_wf07_seed_deposit_receipt_actions_v1(uuid)
  from public,anon,authenticated,service_role;

create or replace function private.workflow_wf07_seed_deposit_review_actions_v1(
  p_execution_id uuid
)
returns void
language plpgsql
security definer
set search_path=''
as $wf07_seed_review$
declare
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
begin
  select * into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id;

  if v_execution.id is null
    or v_execution.spec_snapshot->>'flowType'<>'deposit_review'
    or v_execution.spec_snapshot->>'eventType'<>'occupancy.offboarded'
    or v_execution.spec_snapshot->>'closeType'<>'domain_adapter'
    or v_execution.security_deposit_id is null then
    return;
  end if;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id;

  if v_task.id is null then
    raise exception 'workflow_wf07_task_missing' using errcode='55000';
  end if;

  insert into public.tenant_task_actions_v2(
    task_id,action_key,label,from_status,to_status,
    requires_note,sort_order,active,actor
  ) values
    (v_task.id,'start_review','Iniciar revisión','pending','active',false,10,true,'assignee'),
    (v_task.id,'start_review','Iniciar revisión','active','active',false,10,true,'assignee'),
    (v_task.id,'request_info','Solicitar información','active','waiting_info',true,20,true,'assignee'),
    (v_task.id,'open_damage_claim','Abrir reclamación por daños','active','active',true,30,true,'assignee'),
    (v_task.id,'refund','Devolver fianza','active','completed',true,50,true,'assignee'),
    (v_task.id,'partial_hold','Retener parcialmente','active','completed',true,60,true,'assignee'),
    (v_task.id,'hold','Retener fianza','active','completed',true,70,true,'assignee'),
    (v_task.id,'continue','Registrar información y continuar','waiting_info','active',true,40,true,'assignee')
  on conflict(task_id,action_key,from_status)
  do update set
    label=excluded.label,to_status=excluded.to_status,
    requires_note=excluded.requires_note,sort_order=excluded.sort_order,
    active=true,actor=excluded.actor;
end;
$wf07_seed_review$;

revoke all on function private.workflow_wf07_seed_deposit_review_actions_v1(uuid)
  from public,anon,authenticated,service_role;

create or replace function private.workflow_wf07_seed_damage_actions_v1(
  p_execution_id uuid
)
returns void
language plpgsql
security definer
set search_path=''
as $wf07_seed_damage$
declare
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
begin
  select * into v_execution
  from public.workflow_executions_v2
  where id=p_execution_id;

  if v_execution.id is null
    or v_execution.spec_snapshot->>'flowType'<>'damage_claim'
    or v_execution.spec_snapshot->>'eventType'<>'damage_claim.created'
    or v_execution.spec_snapshot->>'closeType'<>'domain_adapter'
    or v_execution.damage_claim_id is null
    or v_execution.security_deposit_id is null then
    return;
  end if;

  select * into v_task
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=v_execution.id;

  if v_task.id is null then
    raise exception 'workflow_wf07_task_missing' using errcode='55000';
  end if;

  insert into public.tenant_task_actions_v2(
    task_id,action_key,label,from_status,to_status,
    requires_note,sort_order,active,actor
  ) values
    (v_task.id,'notify','Notificar reclamación','pending','active',false,10,true,'assignee'),
    (v_task.id,'notify','Notificar reclamación','active','active',false,10,true,'assignee'),
    (v_task.id,'record_acceptance','Registrar aceptación','active','active',true,20,true,'assignee'),
    (v_task.id,'record_dispute','Registrar disputa','active','active',true,30,true,'assignee'),
    (v_task.id,'request_info','Solicitar información','active','waiting_info',true,40,true,'assignee'),
    (v_task.id,'resolve','Resolver','active','completed',true,60,false,'assignee'),
    (v_task.id,'continue','Registrar información y continuar','waiting_info','active',true,40,true,'assignee')
  on conflict(task_id,action_key,from_status)
  do update set
    label=excluded.label,to_status=excluded.to_status,
    requires_note=excluded.requires_note,sort_order=excluded.sort_order,
    active=excluded.active,actor=excluded.actor;
end;
$wf07_seed_damage$;

revoke all on function private.workflow_wf07_seed_damage_actions_v1(uuid)
  from public,anon,authenticated,service_role;

-- Extiende el resolver para personal interno en scope=occupancy de recepción.
alter function private.workflow_resolve_execution_assignee_v1(uuid,uuid)
  rename to workflow_resolve_execution_assignee_pre_wf07_v1;
revoke all on function private.workflow_resolve_execution_assignee_pre_wf07_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

create function private.workflow_resolve_execution_assignee_v1(
  p_application_id uuid,
  p_requested_user_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path=''
as $wf07_resolve$
declare
  v_org uuid;
  v_property uuid;
  v_scope text;
  v_spec jsonb;
  v_flow text;
  v_assignment text;
  v_role text;
  v_user uuid;
begin
  select a.organization_id,a.property_id,a.scope_type,wv.spec
  into v_org,v_property,v_scope,v_spec
  from public.workflow_applications_v2 a
  join public.workflow_definition_versions_v2 wv
    on wv.id=a.definition_version_id
   and wv.definition_id=a.definition_id
   and wv.organization_id=a.organization_id
  where a.id=p_application_id;

  v_flow:=coalesce(v_spec->>'flowType','');
  v_assignment:=coalesce(v_spec->>'assignmentType','');

  if v_flow='deposit_receipt'
    and v_spec->>'closeType'='domain_adapter' then
    if v_scope<>'occupancy' then
      raise exception 'workflow_wf07_deposit_receipt_scope_required'
        using errcode='22023';
    end if;
    if p_requested_user_id is not null then
      raise exception 'workflow_assignee_must_be_server_resolved'
        using errcode='22023';
    end if;

    if v_assignment='property_responsible' then
      -- El resolver anterior no admite personal interno sobre occupancy.
      select a.employee_user_id
      into v_user
      from public.property_staff_access_v3 a
      join public.user_roles ur
        on ur.user_id=a.employee_user_id
       and ur.organization_id=v_org
       and ur.role in ('admin','employee')
       and ur.revoked_at is null
      where a.organization_id=v_org
        and a.property_id=v_property
        and a.assignment_type='responsible'
        and a.can_write=true
        and a.revoked_at is null
        and a.valid_from<=now()
        and (a.valid_until is null or a.valid_until>now())
      order by a.employee_user_id
      limit 1;
    elsif v_assignment='fixed_person' then
      begin
        v_user:=(v_spec->>'assignmentUserId')::uuid;
      exception when others then
        raise exception 'workflow_fixed_person_invalid' using errcode='22023';
      end;
    elsif v_assignment='role' then
      v_role:=coalesce(v_spec->>'assignmentRole','');
      if v_role not in ('admin','employee') then
        raise exception 'workflow_assignment_role_invalid' using errcode='22023';
      end if;
      select ur.user_id
      into v_user
      from public.user_roles ur
      where ur.organization_id=v_org
        and ur.role::text=v_role
        and ur.revoked_at is null
        and private.wf06_internal_access_v1(v_org,v_property,ur.user_id,true)
      order by (
        select count(*)
        from public.workflow_executions_v2 e
        where e.application_id=p_application_id
          and e.assigned_user_id=ur.user_id
      ),ur.user_id
      limit 1;
    else
      raise exception 'workflow_wf07_assignment_invalid' using errcode='22023';
    end if;

    if v_user is null
      or not private.wf06_internal_access_v1(v_org,v_property,v_user,true) then
      raise exception 'workflow_wf07_assignee_not_eligible' using errcode='42501';
    end if;
    if v_assignment='fixed_person' and not exists(
      select 1 from public.user_roles ur
      where ur.user_id=v_user
        and ur.organization_id=v_org
        and ur.role in ('admin','employee')
        and ur.revoked_at is null
    ) then
      raise exception 'workflow_wf07_assignee_not_eligible' using errcode='42501';
    end if;
    return v_user;
  end if;

  if v_flow in ('deposit_review','damage_claim')
    and v_spec->>'closeType'='domain_adapter' then
    v_user:=private.workflow_resolve_execution_assignee_pre_wf07_v1(
      p_application_id,p_requested_user_id
    );
    if v_user is null
      or not private.wf06_internal_access_v1(v_org,v_property,v_user,true) then
      raise exception 'workflow_wf07_assignee_not_eligible' using errcode='42501';
    end if;
    return v_user;
  end if;

  return private.workflow_resolve_execution_assignee_pre_wf07_v1(
    p_application_id,p_requested_user_id
  );
end;
$wf07_resolve$;

revoke all on function private.workflow_resolve_execution_assignee_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

alter function private.workflow_execute_application_internal_v1(
  uuid,text,uuid,text,uuid
) rename to workflow_execute_application_pre_wf07_internal_v1;
revoke all on function private.workflow_execute_application_pre_wf07_internal_v1(
  uuid,text,uuid,text,uuid
) from public,anon,authenticated,service_role;

create function private.workflow_execute_application_internal_v1(
  p_application_id uuid,
  p_idempotency_key text,
  p_assigned_user_id uuid,
  p_trigger_kind text,
  p_actor_user_id uuid
)
returns table(
  execution_id uuid,
  status text,
  assigned_user_id uuid,
  created_at timestamptz,
  created_new boolean
)
language plpgsql
security definer
set search_path=''
as $wf07_execute$
declare
  v_scope text;
  v_property uuid;
  v_room uuid;
  v_app_occupancy uuid;
  v_spec jsonb;
  v_result record;
  v_execution public.workflow_executions_v2;
  v_task public.tenant_tasks_v2;
  v_occupancy public.occupancies_v2;
  v_tenant public.tenants_v2;
  v_deposit public.security_deposits_v2;
  v_claim public.claims_v2;
  v_event public.workflow_event_outbox_v2;
  v_previous_event uuid;
  v_previous_claim uuid;
  v_amount bigint;
  v_currency text;
begin
  select a.scope_type,a.property_id,a.room_id,a.occupancy_id,wv.spec
  into v_scope,v_property,v_room,v_app_occupancy,v_spec
  from public.workflow_applications_v2 a
  join public.workflow_definition_versions_v2 wv
    on wv.id=a.definition_version_id
   and wv.definition_id=a.definition_id
   and wv.organization_id=a.organization_id
  where a.id=p_application_id;

  if v_spec->>'flowType'='deposit_receipt'
    and v_spec->>'closeType'='domain_adapter' then
    if p_trigger_kind<>'manual_now'
      or v_scope<>'occupancy'
      or v_app_occupancy is null then
      raise exception 'workflow_wf07_deposit_receipt_trigger_invalid'
        using errcode='22023';
    end if;

    select * into v_result
    from private.workflow_execute_application_pre_wf07_internal_v1(
      p_application_id,p_idempotency_key,p_assigned_user_id,
      p_trigger_kind,p_actor_user_id
    );

    select * into v_execution
    from public.workflow_executions_v2
    where id=v_result.execution_id
    for update;

    if v_execution.security_deposit_id is null then
      select o.* into v_occupancy
      from public.occupancies_v2 o
      where o.id=v_execution.occupancy_id
        and o.organization_id=v_execution.organization_id
        and o.property_id=v_execution.property_id
        and o.status='active'
        and o.starts_on<=current_date
        and (o.ends_on is null or o.ends_on>=current_date)
      for share;

      if v_occupancy.id is null or v_occupancy.user_id is null then
        raise exception 'workflow_wf07_occupancy_not_current' using errcode='55000';
      end if;

      select t.* into v_tenant
      from public.tenants_v2 t
      where t.id=v_occupancy.tenant_id
        and t.organization_id=v_execution.organization_id
        and t.user_id=v_occupancy.user_id
        and t.status='active'
        and t.archived_at is null;

      if v_tenant.id is null then
        raise exception 'workflow_wf07_tenant_not_current' using errcode='55000';
      end if;

      if exists(
        select 1 from public.security_deposits_v2 d
        where d.occupancy_id=v_occupancy.id
      ) then
        raise exception 'workflow_wf07_deposit_already_exists' using errcode='55000';
      end if;

      v_amount:=(v_execution.spec_snapshot->>'depositAmountCents')::bigint;
      v_currency:=v_execution.spec_snapshot->>'depositCurrency';

      insert into public.security_deposits_v2(
        organization_id,property_id,room_id,occupancy_id,tenant_user_id,
        amount_cents,currency,status,created_by
      ) values (
        v_execution.organization_id,v_execution.property_id,v_occupancy.room_id,
        v_occupancy.id,v_occupancy.user_id,
        v_amount,v_currency,'pending',
        coalesce(p_actor_user_id,v_execution.created_by)
      )
      returning * into v_deposit;

      update public.workflow_executions_v2
      set security_deposit_id=v_deposit.id,
          updated_at=clock_timestamp()
      where id=v_execution.id
      returning * into v_execution;

      select * into v_task
      from public.tenant_tasks_v2
      where source_kind='workflow_execution'
        and source_id=v_execution.id
      for update;

      if v_task.id is null
        or v_task.tenant_id is distinct from v_occupancy.tenant_id
        or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
        raise exception 'workflow_wf07_task_identity_mismatch' using errcode='55000';
      end if;

      update public.tenant_tasks_v2
      set title='Fianza · recepción',
          description=concat(
            trim(to_char(v_deposit.amount_cents/100.0,'FM9999999990D00')),
            ' ',v_deposit.currency,' · ',v_tenant.full_name
          ),
          updated_at=clock_timestamp()
      where id=v_task.id
      returning * into v_task;

      perform private.workflow_wf07_seed_deposit_receipt_actions_v1(v_execution.id);

      insert into public.workflow_execution_events_v2(
        execution_id,organization_id,event_type,from_status,to_status,
        actor_user_id,details
      ) values (
        v_execution.id,v_execution.organization_id,'wf07_deposit_bound',
        v_execution.status,v_execution.status,
        coalesce(p_actor_user_id,v_execution.created_by),
        jsonb_build_object(
          'security_deposit_id',v_deposit.id,
          'occupancy_id',v_occupancy.id,
          'amount_cents',v_deposit.amount_cents,
          'currency',v_deposit.currency
        )
      );
    else
      select * into v_deposit
      from public.security_deposits_v2
      where id=v_execution.security_deposit_id;
      if v_deposit.id is null
        or v_deposit.occupancy_id is distinct from v_execution.occupancy_id then
        raise exception 'workflow_wf07_deposit_source_conflict' using errcode='55000';
      end if;
      perform private.workflow_wf07_seed_deposit_receipt_actions_v1(v_execution.id);
    end if;

    return query select
      v_result.execution_id::uuid,v_result.status::text,
      v_result.assigned_user_id::uuid,v_result.created_at::timestamptz,
      v_result.created_new::boolean;
    return;
  end if;

  if p_trigger_kind='event' then
    select * into v_event
    from public.workflow_event_outbox_v2
    where id=substring(
      p_idempotency_key from
      '^event:([0-9a-fA-F-]{36})$'
    )::uuid;

    if v_event.id is not null
      and v_event.source_kind='occupancy'
      and v_event.event_type='occupancy.offboarded'
      and v_spec->>'flowType'='deposit_review' then

      if v_spec->>'closeType'<>'domain_adapter'
        or v_scope not in ('property','room')
        or v_property is distinct from v_event.property_id
        or (v_scope='room' and v_room is distinct from v_event.room_id) then
        raise exception 'workflow_event_destination_mismatch' using errcode='42501';
      end if;

      select o.* into v_occupancy
      from public.occupancies_v2 o
      where o.id=v_event.occupancy_id
        and o.organization_id=v_event.organization_id
        and o.property_id=v_event.property_id
        and o.status='archived';

      if v_occupancy.id is null
        or v_occupancy.user_id is null
        or v_occupancy.tenant_id is null then
        raise exception 'workflow_wf07_deposit_review_subject_invalid'
          using errcode='55000';
      end if;

      select * into v_deposit
      from public.security_deposits_v2
      where occupancy_id=v_occupancy.id
        and organization_id=v_occupancy.organization_id
        and property_id=v_occupancy.property_id;

      if v_deposit.id is null then
        raise exception 'workflow_domain_lifecycle_mismatch' using errcode='55000';
      end if;
      if v_deposit.status<>'received' then
        raise exception 'workflow_domain_lifecycle_mismatch' using errcode='55000';
      end if;

      select * into v_result
      from private.workflow_execute_application_pre_wf07_internal_v1(
        p_application_id,p_idempotency_key,p_assigned_user_id,
        p_trigger_kind,p_actor_user_id
      );

      update public.workflow_executions_v2
      set security_deposit_id=coalesce(security_deposit_id,v_deposit.id),
          updated_at=clock_timestamp()
      where id=v_result.execution_id
      returning * into v_execution;

      select * into v_task
      from public.tenant_tasks_v2
      where source_kind='workflow_execution'
        and source_id=v_execution.id
      for update;

      if v_task.id is null
        or v_task.tenant_id is distinct from v_occupancy.tenant_id
        or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
        raise exception 'workflow_wf07_review_task_identity_mismatch'
          using errcode='55000';
      end if;

      update public.tenant_tasks_v2
      set title='Fianza · revisión',
          description=concat(
            trim(to_char(v_deposit.amount_cents/100.0,'FM9999999990D00')),
            ' ',v_deposit.currency,' · salida confirmada'
          ),
          updated_at=clock_timestamp()
      where id=v_task.id;

      perform private.workflow_wf07_seed_deposit_review_actions_v1(v_execution.id);

      return query select
        v_result.execution_id::uuid,v_result.status::text,
        v_result.assigned_user_id::uuid,v_result.created_at::timestamptz,
        v_result.created_new::boolean;
      return;
    end if;

    if v_event.id is not null
      and v_event.source_kind='damage_claim'
      and v_event.event_type='damage_claim.created'
      and v_spec->>'flowType'='damage_claim' then

      if v_spec->>'closeType'<>'domain_adapter'
        or v_scope not in ('property','room')
        or v_property is distinct from v_event.property_id
        or (v_scope='room' and v_room is distinct from v_event.room_id) then
        raise exception 'workflow_event_destination_mismatch' using errcode='42501';
      end if;

      select c.* into v_claim
      from public.claims_v2 c
      where c.id=v_event.source_id
        and c.claim_type='damage'
        and c.status='draft';

      if v_claim.id is null
        or v_claim.organization_id is distinct from v_event.organization_id
        or v_claim.property_id is distinct from v_event.property_id
        or v_claim.occupancy_id is distinct from v_event.occupancy_id
        or v_claim.security_deposit_id is null then
        raise exception 'workflow_wf07_damage_subject_mismatch' using errcode='55000';
      end if;

      select * into v_deposit
      from public.security_deposits_v2
      where id=v_claim.security_deposit_id;

      if v_deposit.id is null
        or v_deposit.occupancy_id is distinct from v_claim.occupancy_id
        or v_deposit.tenant_user_id is distinct from v_claim.tenant_user_id
        or v_deposit.status not in ('under_review','waiting_info') then
        raise exception 'workflow_wf07_damage_deposit_mismatch' using errcode='55000';
      end if;

      select * into v_result
      from private.workflow_execute_application_wf02_internal_v1(
        p_application_id,p_idempotency_key,p_assigned_user_id,
        p_trigger_kind,p_actor_user_id
      );

      select e.source_event_id,e.damage_claim_id
      into v_previous_event,v_previous_claim
      from public.workflow_executions_v2 e
      where e.id=v_result.execution_id
      for update;

      if (v_previous_event is not null and v_previous_event<>v_event.id)
        or (v_previous_claim is not null and v_previous_claim<>v_claim.id) then
        raise exception 'workflow_wf07_damage_source_conflict' using errcode='55000';
      end if;

      update public.workflow_executions_v2
      set source_event_id=coalesce(source_event_id,v_event.id),
          damage_claim_id=coalesce(damage_claim_id,v_claim.id),
          security_deposit_id=coalesce(security_deposit_id,v_deposit.id),
          updated_at=clock_timestamp()
      where id=v_result.execution_id
      returning * into v_execution;

      select * into v_occupancy
      from public.occupancies_v2
      where id=v_claim.occupancy_id;

      select * into v_task
      from public.tenant_tasks_v2
      where source_kind='workflow_execution'
        and source_id=v_execution.id
      for update;

      if v_task.id is null
        or v_occupancy.id is null
        or v_occupancy.user_id is distinct from v_claim.tenant_user_id
        or v_task.assigned_user_id is distinct from v_execution.assigned_user_id then
        raise exception 'workflow_wf07_damage_task_identity_mismatch'
          using errcode='55000';
      end if;

      update public.tenant_tasks_v2
      set tenant_id=v_occupancy.tenant_id,
          title='Daños · reclamación',
          description=concat(
            v_claim.body,' · ',
            trim(to_char(v_claim.claimed_amount_cents/100.0,'FM9999999990D00')),
            ' ',v_claim.currency
          ),
          updated_at=clock_timestamp()
      where id=v_task.id;

      perform private.workflow_wf07_seed_damage_actions_v1(v_execution.id);

      if v_previous_event is null then
        insert into public.workflow_execution_events_v2(
          execution_id,organization_id,event_type,from_status,to_status,
          actor_user_id,details
        ) values (
          v_execution.id,v_execution.organization_id,'wf07_damage_bound',
          v_execution.status,v_execution.status,p_actor_user_id,
          jsonb_build_object(
            'source_event_id',v_event.id,
            'damage_claim_id',v_claim.id,
            'security_deposit_id',v_deposit.id
          )
        );
      end if;

      return query select
        v_result.execution_id::uuid,v_result.status::text,
        v_result.assigned_user_id::uuid,v_result.created_at::timestamptz,
        v_result.created_new::boolean;
      return;
    end if;
  end if;

  return query
  select *
  from private.workflow_execute_application_pre_wf07_internal_v1(
    p_application_id,p_idempotency_key,p_assigned_user_id,
    p_trigger_kind,p_actor_user_id
  );
end;
$wf07_execute$;

revoke all on function private.workflow_execute_application_internal_v1(
  uuid,text,uuid,text,uuid
) from public,anon,authenticated,service_role;
