
create table if not exists public.payment_obligations_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  property_id uuid not null references public.properties_v2(id),
  room_id uuid references public.rooms_v2(id),
  tenant_user_id uuid references auth.users(id),
  concept text not null,
  amount_cents bigint,
  currency text not null default 'EUR',
  due_date date not null,
  status text not null default 'pending'
    check (status in ('pending','paid','overdue','waived','cancelled')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create table if not exists public.reminder_rules_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  property_id uuid references public.properties_v2(id),
  event_type text not null
    check (event_type in ('payment_due','payment_overdue','custom')),
  days_offset integer not null default 0,
  channel_in_app boolean not null default true,
  channel_email boolean not null default true,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.claims_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  property_id uuid not null references public.properties_v2(id),
  tenant_user_id uuid references auth.users(id),
  obligation_id uuid references public.payment_obligations_v2(id),
  claim_type text not null
    check (claim_type in ('payment','conduct','documentation','other')),
  title text not null,
  body text not null,
  status text not null default 'draft'
    check (status in ('draft','scheduled','sent','acknowledged','resolved','cancelled')),
  scheduled_for timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  resolved_at timestamptz
);

alter table public.payment_obligations_v2 enable row level security;
alter table public.reminder_rules_v2 enable row level security;
alter table public.claims_v2 enable row level security;

create index if not exists payment_obligations_tenant_due_idx
  on public.payment_obligations_v2(tenant_user_id,status,due_date);

create index if not exists payment_obligations_property_idx
  on public.payment_obligations_v2(property_id,status,due_date);

create index if not exists reminder_rules_org_event_idx
  on public.reminder_rules_v2(organization_id,event_type,active);

create index if not exists claims_tenant_status_idx
  on public.claims_v2(tenant_user_id,status,created_at desc);
