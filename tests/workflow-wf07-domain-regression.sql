-- WF-07 · Reclamo de daños + Fianza sobre workflow transversal.
begin;

select set_config('wf07.org','11111111-1111-4111-8111-111111111111',true);
select set_config('wf07.root','22222222-2222-4222-8222-222222222222',true);
select set_config('wf07.owner_user',gen_random_uuid()::text,true);
select set_config('wf07.owner',gen_random_uuid()::text,true);
select set_config('wf07.property',gen_random_uuid()::text,true);
select set_config('wf07.staff',gen_random_uuid()::text,true);

-- Tres fianzas reales + una Baja sin fianza para comprobar cola terminal.
select set_config('wf07.partial_user',gen_random_uuid()::text,true);
select set_config('wf07.partial_tenant',gen_random_uuid()::text,true);
select set_config('wf07.partial_room',gen_random_uuid()::text,true);
select set_config('wf07.partial_occupancy',gen_random_uuid()::text,true);

select set_config('wf07.refund_user',gen_random_uuid()::text,true);
select set_config('wf07.refund_tenant',gen_random_uuid()::text,true);
select set_config('wf07.refund_room',gen_random_uuid()::text,true);
select set_config('wf07.refund_occupancy',gen_random_uuid()::text,true);

select set_config('wf07.hold_user',gen_random_uuid()::text,true);
select set_config('wf07.hold_tenant',gen_random_uuid()::text,true);
select set_config('wf07.hold_room',gen_random_uuid()::text,true);
select set_config('wf07.hold_occupancy',gen_random_uuid()::text,true);

select set_config('wf07.missing_user',gen_random_uuid()::text,true);
select set_config('wf07.missing_tenant',gen_random_uuid()::text,true);
select set_config('wf07.missing_room',gen_random_uuid()::text,true);
select set_config('wf07.missing_occupancy',gen_random_uuid()::text,true);

insert into auth.users(id) values
  (current_setting('wf07.owner_user')::uuid),
  (current_setting('wf07.staff')::uuid),
  (current_setting('wf07.partial_user')::uuid),
  (current_setting('wf07.refund_user')::uuid),
  (current_setting('wf07.hold_user')::uuid),
  (current_setting('wf07.missing_user')::uuid);

insert into public.profiles(user_id,organization_id,display_name,status) values
  (current_setting('wf07.owner_user')::uuid,current_setting('wf07.org')::uuid,'WF07 owner','active'),
  (current_setting('wf07.staff')::uuid,current_setting('wf07.org')::uuid,'WF07 responsible','active');

insert into public.profiles(user_id,organization_id,display_name,status)
values (
  current_setting('wf07.root')::uuid,current_setting('wf07.org')::uuid,
  'WF07 ROOT','active'
)
on conflict(user_id) do update
set organization_id=excluded.organization_id,status='active',archived_at=null;

insert into public.user_roles(user_id,organization_id,role) values
  (current_setting('wf07.owner_user')::uuid,current_setting('wf07.org')::uuid,'owner'),
  (current_setting('wf07.staff')::uuid,current_setting('wf07.org')::uuid,'employee'),
  (current_setting('wf07.partial_user')::uuid,current_setting('wf07.org')::uuid,'tenant'),
  (current_setting('wf07.refund_user')::uuid,current_setting('wf07.org')::uuid,'tenant'),
  (current_setting('wf07.hold_user')::uuid,current_setting('wf07.org')::uuid,'tenant'),
  (current_setting('wf07.missing_user')::uuid,current_setting('wf07.org')::uuid,'tenant');

insert into public.owners(id,organization_id,user_id,full_name,status)
values(
  current_setting('wf07.owner')::uuid,current_setting('wf07.org')::uuid,
  current_setting('wf07.owner_user')::uuid,'WF07 owner','active'
);

insert into public.properties_v2(
  id,organization_id,owner_id,name,address_line,status
) values (
  current_setting('wf07.property')::uuid,current_setting('wf07.org')::uuid,
  current_setting('wf07.owner')::uuid,'WF07 property','Regression','active'
);

insert into public.rooms_v2(id,property_id,label,status) values
  (current_setting('wf07.partial_room')::uuid,current_setting('wf07.property')::uuid,'WF07 partial','active'),
  (current_setting('wf07.refund_room')::uuid,current_setting('wf07.property')::uuid,'WF07 refund','active'),
  (current_setting('wf07.hold_room')::uuid,current_setting('wf07.property')::uuid,'WF07 hold','active'),
  (current_setting('wf07.missing_room')::uuid,current_setting('wf07.property')::uuid,'WF07 missing','active');

insert into public.property_staff_access_v3(
  organization_id,property_id,employee_user_id,assignment_type,can_write,granted_by
) values (
  current_setting('wf07.org')::uuid,current_setting('wf07.property')::uuid,
  current_setting('wf07.staff')::uuid,'responsible',true,current_setting('wf07.root')::uuid
);

insert into public.tenants_v2(
  id,organization_id,user_id,full_name,document_type,document_number,email,status
) values
  (
    current_setting('wf07.partial_tenant')::uuid,current_setting('wf07.org')::uuid,
    current_setting('wf07.partial_user')::uuid,'WF07 partial tenant','other','WF07-PARTIAL',
    'wf07-partial@example.invalid','active'
  ),
  (
    current_setting('wf07.refund_tenant')::uuid,current_setting('wf07.org')::uuid,
    current_setting('wf07.refund_user')::uuid,'WF07 refund tenant','other','WF07-REFUND',
    'wf07-refund@example.invalid','active'
  ),
  (
    current_setting('wf07.hold_tenant')::uuid,current_setting('wf07.org')::uuid,
    current_setting('wf07.hold_user')::uuid,'WF07 hold tenant','other','WF07-HOLD',
    'wf07-hold@example.invalid','active'
  ),
  (
    current_setting('wf07.missing_tenant')::uuid,current_setting('wf07.org')::uuid,
    current_setting('wf07.missing_user')::uuid,'WF07 missing tenant','other','WF07-MISSING',
    'wf07-missing@example.invalid','active'
  );

insert into public.occupancies_v2(
  id,organization_id,tenant_id,property_id,room_id,occupant_email,
  starts_on,ends_on,status,user_id
) values
  (
    current_setting('wf07.partial_occupancy')::uuid,current_setting('wf07.org')::uuid,
    current_setting('wf07.partial_tenant')::uuid,current_setting('wf07.property')::uuid,
    current_setting('wf07.partial_room')::uuid,'wf07-partial@example.invalid',
    current_date-10,null,'active',current_setting('wf07.partial_user')::uuid
  ),
  (
    current_setting('wf07.refund_occupancy')::uuid,current_setting('wf07.org')::uuid,
    current_setting('wf07.refund_tenant')::uuid,current_setting('wf07.property')::uuid,
    current_setting('wf07.refund_room')::uuid,'wf07-refund@example.invalid',
    current_date-10,null,'active',current_setting('wf07.refund_user')::uuid
  ),
  (
    current_setting('wf07.hold_occupancy')::uuid,current_setting('wf07.org')::uuid,
    current_setting('wf07.hold_tenant')::uuid,current_setting('wf07.property')::uuid,
    current_setting('wf07.hold_room')::uuid,'wf07-hold@example.invalid',
    current_date-10,null,'active',current_setting('wf07.hold_user')::uuid
  ),
  (
    current_setting('wf07.missing_occupancy')::uuid,current_setting('wf07.org')::uuid,
    current_setting('wf07.missing_tenant')::uuid,current_setting('wf07.property')::uuid,
    current_setting('wf07.missing_room')::uuid,'wf07-missing@example.invalid',
    current_date-10,null,'active',current_setting('wf07.missing_user')::uuid
  );

create function pg_temp.wf07_receipt_spec(p_amount bigint,p_name text)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'authoringVersion',2,'flowName',p_name,'flowType','deposit_receipt',
    'flowDescription','WF07 regression only',
    'scopeType','occupancy','triggerType','manual','eventType','',
    'recurrence','','scheduledAt','','scheduledTimezone','','scheduledAtUtc','',
    'customEvery','','customUnit','','assignmentType','property_responsible',
    'assignmentUserId','','assignmentRole',
    'depositAmountCents',p_amount,'depositCurrency','EUR',
    'steps',jsonb_build_object('accept',false,'photo',false,'checklist',false,'document',false),
    'checklistItems','[]'::jsonb,'closeType','domain_adapter',
    'notifications',jsonb_build_object('onCreate',false,'onClose',true)
  );
$$;

create function pg_temp.wf07_review_spec()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'authoringVersion',2,'flowName','WF07 revisión fianza','flowType','deposit_review',
    'flowDescription','WF07 regression only',
    'scopeType','property','triggerType','event','eventType','occupancy.offboarded',
    'recurrence','','scheduledAt','','scheduledTimezone','','scheduledAtUtc','',
    'customEvery','','customUnit','','assignmentType','property_responsible',
    'assignmentUserId','','assignmentRole',
    'steps',jsonb_build_object('accept',false,'photo',false,'checklist',true,'document',false),
    'checklistItems',jsonb_build_array(
      jsonb_build_object('key','review','text','Revisar estado final','required',true)
    ),
    'closeType','domain_adapter',
    'notifications',jsonb_build_object('onCreate',false,'onClose',true)
  );
$$;

create function pg_temp.wf07_damage_spec()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'authoringVersion',2,'flowName','WF07 daños','flowType','damage_claim',
    'flowDescription','WF07 regression only',
    'scopeType','property','triggerType','event','eventType','damage_claim.created',
    'recurrence','','scheduledAt','','scheduledTimezone','','scheduledAtUtc','',
    'customEvery','','customUnit','','assignmentType','property_responsible',
    'assignmentUserId','','assignmentRole',
    'steps',jsonb_build_object('accept',false,'photo',false,'checklist',true,'document',false),
    'checklistItems',jsonb_build_array(
      jsonb_build_object('key','damage','text','Documentar daño','required',true)
    ),
    'closeType','domain_adapter',
    'notifications',jsonb_build_object('onCreate',false,'onClose',true)
  );
$$;

do $authoring$
begin
  if not public.workflow_authoring_complete_v1(
    pg_temp.wf07_receipt_spec(170000,'WF07 recepción partial')
  ) then
    raise exception 'WF07 rejected valid deposit receipt';
  end if;
  if not public.workflow_authoring_complete_v1(pg_temp.wf07_review_spec()) then
    raise exception 'WF07 rejected valid deposit review';
  end if;
  if not public.workflow_authoring_complete_v1(pg_temp.wf07_damage_spec()) then
    raise exception 'WF07 rejected valid damage claim';
  end if;
  if public.workflow_authoring_complete_v1(
    pg_temp.wf07_damage_spec()
      || jsonb_build_object(
        'steps',jsonb_build_object('accept',false,'photo',false,'checklist',false,'document',false),
        'checklistItems','[]'::jsonb
      )
  ) then
    raise exception 'WF07 accepted damage claim without evidence';
  end if;
end;
$authoring$;

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf07.root'),'role','authenticated','aal','aal2'
)::text,true);

select set_config('wf07.review_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf07_review_spec(),
    current_setting('wf07.property')::uuid,
    null,null,'{}'::uuid[],false,'wf07-review-ready',null,null
  ) limit 1
),true);

select set_config('wf07.damage_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf07_damage_spec(),
    current_setting('wf07.property')::uuid,
    null,null,'{}'::uuid[],false,'wf07-damage-ready',null,null
  ) limit 1
),true);

select set_config('wf07.partial_receipt_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf07_receipt_spec(170000,'WF07 recepción partial'),
    current_setting('wf07.property')::uuid,null,
    current_setting('wf07.partial_occupancy')::uuid,
    '{}'
      ::uuid[],false,'wf07-partial-receipt-ready',null,null
  ) limit 1
),true);
select set_config('wf07.refund_receipt_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf07_receipt_spec(120000,'WF07 recepción refund'),
    current_setting('wf07.property')::uuid,null,
    current_setting('wf07.refund_occupancy')::uuid,
    '{}'
      ::uuid[],false,'wf07-refund-receipt-ready',null,null
  ) limit 1
),true);
select set_config('wf07.hold_receipt_app',(
  select application_id::text
  from public.publish_workflow_ready_v1(
    pg_temp.wf07_receipt_spec(100000,'WF07 recepción hold'),
    current_setting('wf07.property')::uuid,null,
    current_setting('wf07.hold_occupancy')::uuid,
    '{}'
      ::uuid[],false,'wf07-hold-receipt-ready',null,null
  ) limit 1
),true);

select set_config('wf07.partial_receipt_exec',(
  select execution_id::text from public.execute_workflow_application_now_v1(
    current_setting('wf07.partial_receipt_app')::uuid,'wf07-partial-receipt-exec',null
  ) limit 1
),true);
select set_config('wf07.refund_receipt_exec',(
  select execution_id::text from public.execute_workflow_application_now_v1(
    current_setting('wf07.refund_receipt_app')::uuid,'wf07-refund-receipt-exec',null
  ) limit 1
),true);
select set_config('wf07.hold_receipt_exec',(
  select execution_id::text from public.execute_workflow_application_now_v1(
    current_setting('wf07.hold_receipt_app')::uuid,'wf07-hold-receipt-exec',null
  ) limit 1
),true);
reset role;

select set_config('wf07.partial_receipt_task',(
  select id::text from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf07.partial_receipt_exec')::uuid
),true);
select set_config('wf07.refund_receipt_task',(
  select id::text from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf07.refund_receipt_exec')::uuid
),true);
select set_config('wf07.hold_receipt_task',(
  select id::text from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf07.hold_receipt_exec')::uuid
),true);

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf07.staff'),'role','authenticated','aal','aal1'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.partial_receipt_task')::uuid,'register_receipt','wf07-partial-received',null
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.refund_receipt_task')::uuid,'register_receipt','wf07-refund-received',null
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.hold_receipt_task')::uuid,'register_receipt','wf07-hold-received',null
);
reset role;

do $received_three$
begin
  if (
    select count(*)
    from public.security_deposits_v2 d
    where d.organization_id=current_setting('wf07.org')::uuid
      and d.status='received'
      and d.received_at is not null
  )<>3 then
    raise exception 'WF07 did not create/receive three canonical deposits';
  end if;
end;
$received_three$;

-- Baja real: conserva histórico, revoca acceso y publica occupancy.offboarded.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf07.root'),'role','authenticated','aal','aal2'
)::text,true);
select public.offboard_tenant_occupancy_v2(current_setting('wf07.partial_occupancy')::uuid,current_date);
select public.offboard_tenant_occupancy_v2(current_setting('wf07.refund_occupancy')::uuid,current_date);
select public.offboard_tenant_occupancy_v2(current_setting('wf07.hold_occupancy')::uuid,current_date);
select public.offboard_tenant_occupancy_v2(current_setting('wf07.missing_occupancy')::uuid,current_date);
reset role;

select private.process_pending_workflow_events_v1(50);
select private.process_pending_workflow_events_v1(50);

-- La Baja sin fianza no puede bloquear la cola.
do $missing_deposit_terminal$
begin
  if not exists(
    select 1
    from public.workflow_event_outbox_v2 e
    where e.source_id=current_setting('wf07.missing_occupancy')::uuid
      and e.event_type='occupancy.offboarded'
      and e.status='processed_with_errors'
  ) or not exists(
    select 1
    from public.workflow_event_dispatches_v2 d
    join public.workflow_event_outbox_v2 e on e.id=d.event_id
    where e.source_id=current_setting('wf07.missing_occupancy')::uuid
      and d.application_id=current_setting('wf07.review_app')::uuid
      and d.status='failed'
      and d.error_key='workflow_domain_lifecycle_mismatch'
  ) then
    raise exception 'WF07 missing deposit did not retire as terminal';
  end if;
end;
$missing_deposit_terminal$;

select set_config('wf07.partial_review_exec',(
  select e.id::text
  from public.workflow_executions_v2 e
  join public.workflow_event_outbox_v2 o on o.id=e.source_event_id
  where e.application_id=current_setting('wf07.review_app')::uuid
    and o.source_id=current_setting('wf07.partial_occupancy')::uuid
),true);
select set_config('wf07.refund_review_exec',(
  select e.id::text
  from public.workflow_executions_v2 e
  join public.workflow_event_outbox_v2 o on o.id=e.source_event_id
  where e.application_id=current_setting('wf07.review_app')::uuid
    and o.source_id=current_setting('wf07.refund_occupancy')::uuid
),true);
select set_config('wf07.hold_review_exec',(
  select e.id::text
  from public.workflow_executions_v2 e
  join public.workflow_event_outbox_v2 o on o.id=e.source_event_id
  where e.application_id=current_setting('wf07.review_app')::uuid
    and o.source_id=current_setting('wf07.hold_occupancy')::uuid
),true);

select set_config('wf07.partial_review_task',(
  select id::text from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf07.partial_review_exec')::uuid
),true);
select set_config('wf07.refund_review_task',(
  select id::text from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf07.refund_review_exec')::uuid
),true);
select set_config('wf07.hold_review_task',(
  select id::text from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf07.hold_review_exec')::uuid
),true);

-- Antiguo inquilino: sin plataforma, sin tarjeta WF07 y sin SELECT directo de claims.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf07.partial_user'),'role','authenticated','aal','aal1'
)::text,true);
do $offboarded_no_access$
begin
  if public.has_current_platform_access_v1() then
    raise exception 'WF07 offboarded tenant retained platform access';
  end if;
  if public.workflow_execution_actor_current_v1(
    current_setting('wf07.partial_review_exec')::uuid
  ) then
    raise exception 'WF07 offboarded tenant retained workflow actor access';
  end if;
  if (
    select count(*) from public.tenant_tasks_v2
    where id=current_setting('wf07.partial_review_task')::uuid
  )<>0 then
    raise exception 'WF07 offboarded tenant can still read review task';
  end if;
  begin
    perform count(*) from public.claims_v2;
    raise exception 'WF07 authenticated retained direct claims SELECT';
  exception when insufficient_privilege then
    null;
  end;
end;
$offboarded_no_access$;
reset role;

-- Gestor inicia las tres revisiones.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf07.staff'),'role','authenticated','aal','aal1'
)::text,true);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.partial_review_task')::uuid,'start_review','wf07-partial-review',null
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.refund_review_task')::uuid,'start_review','wf07-refund-review',null
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.hold_review_task')::uuid,'start_review','wf07-hold-review',null
);

-- Refund no puede cerrar hasta completar evidencia configurada.
do $review_evidence_required$
begin
  begin
    perform * from public.apply_workflow_task_action_v1(
      current_setting('wf07.refund_review_task')::uuid,'refund','wf07-refund-early','Sin daños'
    );
    raise exception 'WF07 refund ignored configured evidence';
  exception when sqlstate '55000' then
    if sqlerrm<>'workflow_wf07_deposit_evidence_required' then raise; end if;
  end;
end;
$review_evidence_required$;

select * from public.set_workflow_checklist_item_v1(
  current_setting('wf07.partial_review_task')::uuid,'review',true,'wf07-partial-review-check'
);
select * from public.set_workflow_checklist_item_v1(
  current_setting('wf07.refund_review_task')::uuid,'review',true,'wf07-refund-review-check'
);
select * from public.set_workflow_checklist_item_v1(
  current_setting('wf07.hold_review_task')::uuid,'review',true,'wf07-hold-review-check'
);

-- Devolución total sin daños.
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.refund_review_task')::uuid,'refund','wf07-refund-final','Sin daños imputables'
);

-- Parcial: abre daño 80€, se resuelve en 60€, retiene 60€.
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.partial_review_task')::uuid,
  'request_info','wf07-partial-info-request',
  'Confirma por email la información necesaria para cerrar la fianza.'
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.partial_review_task')::uuid,
  'continue','wf07-partial-info-received',
  'Respuesta externa recibida por email y registrada por la gestoría.'
);

select * from public.apply_wf07_deposit_action_v1(
  current_setting('wf07.partial_review_task')::uuid,
  'open_damage_claim','wf07-partial-damage-open','Daño parcial',80000
);

-- Una fianza no puede abrir una segunda reclamación aunque cambie request_key.
do $single_damage_claim_per_deposit$
begin
  begin
    perform * from public.apply_wf07_deposit_action_v1(
      current_setting('wf07.partial_review_task')::uuid,
      'open_damage_claim','wf07-partial-damage-open-second','Daño duplicado',1000
    );
    raise exception 'WF07 allowed a second damage claim for one deposit';
  exception when sqlstate '22023' then
    if sqlerrm<>'workflow_action_not_allowed' then raise; end if;
  end;

  if (
    select count(*)
    from public.claims_v2 c
    join public.security_deposits_v2 d on d.id=c.security_deposit_id
    where d.occupancy_id=current_setting('wf07.partial_occupancy')::uuid
      and c.claim_type='damage'
  )<>1 then
    raise exception 'WF07 duplicated the damage claim for one deposit';
  end if;

  if exists(
    select 1
    from public.tenant_task_actions_v2
    where task_id=current_setting('wf07.partial_review_task')::uuid
      and action_key='open_damage_claim'
      and active=true
  ) then
    raise exception 'WF07 kept damage claim opening active after claim creation';
  end if;
end;
$single_damage_claim_per_deposit$;

-- Total: abre daño 120€, se resuelve en 100€, justifica toda la fianza.
select * from public.apply_wf07_deposit_action_v1(
  current_setting('wf07.hold_review_task')::uuid,
  'open_damage_claim','wf07-hold-damage-open','Daño grave',120000
);
reset role;

select private.process_pending_workflow_events_v1(50);
select private.process_pending_workflow_events_v1(50);

select set_config('wf07.partial_damage_claim',(
  select c.id::text from public.claims_v2 c
  join public.security_deposits_v2 d on d.id=c.security_deposit_id
  where d.occupancy_id=current_setting('wf07.partial_occupancy')::uuid
    and c.claim_type='damage'
),true);
select set_config('wf07.hold_damage_claim',(
  select c.id::text from public.claims_v2 c
  join public.security_deposits_v2 d on d.id=c.security_deposit_id
  where d.occupancy_id=current_setting('wf07.hold_occupancy')::uuid
    and c.claim_type='damage'
),true);

select set_config('wf07.partial_damage_exec',(
  select id::text from public.workflow_executions_v2
  where application_id=current_setting('wf07.damage_app')::uuid
    and damage_claim_id=current_setting('wf07.partial_damage_claim')::uuid
),true);
select set_config('wf07.hold_damage_exec',(
  select id::text from public.workflow_executions_v2
  where application_id=current_setting('wf07.damage_app')::uuid
    and damage_claim_id=current_setting('wf07.hold_damage_claim')::uuid
),true);

select set_config('wf07.partial_damage_task',(
  select id::text from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf07.partial_damage_exec')::uuid
),true);
select set_config('wf07.hold_damage_task',(
  select id::text from public.tenant_tasks_v2
  where source_kind='workflow_execution'
    and source_id=current_setting('wf07.hold_damage_exec')::uuid
),true);

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf07.staff'),'role','authenticated','aal','aal1'
)::text,true);

-- No se puede notificar daños sin evidencia.
do $damage_evidence_required$
begin
  begin
    perform * from public.apply_workflow_task_action_v1(
      current_setting('wf07.partial_damage_task')::uuid,'notify','wf07-partial-notify-early',null
    );
    raise exception 'WF07 damage notification ignored evidence';
  exception when sqlstate '55000' then
    if sqlerrm<>'workflow_wf07_damage_evidence_required' then raise; end if;
  end;
end;
$damage_evidence_required$;

select * from public.set_workflow_checklist_item_v1(
  current_setting('wf07.partial_damage_task')::uuid,'damage',true,'wf07-partial-damage-check'
);
select * from public.set_workflow_checklist_item_v1(
  current_setting('wf07.hold_damage_task')::uuid,'damage',true,'wf07-hold-damage-check'
);

select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.partial_damage_task')::uuid,'notify','wf07-partial-notify',null
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.partial_damage_task')::uuid,
  'request_info','wf07-partial-damage-info-request',
  'Solicita aclaración adicional por email.'
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.partial_damage_task')::uuid,
  'continue','wf07-partial-damage-info-received',
  'Respuesta externa recibida y registrada.'
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.hold_damage_task')::uuid,'notify','wf07-hold-notify',null
);

select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.partial_damage_task')::uuid,'record_dispute','wf07-partial-dispute','Disputa recibida por canal externo'
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.hold_damage_task')::uuid,'record_acceptance','wf07-hold-accept','Aceptación recibida por canal externo'
);

select * from public.apply_wf07_damage_action_v1(
  current_setting('wf07.partial_damage_task')::uuid,
  'resolve','wf07-partial-resolve','Daño reconocido parcialmente',60000
);
select * from public.apply_wf07_damage_action_v1(
  current_setting('wf07.hold_damage_task')::uuid,
  'resolve','wf07-hold-resolve','Daño reconocido',100000
);

do $refund_with_settled_damage_denied$
begin
  begin
    perform * from public.apply_workflow_task_action_v1(
      current_setting('wf07.partial_review_task')::uuid,
      'refund','wf07-partial-invalid-refund','Intento de devolución total'
    );
    raise exception 'WF07 allowed refund despite settled damage';
  exception when sqlstate '55000' then
    if sqlerrm<>'workflow_wf07_refund_has_damage_settlement' then raise; end if;
  end;
end;
$refund_with_settled_damage_denied$;

select * from public.apply_wf07_deposit_action_v1(
  current_setting('wf07.partial_review_task')::uuid,
  'partial_hold','wf07-partial-hold','Retención respaldada por daño resuelto',60000
);
select * from public.apply_workflow_task_action_v1(
  current_setting('wf07.hold_review_task')::uuid,
  'hold','wf07-full-hold','Retención total respaldada por daño resuelto'
);
reset role;

do $final_states$
begin
  if not exists(
    select 1 from public.security_deposits_v2
    where occupancy_id=current_setting('wf07.refund_occupancy')::uuid
      and status='refunded'
      and held_amount_cents=0
      and refunded_amount_cents=120000
      and resolved_at is not null
  ) then
    raise exception 'WF07 full refund state is inconsistent';
  end if;

  if not exists(
    select 1 from public.security_deposits_v2
    where occupancy_id=current_setting('wf07.partial_occupancy')::uuid
      and status='partially_held'
      and held_amount_cents=60000
      and refunded_amount_cents=110000
      and resolved_at is not null
  ) then
    raise exception 'WF07 partial hold state is inconsistent';
  end if;

  if not exists(
    select 1 from public.security_deposits_v2
    where occupancy_id=current_setting('wf07.hold_occupancy')::uuid
      and status='held'
      and held_amount_cents=100000
      and refunded_amount_cents=0
      and resolved_at is not null
  ) then
    raise exception 'WF07 full hold state is inconsistent';
  end if;

  if not exists(
    select 1 from public.claims_v2
    where id=current_setting('wf07.partial_damage_claim')::uuid
      and status='resolved'
      and tenant_decision='disputed'
      and claimed_amount_cents=80000
      and settled_amount_cents=60000
  ) or not exists(
    select 1 from public.claims_v2
    where id=current_setting('wf07.hold_damage_claim')::uuid
      and status='resolved'
      and tenant_decision='accepted'
      and claimed_amount_cents=120000
      and settled_amount_cents=100000
  ) then
    raise exception 'WF07 damage settlements are inconsistent';
  end if;

  if (
    select count(*) from public.workflow_event_outbox_v2
    where event_type='damage_claim.created'
      and source_kind='damage_claim'
      and source_id in (
        current_setting('wf07.partial_damage_claim')::uuid,
        current_setting('wf07.hold_damage_claim')::uuid
      )
  )<>2 then
    raise exception 'WF07 damage events are not exactly once';
  end if;

  if not exists(
    select 1 from public.notifications_v2 n
    join public.security_deposits_v2 d on d.id=n.source_id
    where d.occupancy_id=current_setting('wf07.partial_occupancy')::uuid
      and n.source_kind='security_deposit'
      and n.event_key='information_requested:wf07-partial-info-request'
      and n.channel_email=true
  ) or not exists(
    select 1 from public.notifications_v2
    where source_kind='damage_claim'
      and source_id=current_setting('wf07.partial_damage_claim')::uuid
      and event_key='notified'
      and channel_email=true
  ) or not exists(
    select 1 from public.notifications_v2
    where source_kind='damage_claim'
      and source_id=current_setting('wf07.partial_damage_claim')::uuid
      and event_key='information_requested:wf07-partial-damage-info-request'
      and channel_email=true
  ) or not exists(
    select 1 from public.notifications_v2
    where source_kind='damage_claim'
      and source_id=current_setting('wf07.partial_damage_claim')::uuid
      and event_key='resolved'
      and channel_email=true
  ) then
    raise exception 'WF07 offboarded-tenant email notifications are incomplete';
  end if;
end;
$final_states$;

-- Reintento terminal con misma clave no duplica historial.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('wf07.staff'),'role','authenticated','aal','aal1'
)::text,true);
do $partial_hold_idempotent$
declare v_result record;
begin
  select * into v_result
  from public.apply_wf07_deposit_action_v1(
    current_setting('wf07.partial_review_task')::uuid,
    'partial_hold','wf07-partial-hold','Retención respaldada por daño resuelto',60000
  );
  if v_result.applied_new then
    raise exception 'WF07 duplicated terminal deposit action';
  end if;
end;
$partial_hold_idempotent$;
reset role;

-- El dispatcher email es idempotente e independiente del rol tenant activo.
do $email_delivery_contract$
declare
  v_notification uuid;
  v_first boolean;
  v_second boolean;
begin
  select n.id into v_notification
  from public.notifications_v2 n
  where n.source_kind='damage_claim'
    and n.source_id=current_setting('wf07.partial_damage_claim')::uuid
    and n.event_key='notified'
    and n.channel_email=true
  limit 1;

  if v_notification is null then
    raise exception 'WF07 email notification fixture missing';
  end if;

  if not exists(
    select 1
    from pg_trigger
    where tgname='notification_email_dispatch_v1'
      and not tgisinternal
  ) then
    raise exception 'WF07 notification email trigger missing';
  end if;

  v_first:=public.notification_email_claim_delivery_v1(v_notification);
  v_second:=public.notification_email_claim_delivery_v1(v_notification);
  if v_first is distinct from true or v_second is distinct from false then
    raise exception 'WF07 email delivery claim is not idempotent';
  end if;

  perform public.notification_email_finish_delivery_v1(
    v_notification,true,null,'wf07-regression-provider-id'
  );

  if not exists(
    select 1
    from public.notification_email_deliveries_v1
    where notification_id=v_notification
      and status='sent'
      and provider_message_id='wf07-regression-provider-id'
  ) then
    raise exception 'WF07 email delivery receipt did not finish as sent';
  end if;
end;
$email_delivery_contract$;

rollback;
