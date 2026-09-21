-- WF-06 · Pago de alquiler + Reclamación sobre workflow transversal.
begin;

select set_config('wf06.org','11111111-1111-4111-8111-111111111111',true);
select set_config('wf06.root','22222222-2222-4222-8222-222222222222',true);
select set_config('wf06.owner_user',gen_random_uuid()::text,true);
select set_config('wf06.owner',gen_random_uuid()::text,true);
select set_config('wf06.property',gen_random_uuid()::text,true);
select set_config('wf06.room',gen_random_uuid()::text,true);
select set_config('wf06.staff',gen_random_uuid()::text,true);
select set_config('wf06.admin',gen_random_uuid()::text,true);
select set_config('wf06.tenant_user',gen_random_uuid()::text,true);
select set_config('wf06.tenant',gen_random_uuid()::text,true);
select set_config('wf06.occupancy',gen_random_uuid()::text,true);

insert into auth.users(id) values
  (current_setting('wf06.owner_user')::uuid),
  (current_setting('wf06.staff')::uuid),
  (current_setting('wf06.admin')::uuid),
  (current_setting('wf06.tenant_user')::uuid);

insert into public.profiles(user_id,organization_id,display_name,status) values
  (current_setting('wf06.owner_user')::uuid,current_setting('wf06.org')::uuid,'WF06 owner','active'),
  (current_setting('wf06.staff')::uuid,current_setting('wf06.org')::uuid,'WF06 responsible','active'),
  (current_setting('wf06.admin')::uuid,current_setting('wf06.org')::uuid,'WF06 admin','active');

insert into public.profiles(user_id,organization_id,display_name,status)
values (
  current_setting('wf06.root')::uuid,current_setting('wf06.org')::uuid,
  'WF06 ROOT','active'
)
on conflict(user_id) do update
set organization_id=excluded.organization_id,status='active',archived_at=null;

insert into public.user_roles(user_id,organization_id,role) values
  (current_setting('wf06.owner_user')::uuid,current_setting('wf06.org')::uuid,'owner'),
  (current_setting('wf06.staff')::uuid,current_setting('wf06.org')::uuid,'employee'),
  (current_setting('wf06.admin')::uuid,current_setting('wf06.org')::uuid,'admin'),
  (current_setting('wf06.tenant_user')::uuid,current_setting('wf06.org')::uuid,'tenant');

insert into public.owners(id,organization_id,user_id,full_name,status)
values(
  current_setting('wf06.owner')::uuid,current_setting('wf06.org')::uuid,
  current_setting('wf06.owner_user')::uuid,'WF06 owner','active'
);

insert into public.properties_v2(
  id,organization_id,owner_id,name,address_line,status
) values (
  current_setting('wf06.property')::uuid,current_setting('wf06.org')::uuid,
  current_setting('wf06.owner')::uuid,'WF06 property','Regression','active'
);

insert into public.rooms_v2(id,property_id,label,status)
values(
  current_setting('wf06.room')::uuid,current_setting('wf06.property')::uuid,
  'WF06 room','active'
);

insert into public.property_staff_access_v3(
  organization_id,property_id,employee_user_id,assignment_type,can_write,granted_by
) values (
  current_setting('wf06.org')::uuid,current_setting('wf06.property')::uuid,
  current_setting('wf06.staff')::uuid,'responsible',true,current_setting('wf06.root')::uuid
);

insert into public.tenants_v2(
  id,organization_id,user_id,full_name,document_type,document_number,email,status
) values (
  current_setting('wf06.tenant')::uuid,current_setting('wf06.org')::uuid,
  current_setting('wf06.tenant_user')::uuid,'WF06 tenant','other','WF06-TENANT',
  'wf06-tenant@example.invalid','active'
);

insert into public.occupancies_v2(
  id,organization_id,tenant_id,property_id,room_id,occupant_email,
  starts_on,ends_on,status,user_id
) values (
  current_setting('wf06.occupancy')::uuid,current_setting('wf06.org')::uuid,
  current_setting('wf06.tenant')::uuid,current_setting('wf06.property')::uuid,
  current_setting('wf06.room')::uuid,'wf06-tenant@example.invalid',
  current_date-1,null,'active',current_setting('wf06.tenant_user')::uuid
);

create function pg_temp.wf06_payment_spec(
  p_assignment text default 'property_responsible'
)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'authoringVersion',2,
    'flowName',case when p_assignment='role' then 'WF06 pago admin' else 'WF06 pago alquiler' end,
    'flowType','rent_payment',
    'flowDescription','WF06 regression only',
    'scopeType','occupancy',
    'triggerType','manual',
    'eventType','',
    'recurrence','','scheduledAt','','scheduledTimezone','','scheduledAtUtc','',
    'customEvery','','customUnit','',
    'assignmentType',p_assignment,
    'assignmentUserId','',
    'assignmentRole',case when p_assignment='role' then 'admin' else '' end,
    'paymentConcept','Alquiler septiembre',
    'paymentAmountCents',85000,
    'paymentCurrency','EUR',
    'paymentDueDays',0,
    'steps',jsonb_build_object(
      'accept',true,'photo',false,'checklist',false,'document',false
    ),
    'checklistItems','[]'::jsonb,
    'closeType','domain_adapter',
    'notifications',jsonb_build_object('onCreate',false,'onClose',true)
  );
$$;

create function pg_temp.wf06_claim_spec()
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'authoringVersion',2,
    'flowName','WF06 reclamación alquiler',
    'flowType','rent_claim',
    'flowDescription','WF06 regression only',
    'scopeType','property',
    'triggerType','event',
    'eventType','rent_claim.created',
    'recurrence','','scheduledAt','','scheduledTimezone','','scheduledAtUtc','',
    'customEvery','','customUnit','',
    'assignmentType','property_responsible',
    'assignmentUserId','','assignmentRole','',
    'steps',jsonb_build_object(
      'accept',true,'photo',false,'checklist',false,'document',false
    ),
    'checklistItems','[]'::jsonb,
    'closeType','domain_adapter',
    'notifications',jsonb_build_object('onCreate',false,'onClose',true)
  );
$$;

do $authoring_contract$
begin
  if not public.workflow_authoring_complete_v1(pg_temp.wf06_payment_spec()) then
    raise exception 'WF06 rejected valid rent payment authoring';
  end if;
  if not public.workflow_authoring_complete_v1(pg_temp.wf06_claim_spec()) then
    raise exception 'WF06 rejected valid rent claim authoring';
  end if;
  if public.workflow_authoring_complete_v1(
    pg_temp.wf06_payment_spec() || jsonb_build_object('scopeType','property')
  ) then
    raise exception 'WF06 accepted rent payment without exact occupancy scope';
  end if;
  if public.workflow_authoring_complete_v1(
    pg_temp.wf06_claim_spec() || jsonb_build_object('triggerType','manual','eventType','')
  ) then
    raise exception 'WF06 accepted rent claim without event trigger';
  end if;
  if public.workflow_authoring_complete_v1(
    pg_temp.wf06_payment_spec() || jsonb_build_object('paymentAmountCents',0)
  ) then
    raise exception 'WF06 accepted zero rent amount';
  end if;
end;
$authoring_contract$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.root'),'role','authenticated','aal','aal2'
)::text,true);

select set_config('wf06.claim_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf06_claim_spec(),
    current_setting('wf06.property')::uuid,
    null,null,'{}'::uuid[],false,
    'wf06-claim-ready',null,null
  ) limit 1
),true);

do $claim_single_manager$
begin
  begin
    perform *
    from public.publish_workflow_ready_v1(
      pg_temp.wf06_claim_spec() || jsonb_build_object(
        'flowName','WF06 reclamación duplicada'
      ),
      current_setting('wf06.property')::uuid,
      null,null,'{}'::uuid[],false,
      'wf06-claim-duplicate',null,null
    );
    raise exception 'WF06 allowed overlapping rent claim managers';
  exception when sqlstate '55000' then
    if sqlerrm<>'workflow_wf06_claim_application_conflict' then
      raise;
    end if;
  end;
end;
$claim_single_manager$;

select set_config('wf06.payment_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf06_payment_spec(),
    current_setting('wf06.property')::uuid,
    null,current_setting('wf06.occupancy')::uuid,
    '{}'
      ::uuid[],false,'wf06-payment-ready',null,null
  ) limit 1
),true);

select set_config('wf06.admin_payment_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf06_payment_spec('role'),
    current_setting('wf06.property')::uuid,
    null,current_setting('wf06.occupancy')::uuid,
    '{}'
      ::uuid[],false,'wf06-payment-admin-ready',null,null
  ) limit 1
),true);

select set_config('wf06.payment_execution_1',(
  select execution_id::text
  from public.execute_workflow_application_now_v1(
    current_setting('wf06.payment_app')::uuid,
    'wf06-payment-exec-1',null
  ) limit 1
),true);

select set_config('wf06.payment_execution_2',(
  select execution_id::text
  from public.execute_workflow_application_now_v1(
    current_setting('wf06.payment_app')::uuid,
    'wf06-payment-exec-2',null
  ) limit 1
),true);

select set_config('wf06.admin_payment_execution',(
  select execution_id::text
  from public.execute_workflow_application_now_v1(
    current_setting('wf06.admin_payment_app')::uuid,
    'wf06-payment-admin-exec',null
  ) limit 1
),true);
reset role;

select set_config('wf06.payment_task_1',(
  select id::text from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf06.payment_execution_1')::uuid
),true);
select set_config('wf06.payment_task_2',(
  select id::text from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf06.payment_execution_2')::uuid
),true);
select set_config('wf06.admin_payment_task',(
  select id::text from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf06.admin_payment_execution')::uuid
),true);

do $payment_binding$
begin
  if (
    select count(*)
    from public.workflow_executions_v2 e
    join public.payment_obligations_v2 o on o.id=e.payment_obligation_id
    join public.tenant_tasks_v2 t
      on t.source_kind='workflow_execution' and t.source_id=e.id
    where e.id in (
      current_setting('wf06.payment_execution_1')::uuid,
      current_setting('wf06.payment_execution_2')::uuid
    )
      and e.scope_type='occupancy'
      and e.occupancy_id=current_setting('wf06.occupancy')::uuid
      and e.assigned_user_id=current_setting('wf06.staff')::uuid
      and o.occupancy_id=e.occupancy_id
      and o.tenant_user_id=current_setting('wf06.tenant_user')::uuid
      and o.amount_cents=85000
      and o.currency='EUR'
      and o.status='pending'
      and t.tenant_id=current_setting('wf06.tenant')::uuid
      and t.assigned_user_id=e.assigned_user_id
  )<>2 then
    raise exception 'WF06 payment execution did not bind canonical obligations/tasks';
  end if;
  if (
    select count(distinct payment_obligation_id)
    from public.workflow_executions_v2
    where id in (
      current_setting('wf06.payment_execution_1')::uuid,
      current_setting('wf06.payment_execution_2')::uuid
    )
  )<>2 then
    raise exception 'WF06 reused one obligation across executions';
  end if;
end;
$payment_binding$;

-- ADMIN financiero exige AAL2.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.admin'),'role','authenticated','aal','aal1'
)::text,true);
do $admin_mfa_required$
begin
  begin
    perform *
    from public.apply_workflow_task_action_v1(
      current_setting('wf06.admin_payment_task')::uuid,
      'request_payment','wf06-admin-aal1',null
    );
    raise exception 'WF06 admin financial mutation succeeded without AAL2';
  exception when sqlstate '42501' then
    if sqlerrm<>'workflow_wf06_mfa_required' then
      raise;
    end if;
  end;
end;
$admin_mfa_required$;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.admin'),'role','authenticated','aal','aal2'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.admin_payment_task')::uuid,
  'request_payment','wf06-admin-aal2',null
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.admin_payment_task')::uuid,
  'register_payment','wf06-admin-paid',null
);
reset role;

-- Primer pago: solicitar -> aplazar -> registrar; el mismo request_key no duplica.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.staff'),'role','authenticated','aal','aal1'
)::text,true);

select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.payment_task_1')::uuid,
  'request_payment','wf06-request-1',null
);

select * from public.apply_wf06_payment_action_v1(
  current_setting('wf06.payment_task_1')::uuid,
  'postpone','wf06-postpone-1','Aplazamiento acordado',current_date+7
);

do $postpone_idempotent$
declare v_result record;
begin
  select * into v_result
  from public.apply_wf06_payment_action_v1(
    current_setting('wf06.payment_task_1')::uuid,
    'postpone','wf06-postpone-1','Aplazamiento acordado',current_date+7
  );
  if v_result.applied_new then
    raise exception 'WF06 duplicated postpone with same request key';
  end if;
end;
$postpone_idempotent$;

select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.payment_task_1')::uuid,
  'register_payment','wf06-paid-1',null
);
reset role;

do $payment_completed$
begin
  if not exists(
    select 1
    from public.workflow_executions_v2 e
    join public.payment_obligations_v2 o on o.id=e.payment_obligation_id
    join public.tenant_tasks_v2 t
      on t.source_kind='workflow_execution' and t.source_id=e.id
    where e.id=current_setting('wf06.payment_execution_1')::uuid
      and e.status='completed'
      and t.status='completed'
      and o.status='paid'
      and o.paid_at is not null
      and o.due_date=current_date+7
  ) then
    raise exception 'WF06 payment lifecycle did not complete atomically';
  end if;
  if (
    select count(*) from public.workflow_execution_events_v2
    where execution_id=current_setting('wf06.payment_execution_1')::uuid
      and event_type='wf06_payment_action'
      and details->>'request_key'='wf06-postpone-1'
  )<>1 then
    raise exception 'WF06 postpone history is not idempotent';
  end if;
end;
$payment_completed$;

-- Segundo pago: escalar a reclamación. Debe existir el flujo claim antes del evento.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.staff'),'role','authenticated','aal','aal1'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.payment_task_2')::uuid,
  'claim','wf06-claim-payment','Impago vencido'
);
reset role;

select set_config('wf06.claim',(
  select c.id::text
  from public.claims_v2 c
  join public.workflow_executions_v2 e
    on e.payment_obligation_id=c.obligation_id
  where e.id=current_setting('wf06.payment_execution_2')::uuid
    and c.claim_type='payment'
),true);

do $claim_created_once$
begin
  if (
    select count(*) from public.claims_v2
    where id=current_setting('wf06.claim')::uuid
      and status='draft'
      and tenant_decision is null
      and occupancy_id=current_setting('wf06.occupancy')::uuid
      and tenant_user_id=current_setting('wf06.tenant_user')::uuid
  )<>1 then
    raise exception 'WF06 claim dossier was not created once';
  end if;
  if (
    select count(*) from public.workflow_event_outbox_v2
    where event_type='rent_claim.created'
      and source_kind='rent_claim'
      and source_id=current_setting('wf06.claim')::uuid
      and event_key='created'
      and status='pending'
  )<>1 then
    raise exception 'WF06 claim event was not enqueued once';
  end if;
  if not exists(
    select 1
    from public.workflow_executions_v2 e
    join public.payment_obligations_v2 o on o.id=e.payment_obligation_id
    where e.id=current_setting('wf06.payment_execution_2')::uuid
      and e.status='completed'
      and o.status='overdue'
  ) then
    raise exception 'WF06 payment escalation did not close payment execution as overdue';
  end if;
end;
$claim_created_once$;

select private.process_pending_workflow_events_v1(50);
select private.process_pending_workflow_events_v1(50);

do $claim_dispatch_diagnostic$
declare
  v_status text;
  v_error_code text;
  v_error_key text;
begin
  select d.status,d.error_code,d.error_key
  into v_status,v_error_code,v_error_key
  from public.workflow_event_dispatches_v2 d
  join public.workflow_event_outbox_v2 e on e.id=d.event_id
  where e.event_type='rent_claim.created'
    and e.source_kind='rent_claim'
    and e.source_id=current_setting('wf06.claim')::uuid
    and d.application_id=current_setting('wf06.claim_app')::uuid;

  if v_status is distinct from 'executed' then
    raise exception 'WF06 rent claim dispatch failed: status=%, code=%, key=%',
      coalesce(v_status,'missing'),
      coalesce(v_error_code,'null'),
      coalesce(v_error_key,'null');
  end if;
end;
$claim_dispatch_diagnostic$;

select set_config('wf06.claim_execution',(
  select id::text
  from public.workflow_executions_v2
  where application_id=current_setting('wf06.claim_app')::uuid
    and rent_claim_id=current_setting('wf06.claim')::uuid
),true);
select set_config('wf06.claim_task',(
  select id::text
  from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf06.claim_execution')::uuid
),true);

do $claim_dispatched_once$
begin
  if not exists(
    select 1
    from public.workflow_executions_v2 e
    join public.tenant_tasks_v2 t
      on t.source_kind='workflow_execution' and t.source_id=e.id
    where e.id=current_setting('wf06.claim_execution')::uuid
      and e.rent_claim_id=current_setting('wf06.claim')::uuid
      and e.payment_obligation_id is not null
      and e.source_event_id is not null
      and e.assigned_user_id=current_setting('wf06.staff')::uuid
      and t.id=current_setting('wf06.claim_task')::uuid
      and t.tenant_id=current_setting('wf06.tenant')::uuid
      and t.status='pending'
  ) then
    raise exception 'WF06 claim did not materialize one canonical shared card';
  end if;
  if (
    select count(*)
    from public.workflow_executions_v2 e
    join public.claims_v2 c
      on c.obligation_id=e.payment_obligation_id
    where c.id=current_setting('wf06.claim')::uuid
      and e.payment_obligation_id is not null
      and e.spec_snapshot->>'flowType' in ('rent_payment','rent_claim')
  )<>2 then
    raise exception 'WF06 payment and claim executions did not share one canonical obligation';
  end if;
  if exists(
    select 1 from public.tenant_task_actions_v2
    where task_id=current_setting('wf06.claim_task')::uuid
      and action_key='resolve'
      and from_status='active'
      and active=true
  ) then
    raise exception 'WF06 exposed resolve before tenant decision';
  end if;
end;
$claim_dispatched_once$;

-- Gestor notifica y solicita información.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.staff'),'role','authenticated','aal','aal1'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.claim_task')::uuid,
  'notify','wf06-notify-claim',null
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.claim_task')::uuid,
  'request_info','wf06-request-info','Aporta justificante o explicación'
);
reset role;

-- El inquilino exacto puede ver la tarjeta/acciones a través del gate RLS WF-06.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.tenant_user'),'role','authenticated','aal','aal1'
)::text,true);
do $tenant_shared_card$
begin
  if not public.has_current_platform_access_v1() then
    raise exception 'WF06 exact tenant failed current platform access gate';
  end if;
  if (
    select count(*) from public.tenants_v2
    where id=current_setting('wf06.tenant')::uuid
      and user_id=current_setting('wf06.tenant_user')::uuid
  )<>1 then
    raise exception 'WF06 exact tenant cannot read own tenant identity';
  end if;
  if not public.workflow_execution_actor_current_v1(
    current_setting('wf06.claim_execution')::uuid
  ) then
    raise exception 'WF06 exact tenant was not recognized by workflow actor gate';
  end if;
  if (
    select count(*) from public.tenant_tasks_v2
    where id=current_setting('wf06.claim_task')::uuid
  )<>1 then
    raise exception
      'WF06 exact tenant cannot read shared claim task: uid=%, platform=%, tenant_visible=%, actor_gate=%',
      auth.uid(),
      public.has_current_platform_access_v1(),
      (select count(*) from public.tenants_v2
       where id=current_setting('wf06.tenant')::uuid
         and user_id=auth.uid()),
      public.workflow_execution_actor_current_v1(
        current_setting('wf06.claim_execution')::uuid
      );
  end if;
  if (
    select count(*) from public.tenant_task_actions_v2
    where task_id=current_setting('wf06.claim_task')::uuid
      and action_key='provide_info'
      and from_status='waiting_info'
      and active=true
      and actor='tenant'
  )<>1 then
    raise exception 'WF06 exact tenant cannot read provide-info action';
  end if;
end;
$tenant_shared_card$;

select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.claim_task')::uuid,
  'provide_info','wf06-provide-info','Transferencia pendiente de conciliar'
);
reset role;

-- El gestor solo puede continuar después de una respuesta posterior a la petición.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.staff'),'role','authenticated','aal','aal1'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.claim_task')::uuid,
  'continue','wf06-continue',null
);
reset role;

-- Una respuesta vieja no puede satisfacer una petición nueva.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.staff'),'role','authenticated','aal','aal1'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.claim_task')::uuid,
  'request_info','wf06-request-info-2','Aporta justificante actualizado'
);
do $wf06_fresh_response_required$
begin
  begin
    perform *
    from public.apply_workflow_task_action_v1(
      current_setting('wf06.claim_task')::uuid,
      'continue','wf06-continue-too-early',null
    );
    raise exception 'WF06 accepted continue using a stale information response';
  exception
    when sqlstate '55000' then
      if position('workflow_wf06_information_response_required' in sqlerrm)=0 then
        raise;
      end if;
  end;
end;
$wf06_fresh_response_required$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.tenant_user'),'role','authenticated','aal','aal1'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.claim_task')::uuid,
  'provide_info','wf06-provide-info-2','Justificante actualizado aportado'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.staff'),'role','authenticated','aal','aal1'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.claim_task')::uuid,
  'continue','wf06-continue-2',null
);
reset role;

-- Decisión exacta del inquilino; activa Resolver y retira Aceptar/Disputar.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.tenant_user'),'role','authenticated','aal','aal1'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.claim_task')::uuid,
  'accept','wf06-tenant-accept',null
);
reset role;

do $decision_gates_resolve$
begin
  if (select tenant_decision from public.claims_v2
      where id=current_setting('wf06.claim')::uuid)<>'accepted' then
    raise exception 'WF06 tenant decision was not stored';
  end if;
  if not exists(
    select 1 from public.tenant_task_actions_v2
    where task_id=current_setting('wf06.claim_task')::uuid
      and action_key='resolve'
      and from_status='active'
      and active=true
      and actor='assignee'
  ) then
    raise exception 'WF06 did not activate resolve after tenant decision';
  end if;
  if exists(
    select 1 from public.tenant_task_actions_v2
    where task_id=current_setting('wf06.claim_task')::uuid
      and action_key in ('accept','dispute')
      and from_status='active'
      and active=true
  ) then
    raise exception 'WF06 kept tenant decision buttons active after deciding';
  end if;
end;
$decision_gates_resolve$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf06.staff'),'role','authenticated','aal','aal1'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf06.claim_task')::uuid,
  'resolve','wf06-resolve','Acuerdo registrado por la gestoría'
);
reset role;

do $claim_completed$
begin
  if not exists(
    select 1
    from public.claims_v2 c
    join public.workflow_executions_v2 e on e.rent_claim_id=c.id
    join public.tenant_tasks_v2 t
      on t.source_kind='workflow_execution' and t.source_id=e.id
    where c.id=current_setting('wf06.claim')::uuid
      and c.status='resolved'
      and c.resolved_at is not null
      and c.tenant_decision='accepted'
      and e.status='completed'
      and t.status='completed'
  ) then
    raise exception 'WF06 claim did not close dossier/task/execution together';
  end if;

  if (
    select count(*)
    from public.workflow_execution_events_v2
    where execution_id=current_setting('wf06.claim_execution')::uuid
      and event_type='wf06_claim_action'
  )<>9 then
    raise exception 'WF06 claim action history count is inconsistent';
  end if;

  if not exists(
    select 1 from public.notifications_v2
    where source_kind='rent_claim'
      and source_id=current_setting('wf06.claim')::uuid
      and event_key='notified'
      and recipient_user_id=current_setting('wf06.tenant_user')::uuid
  ) or not exists(
    select 1 from public.notifications_v2
    where source_kind='rent_claim'
      and source_id=current_setting('wf06.claim')::uuid
      and event_key='resolved'
      and recipient_user_id=current_setting('wf06.tenant_user')::uuid
  ) then
    raise exception 'WF06 claim notifications are incomplete';
  end if;

  if (
    select count(*)
    from public.audit_log_v2
    where entity_type='workflow_execution'
      and entity_id=current_setting('wf06.claim_execution')
      and action='workflow_wf06_claim_action'
  )<>9 then
    raise exception 'WF06 claim audit trail is incomplete';
  end if;
end;
$claim_completed$;

rollback;
