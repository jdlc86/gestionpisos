
create table if not exists public.notifications_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  recipient_user_id uuid not null references auth.users(id),
  event_type text not null,
  title text not null,
  body text not null,
  status text not null default 'pending'
    check (status in ('pending','sent','read','failed','cancelled')),
  channel_in_app boolean not null default true,
  channel_email boolean not null default false,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  read_at timestamptz
);

create table if not exists public.broadcasts_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  property_id uuid references public.properties_v2(id),
  created_by uuid not null references auth.users(id),
  audience text not null
    check (audience in ('all','property','owners','employees','tenants')),
  title text not null,
  body text not null,
  status text not null default 'draft'
    check (status in ('draft','scheduled','sending','sent','cancelled','failed')),
  scheduled_for timestamptz,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

alter table public.notifications_v2 enable row level security;
alter table public.broadcasts_v2 enable row level security;

create index if not exists notifications_recipient_idx
  on public.notifications_v2(recipient_user_id,status,created_at desc);

create index if not exists broadcasts_org_idx
  on public.broadcasts_v2(organization_id,status,scheduled_for);
