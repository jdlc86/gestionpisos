-- GestionPisos · WF-07 · una sola reclamación de daños por fianza
-- Hardening aditivo: impide duplicados incluso con request_key distintos y
-- retira la acción de apertura una vez creado el expediente.

create unique index if not exists claims_v2_damage_security_deposit_uq
  on public.claims_v2(security_deposit_id)
  where claim_type='damage' and security_deposit_id is not null;

create or replace function private.wf07_disable_damage_claim_reopen_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $wf07_single_damage_claim$
begin
  if new.claim_type<>'damage' or new.security_deposit_id is null then
    return new;
  end if;

  update public.tenant_task_actions_v2 a
  set active=false
  from public.tenant_tasks_v2 t
  join public.workflow_executions_v2 e
    on e.id=t.source_id
   and t.source_kind='workflow_execution'
  where a.task_id=t.id
    and e.security_deposit_id=new.security_deposit_id
    and e.spec_snapshot->>'flowType'='deposit_review'
    and e.spec_snapshot->>'closeType'='domain_adapter'
    and a.action_key='open_damage_claim'
    and a.active=true;

  return new;
end;
$wf07_single_damage_claim$;

revoke all on function private.wf07_disable_damage_claim_reopen_v1()
  from public,anon,authenticated,service_role;

drop trigger if exists wf07_disable_damage_claim_reopen_v1
  on public.claims_v2;

create trigger wf07_disable_damage_claim_reopen_v1
after insert on public.claims_v2
for each row
when (new.claim_type='damage' and new.security_deposit_id is not null)
execute function private.wf07_disable_damage_claim_reopen_v1();

comment on index public.claims_v2_damage_security_deposit_uq is
  'WF-07: una fianza solo puede originar un expediente de reclamación por daños.';
