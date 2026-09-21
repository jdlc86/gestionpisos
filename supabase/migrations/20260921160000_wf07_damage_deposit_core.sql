-- GestionPisos · WF-07 · núcleo de Daños + Fianza
-- Reutiliza claims_v2 y el motor transversal. La fianza es un expediente
-- operativo por ocupación; no se crea ledger ni contabilidad paralela.

create table if not exists public.security_deposits_v2(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  property_id uuid not null references public.properties_v2(id) on delete restrict,
  room_id uuid references public.rooms_v2(id) on delete restrict,
  occupancy_id uuid not null references public.occupancies_v2(id) on delete restrict,
  tenant_user_id uuid not null references auth.users(id) on delete restrict,
  amount_cents bigint not null check(amount_cents>0 and amount_cents<=1000000000),
  currency text not null default 'EUR' check(currency ~ '^[A-Z]{3}$'),
  status text not null default 'pending'
    check(status in (
      'pending','received','under_review','waiting_info',
      'refunded','partially_held','held','cancelled'
    )),
  held_amount_cents bigint not null default 0 check(held_amount_cents>=0),
  refunded_amount_cents bigint not null default 0 check(refunded_amount_cents>=0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  received_at timestamptz,
  review_started_at timestamptz,
  resolved_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(occupancy_id),
  check(held_amount_cents + refunded_amount_cents <= amount_cents)
);

create index if not exists security_deposits_v2_org_property_status_idx
  on public.security_deposits_v2(organization_id,property_id,status);
create index if not exists security_deposits_v2_tenant_idx
  on public.security_deposits_v2(tenant_user_id,created_at desc);

alter table public.security_deposits_v2 enable row level security;
revoke all on public.security_deposits_v2 from anon,authenticated;
grant select on public.security_deposits_v2 to service_role;

-- Hardening de claims legacy: no aceptar mutación directa cliente y no
-- permitir que una sesión Auth histórica conserve lectura tras la Baja.
revoke select,insert,update,delete,truncate,references,trigger
  on public.claims_v2 from authenticated;

drop policy if exists claims_self_read on public.claims_v2;
create policy claims_self_read
on public.claims_v2
for select
to authenticated
using (
  tenant_user_id=(select auth.uid())
  and public.has_current_platform_access_v1()
);

drop policy if exists claims_admin_read on public.claims_v2;
create policy claims_admin_read
on public.claims_v2
for select
to authenticated
using (
  exists(
    select 1
    from public.profiles pr
    where pr.user_id=(select auth.uid())
      and pr.status='active'
      and pr.archived_at is null
  )
  and exists(
    select 1
    from public.user_roles ur
    where ur.user_id=(select auth.uid())
      and ur.revoked_at is null
      and (
        ur.role='root'
        or (
          ur.role='admin'
          and ur.organization_id=claims_v2.organization_id
        )
      )
  )
);

drop policy if exists claims_admin_insert on public.claims_v2;
create policy claims_admin_insert
on public.claims_v2
for insert
to authenticated
with check (
  exists(
    select 1
    from public.user_roles ur
    where ur.user_id=(select auth.uid())
      and ur.revoked_at is null
      and (
        ur.role='root'
        or (
          ur.role='admin'
          and ur.organization_id=claims_v2.organization_id
        )
      )
  )
);

drop policy if exists claims_admin_update on public.claims_v2;
create policy claims_admin_update
on public.claims_v2
for update
to authenticated
using (
  exists(
    select 1
    from public.user_roles ur
    where ur.user_id=(select auth.uid())
      and ur.revoked_at is null
      and (
        ur.role='root'
        or (
          ur.role='admin'
          and ur.organization_id=claims_v2.organization_id
        )
      )
  )
)
with check (
  exists(
    select 1
    from public.user_roles ur
    where ur.user_id=(select auth.uid())
      and ur.revoked_at is null
      and (
        ur.role='root'
        or (
          ur.role='admin'
          and ur.organization_id=claims_v2.organization_id
        )
      )
  )
);

alter table public.claims_v2
  add column if not exists security_deposit_id uuid
    references public.security_deposits_v2(id) on delete restrict,
  add column if not exists claimed_amount_cents bigint
    check(claimed_amount_cents is null or claimed_amount_cents>0),
  add column if not exists settled_amount_cents bigint
    check(settled_amount_cents is null or settled_amount_cents>=0),
  add column if not exists currency text
    check(currency is null or currency ~ '^[A-Z]{3}$');

alter table public.claims_v2
  drop constraint if exists claims_v2_claim_type_check;
alter table public.claims_v2
  add constraint claims_v2_claim_type_check
  check(claim_type in ('payment','conduct','documentation','other','damage'));

alter table public.claims_v2
  drop constraint if exists claims_v2_damage_amount_check;
alter table public.claims_v2
  add constraint claims_v2_damage_amount_check
  check(
    claim_type<>'damage'
    or (
      security_deposit_id is not null
      and claimed_amount_cents is not null
      and claimed_amount_cents>0
      and currency is not null
      and (
        settled_amount_cents is null
        or settled_amount_cents between 0 and claimed_amount_cents
      )
    )
  );

create index if not exists claims_v2_security_deposit_idx
  on public.claims_v2(security_deposit_id,created_at desc)
  where security_deposit_id is not null;

alter table public.workflow_executions_v2
  add column if not exists security_deposit_id uuid
    references public.security_deposits_v2(id) on delete restrict,
  add column if not exists damage_claim_id uuid
    references public.claims_v2(id) on delete restrict;

create unique index if not exists workflow_executions_v2_damage_claim_uq
  on public.workflow_executions_v2(damage_claim_id)
  where damage_claim_id is not null;
create index if not exists workflow_executions_v2_security_deposit_idx
  on public.workflow_executions_v2(security_deposit_id,created_at desc)
  where security_deposit_id is not null;

alter table public.workflow_event_outbox_v2
  drop constraint if exists workflow_event_outbox_v2_event_type_check;
alter table public.workflow_event_outbox_v2
  add constraint workflow_event_outbox_v2_event_type_check
  check(event_type in (
    'occupancy.created','occupancy.offboarded',
    'incident.created','incident.resolved',
    'rent_claim.created','damage_claim.created'
  ));

alter table public.workflow_event_outbox_v2
  drop constraint if exists workflow_event_outbox_v2_source_kind_check;
alter table public.workflow_event_outbox_v2
  add constraint workflow_event_outbox_v2_source_kind_check
  check(source_kind in ('occupancy','incident','rent_claim','damage_claim'));

-- Una aplicación de recepción por ocupación y un único gestor solapado para
-- revisión/daños por destino efectivo.
create or replace function private.workflow_wf07_guard_application_overlap_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $wf07_overlap$
declare
  v_spec jsonb;
  v_flow text;
begin
  if new.status<>'configured' then
    return new;
  end if;

  select wv.spec into v_spec
  from public.workflow_definition_versions_v2 wv
  where wv.id=new.definition_version_id
    and wv.definition_id=new.definition_id
    and wv.organization_id=new.organization_id;

  v_flow:=coalesce(v_spec->>'flowType','');
  if v_flow not in ('deposit_receipt','deposit_review','damage_claim') then
    return new;
  end if;

  if v_flow='deposit_receipt' then
    if new.scope_type<>'occupancy' or new.occupancy_id is null then
      raise exception 'workflow_wf07_deposit_receipt_scope_invalid'
        using errcode='22023';
    end if;

    perform pg_advisory_xact_lock(
      hashtextextended(
        'wf07-deposit-receipt:'||new.organization_id::text||':'||new.occupancy_id::text,
        0
      )
    );

    if exists(
      select 1
      from public.workflow_applications_v2 a
      join public.workflow_definition_versions_v2 wv
        on wv.id=a.definition_version_id
       and wv.definition_id=a.definition_id
       and wv.organization_id=a.organization_id
      join public.workflow_definitions_v2 d
        on d.id=a.definition_id
       and d.organization_id=a.organization_id
      where a.id is distinct from new.id
        and a.organization_id=new.organization_id
        and a.status='configured'
        and d.status='published'
        and a.scope_type='occupancy'
        and a.occupancy_id=new.occupancy_id
        and wv.spec->>'flowType'='deposit_receipt'
        and wv.spec->>'closeType'='domain_adapter'
    ) then
      raise exception 'workflow_wf07_deposit_receipt_application_conflict'
        using errcode='55000';
    end if;
    return new;
  end if;

  if new.scope_type not in ('property','room') or new.property_id is null then
    raise exception 'workflow_wf07_event_scope_invalid' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'wf07-'||v_flow||':'||new.organization_id::text||':'||new.property_id::text,
      0
    )
  );

  if exists(
    select 1
    from public.workflow_applications_v2 a
    join public.workflow_definition_versions_v2 wv
      on wv.id=a.definition_version_id
     and wv.definition_id=a.definition_id
     and wv.organization_id=a.organization_id
    join public.workflow_definitions_v2 d
      on d.id=a.definition_id
     and d.organization_id=a.organization_id
    where a.id is distinct from new.id
      and a.organization_id=new.organization_id
      and a.status='configured'
      and d.status='published'
      and a.property_id=new.property_id
      and wv.spec->>'flowType'=v_flow
      and wv.spec->>'closeType'='domain_adapter'
      and (
        new.scope_type='property'
        or a.scope_type='property'
        or (
          new.scope_type='room'
          and a.scope_type='room'
          and a.room_id is not distinct from new.room_id
        )
      )
  ) then
    raise exception 'workflow_wf07_event_application_conflict'
      using errcode='55000';
  end if;

  return new;
end;
$wf07_overlap$;

revoke all on function private.workflow_wf07_guard_application_overlap_v1()
  from public,anon,authenticated,service_role;

drop trigger if exists workflow_wf07_guard_application_overlap_v1
  on public.workflow_applications_v2;
create trigger workflow_wf07_guard_application_overlap_v1
before insert or update of
  status,definition_version_id,definition_id,organization_id,
  scope_type,property_id,room_id,occupancy_id
on public.workflow_applications_v2
for each row
execute function private.workflow_wf07_guard_application_overlap_v1();

-- Extiende el productor de eventos con reclamaciones por daños.
alter function private.workflow_enqueue_event_v1(
  uuid,text,text,uuid,text,uuid,uuid,uuid,jsonb,uuid,timestamptz
) rename to workflow_enqueue_event_pre_wf07_v1;
revoke all on function private.workflow_enqueue_event_pre_wf07_v1(
  uuid,text,text,uuid,text,uuid,uuid,uuid,jsonb,uuid,timestamptz
) from public,anon,authenticated,service_role;

create function private.workflow_enqueue_event_v1(
  p_organization_id uuid,
  p_event_type text,
  p_source_kind text,
  p_source_id uuid,
  p_event_key text,
  p_property_id uuid,
  p_room_id uuid,
  p_occupancy_id uuid,
  p_payload jsonb default '{}'::jsonb,
  p_actor_user_id uuid default null,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path=''
as $wf07_enqueue$
declare
  v_claim public.claims_v2;
  v_deposit public.security_deposits_v2;
  v_event_id uuid;
begin
  if p_event_type<>'damage_claim.created' then
    return private.workflow_enqueue_event_pre_wf07_v1(
      p_organization_id,p_event_type,p_source_kind,p_source_id,p_event_key,
      p_property_id,p_room_id,p_occupancy_id,p_payload,p_actor_user_id,p_occurred_at
    );
  end if;

  if p_source_kind<>'damage_claim'
    or p_source_id is null
    or p_event_key<>'created'
    or p_payload is null
    or jsonb_typeof(p_payload)<>'object' then
    raise exception 'workflow_wf07_damage_event_source_invalid'
      using errcode='22023';
  end if;

  select * into v_claim
  from public.claims_v2
  where id=p_source_id;

  if v_claim.id is null
    or v_claim.claim_type<>'damage'
    or v_claim.status<>'draft'
    or v_claim.organization_id is distinct from p_organization_id
    or v_claim.property_id is distinct from p_property_id
    or v_claim.occupancy_id is distinct from p_occupancy_id
    or v_claim.security_deposit_id is null then
    raise exception 'workflow_wf07_damage_event_routing_invalid'
      using errcode='22023';
  end if;

  select * into v_deposit
  from public.security_deposits_v2
  where id=v_claim.security_deposit_id;

  if v_deposit.id is null
    or v_deposit.organization_id is distinct from v_claim.organization_id
    or v_deposit.property_id is distinct from v_claim.property_id
    or v_deposit.room_id is distinct from p_room_id
    or v_deposit.occupancy_id is distinct from v_claim.occupancy_id
    or v_deposit.tenant_user_id is distinct from v_claim.tenant_user_id
    or v_deposit.status not in ('under_review','waiting_info') then
    raise exception 'workflow_wf07_damage_event_deposit_invalid'
      using errcode='22023';
  end if;

  insert into public.workflow_event_outbox_v2(
    organization_id,event_type,source_kind,source_id,event_key,
    property_id,room_id,occupancy_id,payload,actor_user_id,occurred_at
  ) values (
    p_organization_id,p_event_type,p_source_kind,p_source_id,p_event_key,
    p_property_id,p_room_id,p_occupancy_id,p_payload,p_actor_user_id,
    coalesce(p_occurred_at,now())
  )
  on conflict(organization_id,event_type,source_kind,source_id,event_key)
  do nothing
  returning id into v_event_id;

  if v_event_id is null then
    select id into v_event_id
    from public.workflow_event_outbox_v2
    where organization_id=p_organization_id
      and event_type=p_event_type
      and source_kind=p_source_kind
      and source_id=p_source_id
      and event_key=p_event_key;
  end if;

  return v_event_id;
end;
$wf07_enqueue$;

revoke all on function private.workflow_enqueue_event_v1(
  uuid,text,text,uuid,text,uuid,uuid,uuid,jsonb,uuid,timestamptz
) from public,anon,authenticated,service_role;

-- Autoría WF-07 sobre el contrato actual.
alter function private.workflow_sanitize_authoring_spec_v3(jsonb)
  rename to workflow_sanitize_authoring_spec_pre_wf07_v3;
revoke all on function private.workflow_sanitize_authoring_spec_pre_wf07_v3(jsonb)
  from public,anon,authenticated,service_role;

create function private.workflow_sanitize_authoring_spec_v3(p_spec jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $wf07_sanitize$
declare
  v_flow text:=coalesce(p_spec->>'flowType','');
  v_spec jsonb;
  v_amount_text text;
  v_amount bigint;
  v_currency text;
begin
  if v_flow='deposit_receipt' then
    v_amount_text:=btrim(coalesce(p_spec->>'depositAmountCents',''));
    v_currency:=upper(btrim(coalesce(p_spec->>'depositCurrency','EUR')));
    if v_amount_text !~ '^[0-9]+$' then
      raise exception 'workflow_wf07_deposit_amount_invalid' using errcode='22023';
    end if;
    v_amount:=v_amount_text::bigint;
    if v_amount<1 or v_amount>1000000000 then
      raise exception 'workflow_wf07_deposit_amount_invalid' using errcode='22023';
    end if;
    if v_currency !~ '^[A-Z]{3}$' then
      raise exception 'workflow_wf07_deposit_currency_invalid' using errcode='22023';
    end if;

    v_spec:=private.workflow_sanitize_authoring_spec_pre_wf07_v3(
      p_spec || jsonb_build_object(
        'flowType','rent_payment',
        'paymentConcept','Fianza',
        'paymentAmountCents',v_amount,
        'paymentCurrency',v_currency,
        'paymentDueDays',0
      )
    );
    return v_spec
      - 'paymentConcept' - 'paymentAmountCents' - 'paymentCurrency' - 'paymentDueDays'
      || jsonb_build_object(
        'flowType','deposit_receipt',
        'depositAmountCents',v_amount,
        'depositCurrency',v_currency
      );
  end if;

  if v_flow='deposit_review' then
    v_spec:=private.workflow_sanitize_authoring_spec_pre_wf07_v3(
      p_spec || jsonb_build_object(
        'flowType','checkout',
        'triggerType','event',
        'eventType','occupancy.offboarded'
      )
    );
    return v_spec || jsonb_build_object(
      'flowType','deposit_review',
      'eventType','occupancy.offboarded'
    );
  end if;

  if v_flow='damage_claim' then
    v_spec:=private.workflow_sanitize_authoring_spec_pre_wf07_v3(
      p_spec || jsonb_build_object(
        'flowType','rent_claim',
        'triggerType','event',
        'eventType','rent_claim.created'
      )
    );
    return v_spec || jsonb_build_object(
      'flowType','damage_claim',
      'eventType','damage_claim.created'
    );
  end if;

  return private.workflow_sanitize_authoring_spec_pre_wf07_v3(p_spec);
end;
$wf07_sanitize$;

revoke all on function private.workflow_sanitize_authoring_spec_v3(jsonb)
  from public,anon,authenticated,service_role;

alter function public.workflow_authoring_complete_v1(jsonb)
  rename to workflow_authoring_complete_pre_wf07_v1;
revoke all on function public.workflow_authoring_complete_pre_wf07_v1(jsonb)
  from public,anon,authenticated,service_role;

create function public.workflow_authoring_complete_v1(p_spec jsonb)
returns boolean
language plpgsql
immutable
security definer
set search_path=''
as $wf07_complete$
declare
  v_flow text:=coalesce(p_spec->>'flowType','');
  v_base jsonb;
  v_steps jsonb:=coalesce(p_spec->'steps','{}'::jsonb);
  v_evidence boolean:=
    coalesce((p_spec#>>'{steps,photo}')::boolean,false)
    or coalesce((p_spec#>>'{steps,checklist}')::boolean,false)
    or coalesce((p_spec#>>'{steps,document}')::boolean,false);
begin
  if v_flow='deposit_receipt' then
    v_base:=p_spec || jsonb_build_object(
      'flowType','rent_payment',
      'paymentConcept','Fianza',
      'paymentAmountCents',p_spec->>'depositAmountCents',
      'paymentCurrency',p_spec->>'depositCurrency',
      'paymentDueDays',0
    );
    if not public.workflow_authoring_complete_pre_wf07_v1(v_base) then
      return false;
    end if;
    return p_spec->>'scopeType'='occupancy'
      and p_spec->>'triggerType'='manual'
      and p_spec->>'assignmentType' in ('property_responsible','fixed_person','role')
      and (
        p_spec->>'assignmentType'<>'role'
        or p_spec->>'assignmentRole' in ('admin','employee')
      )
      and p_spec->>'closeType'='domain_adapter'
      and coalesce(p_spec->>'depositAmountCents','') ~ '^[0-9]+$'
      and (p_spec->>'depositAmountCents')::bigint between 1 and 1000000000
      and coalesce(p_spec->>'depositCurrency','') ~ '^[A-Z]{3}$';
  end if;

  if v_flow='deposit_review' then
    v_base:=p_spec || jsonb_build_object(
      'flowType','checkout',
      'triggerType','event',
      'eventType','occupancy.offboarded',
      'closeType','domain_adapter',
      'steps',jsonb_build_object(
        'accept',true,'photo',false,'checklist',false,'document',false
      )
    );
    if not public.workflow_authoring_complete_pre_wf07_v1(v_base) then
      return false;
    end if;
    return p_spec->>'triggerType'='event'
      and p_spec->>'eventType'='occupancy.offboarded'
      and p_spec->>'scopeType' in ('property','room')
      and p_spec->>'assignmentType' in ('property_responsible','fixed_person','role')
      and (
        p_spec->>'assignmentType'<>'role'
        or p_spec->>'assignmentRole' in ('admin','employee')
      )
      and p_spec->>'closeType'='domain_adapter'
      and coalesce((v_steps->>'accept')::boolean,false)=false
      and v_evidence;
  end if;

  if v_flow='damage_claim' then
    v_base:=p_spec || jsonb_build_object(
      'flowType','rent_claim',
      'triggerType','event',
      'eventType','rent_claim.created',
      'closeType','domain_adapter'
    );
    if not public.workflow_authoring_complete_pre_wf07_v1(v_base) then
      return false;
    end if;
    return p_spec->>'triggerType'='event'
      and p_spec->>'eventType'='damage_claim.created'
      and p_spec->>'scopeType' in ('property','room')
      and p_spec->>'assignmentType' in ('property_responsible','fixed_person','role')
      and (
        p_spec->>'assignmentType'<>'role'
        or p_spec->>'assignmentRole' in ('admin','employee')
      )
      and p_spec->>'closeType'='domain_adapter'
      and coalesce((v_steps->>'accept')::boolean,false)=false
      and v_evidence;
  end if;

  return public.workflow_authoring_complete_pre_wf07_v1(p_spec);
end;
$wf07_complete$;

revoke all on function public.workflow_authoring_complete_v1(jsonb)
  from public,anon,service_role;
grant execute on function public.workflow_authoring_complete_v1(jsonb)
  to authenticated;

comment on table public.security_deposits_v2 is
  'WF-07: expediente operativo de fianza por ocupación. No es ledger contable.';
comment on column public.workflow_executions_v2.security_deposit_id is
  'WF-07: fianza reutilizada por ejecuciones de recepción/revisión/daños.';
comment on column public.workflow_executions_v2.damage_claim_id is
  'WF-07: reclamación por daños enlazada uno-a-uno a su ejecución de gestión.';
