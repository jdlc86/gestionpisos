-- Batería E2E final · preflight automático.
-- No modifica datos; aborta si una frontera estructural imprescindible ha regresado.

begin;
set local transaction read only;

do $final_e2e_preflight$
declare
  v_apply_legacy text;
  v_create_legacy text;
begin
  if to_regclass('public.workflow_executions_v2') is null
    or to_regclass('public.tenant_tasks_v2') is null
    or to_regclass('public.incidents_v2') is null
    or to_regclass('public.payment_obligations_v2') is null
    or to_regclass('public.claims_v2') is null
    or to_regclass('public.security_deposits_v2') is null then
    raise exception 'final E2E preflight: required workflow/domain table missing';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.apply_workflow_task_action_v1(uuid,text,text,text)',
    'EXECUTE'
  ) then
    raise exception 'final E2E preflight: current workflow action router is not executable';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.apply_workflow_task_action_pre_wf07_v1(uuid,text,text,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'service_role',
    'public.apply_workflow_task_action_pre_wf07_v1(uuid,text,text,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.apply_workflow_task_action_pre_wf07_v1(uuid,text,text,text)',
    'EXECUTE'
  ) then
    raise exception 'final E2E preflight: superseded WF07 action router became externally executable';
  end if;

  if exists(
    select 1
    from public.tenant_task_workflow_templates_v2
    where task_type='workflow'
  ) then
    raise exception 'final E2E preflight: legacy templates can seed workflow cards';
  end if;

  if exists(
    select source_id
    from public.tenant_tasks_v2
    where task_type='workflow'
      and source_kind='workflow_execution'
    group by source_id
    having count(*)>1
  ) then
    raise exception 'final E2E preflight: workflow execution has duplicate operational cards';
  end if;

  if has_table_privilege('authenticated','public.tenant_tasks_v2','insert')
    or has_table_privilege('authenticated','public.tenant_tasks_v2','update')
    or has_table_privilege('authenticated','public.tenant_tasks_v2','delete') then
    raise exception 'final E2E preflight: direct workflow task writes exposed to authenticated';
  end if;

  if has_table_privilege('authenticated','public.security_deposits_v2','insert')
    or has_table_privilege('authenticated','public.security_deposits_v2','update')
    or has_table_privilege('authenticated','public.security_deposits_v2','delete') then
    raise exception 'final E2E preflight: direct security deposit writes exposed to authenticated';
  end if;

  if has_table_privilege('authenticated','public.claims_v2','insert')
    or has_table_privilege('authenticated','public.claims_v2','update')
    or has_table_privilege('authenticated','public.claims_v2','delete') then
    raise exception 'final E2E preflight: direct claims writes exposed to authenticated';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.create_tenant_task_v2(uuid,text,text,text,timestamptz,uuid,uuid,uuid,text,text,uuid)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.apply_tenant_task_action_v2(uuid,text,text)',
    'EXECUTE'
  ) then
    raise exception 'final E2E preflight: legacy compatibility RPC removed before human E2E';
  end if;

  v_apply_legacy:=pg_get_functiondef(
    'public.apply_tenant_task_action_v2(uuid,text,text)'::regprocedure
  );
  if position('workflow_task_requires_atomic_action' in v_apply_legacy)=0 then
    raise exception 'final E2E preflight: legacy action RPC no longer blocks workflow cards';
  end if;

  v_create_legacy:=pg_get_functiondef(
    'public.create_tenant_task_v2(uuid,text,text,text,timestamptz,uuid,uuid,uuid,text,text,uuid)'::regprocedure
  );
  if position('when ''workflow''' in lower(v_create_legacy))>0 then
    raise exception 'final E2E preflight: legacy creator accepts task_type=workflow';
  end if;
end;
$final_e2e_preflight$;

select jsonb_build_object(
  'workflow_definitions', (select count(*) from public.workflow_definitions_v2),
  'workflow_applications', (select count(*) from public.workflow_applications_v2),
  'workflow_executions', (select count(*) from public.workflow_executions_v2),
  'workflow_tasks', (select count(*) from public.tenant_tasks_v2 where task_type='workflow' and source_kind='workflow_execution'),
  'legacy_tasks', (select count(*) from public.tenant_tasks_v2 where not (task_type='workflow' and source_kind='workflow_execution')),
  'incidents', (select count(*) from public.incidents_v2),
  'payment_obligations', (select count(*) from public.payment_obligations_v2),
  'claims', (select count(*) from public.claims_v2),
  'security_deposits', (select count(*) from public.security_deposits_v2)
) as snapshot;

rollback;
