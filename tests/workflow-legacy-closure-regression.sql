-- WF-09 · cierre controlado de compatibilidad legacy.
-- No modifica datos: congela las fronteras entre tareas históricas y el motor común.

begin;

do $wf09_legacy_boundaries$
declare
  v_apply text;
  v_create text;
  v_constraint text;
begin
  v_apply:=pg_get_functiondef(
    'public.apply_tenant_task_action_v2(uuid,text,text)'::regprocedure
  );
  if position('workflow_task_requires_atomic_action' in v_apply)=0
    or position('task_type=''workflow''' in v_apply)=0
    or position('source_kind=''workflow_execution''' in v_apply)=0 then
    raise exception 'WF09 legacy action RPC no longer blocks workflow cards';
  end if;

  v_create:=pg_get_functiondef(
    'public.create_tenant_task_v2(uuid,text,text,text,timestamptz,uuid,uuid,uuid,text,text,uuid)'::regprocedure
  );
  if position('when ''workflow''' in lower(v_create))>0 then
    raise exception 'WF09 legacy creator accepts task_type=workflow';
  end if;

  select pg_get_constraintdef(c.oid)
  into v_constraint
  from pg_constraint c
  where c.conrelid='public.tenant_tasks_v2'::regclass
    and c.conname='tenant_tasks_v2_subject_or_workflow_check';

  if v_constraint is null
    or position('workflow_execution' in v_constraint)=0
    or position('task_type = ''workflow''' in v_constraint)=0 then
    raise exception 'WF09 workflow subject boundary constraint is missing';
  end if;

  if exists(
    select 1
    from public.tenant_task_workflow_templates_v2
    where task_type='workflow'
  ) then
    raise exception 'WF09 legacy templates can seed workflow cards';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.workflow_materialize_execution_task_internal_v1(uuid,uuid)',
    'EXECUTE'
  ) then
    raise exception 'WF09 internal workflow materializer became client executable';
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
    raise exception 'WF09 compatibility RPC removed before final E2E';
  end if;
end;
$wf09_legacy_boundaries$;

rollback;
