-- GestionPisos · WF-06 · núcleo financiero y contrato de autoría
-- Pago de alquiler y reclamación reutilizan payment_obligations_v2 / claims_v2
-- y el motor workflow transversal. No se crea un ledger ni un motor paralelo.

alter table public.payment_obligations_v2
  add column if not exists occupancy_id uuid
    references public.occupancies_v2(id) on delete restrict,
  add column if not exists updated_at timestamptz not null default now();

alter table public.claims_v2
  add column if not exists occupancy_id uuid
    references public.occupancies_v2(id) on delete restrict,
  add column if not exists tenant_decision text
    check (tenant_decision is null or tenant_decision in ('accepted','disputed')),
  add column if not exists updated_at timestamptz not null default now();

alter table public.claims_v2
  drop constraint if exists claims_v2_status_check;
alter table public.claims_v2
  add constraint claims_v2_status_check
  check (status in (
    'draft','scheduled','sent','waiting_info',
    'acknowledged','resolved','cancelled'
  ));

alter table public.workflow_executions_v2
  add column if not exists payment_obligation_id uuid
    references public.payment_obligations_v2(id) on delete restrict,
  add column if not exists rent_claim_id uuid
    references public.claims_v2(id) on delete restrict;

create unique index if not exists workflow_executions_v2_payment_obligation_uq
  on public.workflow_executions_v2(payment_obligation_id)
  where payment_obligation_id is not null;

create unique index if not exists workflow_executions_v2_rent_claim_uq
  on public.workflow_executions_v2(rent_claim_id)
  where rent_claim_id is not null;

create unique index if not exists claims_v2_payment_obligation_uq
  on public.claims_v2(obligation_id)
  where claim_type='payment' and obligation_id is not null;

create index if not exists payment_obligations_v2_occupancy_due_idx
  on public.payment_obligations_v2(occupancy_id,status,due_date)
  where occupancy_id is not null;

create index if not exists claims_v2_occupancy_created_idx
  on public.claims_v2(occupancy_id,created_at desc)
  where occupancy_id is not null;

alter table public.workflow_event_outbox_v2
  drop constraint if exists workflow_event_outbox_v2_event_type_check;
alter table public.workflow_event_outbox_v2
  add constraint workflow_event_outbox_v2_event_type_check
  check (event_type in (
    'occupancy.created','occupancy.offboarded',
    'incident.created','incident.resolved',
    'rent_claim.created'
  ));

alter table public.workflow_event_outbox_v2
  drop constraint if exists workflow_event_outbox_v2_source_kind_check;
alter table public.workflow_event_outbox_v2
  add constraint workflow_event_outbox_v2_source_kind_check
  check (source_kind in ('occupancy','incident','rent_claim'));

create or replace function private.wf06_internal_access_v1(
  p_organization_id uuid,
  p_property_id uuid,
  p_actor uuid,
  p_require_write boolean default false
)
returns boolean
language sql
stable
security definer
set search_path=''
as $wf06_internal_access$
  select p_actor is not null
    and exists(
      select 1
      from public.profiles pr
      where pr.user_id=p_actor
        and pr.status='active'
        and pr.archived_at is null
    )
    and (
      exists(
        select 1
        from public.user_roles ur
        where ur.user_id=p_actor
          and ur.role='root'
          and ur.revoked_at is null
      )
      or exists(
        select 1
        from public.user_roles ur
        where ur.user_id=p_actor
          and ur.organization_id=p_organization_id
          and ur.role='admin'
          and ur.revoked_at is null
      )
      or exists(
        select 1
        from public.user_roles ur
        join public.property_staff_access_v3 a
          on a.employee_user_id=ur.user_id
         and a.organization_id=ur.organization_id
         and a.property_id=p_property_id
        where ur.user_id=p_actor
          and ur.organization_id=p_organization_id
          and ur.role='employee'
          and ur.revoked_at is null
          and a.assignment_type in ('responsible','access')
          and a.revoked_at is null
          and a.valid_from<=now()
          and (a.valid_until is null or a.valid_until>now())
          and (not p_require_write or a.can_write=true)
      )
    );
$wf06_internal_access$;

revoke all on function private.wf06_internal_access_v1(
  uuid,uuid,uuid,boolean
) from public,anon,authenticated,service_role;

create or replace function private.wf06_require_privileged_aal2_v1(
  p_organization_id uuid,
  p_actor uuid
)
returns void
language plpgsql
stable
security definer
set search_path=''
as $wf06_aal2$
begin
  if exists(
    select 1
    from public.user_roles ur
    where ur.user_id=p_actor
      and ur.revoked_at is null
      and (
        ur.role='root'
        or (ur.role='admin' and ur.organization_id=p_organization_id)
      )
  ) and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
    raise exception 'workflow_wf06_mfa_required' using errcode='42501';
  end if;
end;
$wf06_aal2$;

revoke all on function private.wf06_require_privileged_aal2_v1(
  uuid,uuid
) from public,anon,authenticated,service_role;

-- Autoría: extender el sanitizador sin cambiar contratos de WF-00..WF-05.
alter function private.workflow_sanitize_authoring_spec_v3(jsonb)
  rename to workflow_sanitize_authoring_spec_pre_wf06_v3;
revoke all on function private.workflow_sanitize_authoring_spec_pre_wf06_v3(jsonb)
  from public,anon,authenticated,service_role;

create function private.workflow_sanitize_authoring_spec_v3(p_spec jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $wf06_sanitize$
declare
  v_flow text:=coalesce(p_spec->>'flowType','');
  v_spec jsonb;
  v_concept text;
  v_amount_text text;
  v_amount bigint;
  v_currency text;
  v_due_days_text text;
  v_due_days integer;
begin
  if v_flow='rent_payment' then
    v_concept:=btrim(coalesce(p_spec->>'paymentConcept',''));
    v_amount_text:=btrim(coalesce(p_spec->>'paymentAmountCents',''));
    v_currency:=upper(btrim(coalesce(p_spec->>'paymentCurrency','EUR')));
    v_due_days_text:=btrim(coalesce(p_spec->>'paymentDueDays','0'));

    if char_length(v_concept)<1 or char_length(v_concept)>120 then
      raise exception 'workflow_wf06_payment_concept_invalid' using errcode='22023';
    end if;
    if v_amount_text !~ '^[0-9]+$' then
      raise exception 'workflow_wf06_payment_amount_invalid' using errcode='22023';
    end if;
    v_amount:=v_amount_text::bigint;
    if v_amount<1 or v_amount>1000000000 then
      raise exception 'workflow_wf06_payment_amount_invalid' using errcode='22023';
    end if;
    if v_currency !~ '^[A-Z]{3}$' then
      raise exception 'workflow_wf06_payment_currency_invalid' using errcode='22023';
    end if;
    if v_due_days_text !~ '^[0-9]+$' then
      raise exception 'workflow_wf06_payment_due_days_invalid' using errcode='22023';
    end if;
    v_due_days:=v_due_days_text::integer;
    if v_due_days<0 or v_due_days>365 then
      raise exception 'workflow_wf06_payment_due_days_invalid' using errcode='22023';
    end if;

    v_spec:=private.workflow_sanitize_authoring_spec_pre_wf06_v3(
      p_spec || jsonb_build_object('flowType','custom')
    );
    return v_spec || jsonb_build_object(
      'flowType','rent_payment',
      'paymentConcept',v_concept,
      'paymentAmountCents',v_amount,
      'paymentCurrency',v_currency,
      'paymentDueDays',v_due_days
    );
  end if;

  if v_flow='rent_claim' then
    v_spec:=private.workflow_sanitize_authoring_spec_pre_wf06_v3(
      p_spec || jsonb_build_object(
        'flowType','maintenance',
        'eventType','incident.created'
      )
    );
    return v_spec || jsonb_build_object(
      'flowType','rent_claim',
      'eventType','rent_claim.created'
    );
  end if;

  return private.workflow_sanitize_authoring_spec_pre_wf06_v3(p_spec);
end;
$wf06_sanitize$;

revoke all on function private.workflow_sanitize_authoring_spec_v3(jsonb)
  from public,anon,authenticated,service_role;

alter function public.workflow_authoring_complete_v1(jsonb)
  rename to workflow_authoring_complete_pre_wf06_v1;
revoke all on function public.workflow_authoring_complete_pre_wf06_v1(jsonb)
  from public,anon,authenticated,service_role;

create function public.workflow_authoring_complete_v1(p_spec jsonb)
returns boolean
language plpgsql
immutable
security definer
set search_path=''
as $wf06_complete$
declare
  v_flow text:=coalesce(p_spec->>'flowType','');
  v_base jsonb;
  v_steps jsonb;
begin
  if v_flow='rent_payment' then
    v_steps:=jsonb_build_object(
      'accept',true,'photo',false,'checklist',false,'document',false
    );
    v_base:=p_spec || jsonb_build_object(
      'flowType','custom',
      'closeType','auto',
      'steps',v_steps
    );
    if not public.workflow_authoring_complete_pre_wf06_v1(v_base) then
      return false;
    end if;

    return p_spec->>'scopeType'='occupancy'
      and p_spec->>'triggerType' in ('manual','scheduled_once','recurring')
      and p_spec->>'assignmentType' in ('property_responsible','fixed_person','role')
      and (
        p_spec->>'assignmentType'<>'role'
        or p_spec->>'assignmentRole' in ('admin','employee')
      )
      and p_spec->>'closeType'='domain_adapter'
      and coalesce(p_spec->>'paymentConcept','')<>''
      and coalesce(p_spec->>'paymentCurrency','') ~ '^[A-Z]{3}$'
      and coalesce(p_spec->>'paymentAmountCents','') ~ '^[0-9]+$'
      and (p_spec->>'paymentAmountCents')::bigint between 1 and 1000000000
      and coalesce(p_spec->>'paymentDueDays','') ~ '^[0-9]+$'
      and (p_spec->>'paymentDueDays')::integer between 0 and 365;
  end if;

  if v_flow='rent_claim' then
    v_base:=p_spec || jsonb_build_object(
      'flowType','maintenance',
      'eventType','incident.created',
      'closeType','domain_adapter',
      'steps',jsonb_build_object(
        'accept',true,'photo',false,'checklist',false,'document',false
      )
    );
    if not public.workflow_authoring_complete_pre_wf06_v1(v_base) then
      return false;
    end if;

    return p_spec->>'triggerType'='event'
      and p_spec->>'eventType'='rent_claim.created'
      and p_spec->>'scopeType' in ('property','room')
      and p_spec->>'assignmentType' in ('property_responsible','fixed_person','role')
      and (
        p_spec->>'assignmentType'<>'role'
        or p_spec->>'assignmentRole' in ('admin','employee')
      )
      and p_spec->>'closeType'='domain_adapter';
  end if;

  return public.workflow_authoring_complete_pre_wf06_v1(p_spec);
end;
$wf06_complete$;

revoke all on function public.workflow_authoring_complete_v1(jsonb)
  from public,anon,service_role;
grant execute on function public.workflow_authoring_complete_v1(jsonb)
  to authenticated;

comment on column public.workflow_executions_v2.payment_obligation_id is
  'WF-06 payment obligation bound one-to-one to a rent_payment execution.';
comment on column public.workflow_executions_v2.rent_claim_id is
  'WF-06 rent claim dossier bound one-to-one to the claim management execution.';
comment on function public.workflow_authoring_complete_v1(jsonb) is
  'Validador transversal + WF-04/WF-05/WF-06. rent_payment exige ocupación exacta y domain_adapter; rent_claim consume rent_claim.created.';
