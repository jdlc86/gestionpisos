
create table public.admin_capability_holders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  capability text not null check (capability in ('property_lifecycle')),
  holder_user_id uuid not null references auth.users(id) on delete restrict,
  granted_by uuid references auth.users(id) on delete set null,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (organization_id, capability)
);

create table public.admin_capability_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  capability text not null check (capability in ('property_lifecycle')),
  requester_user_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references auth.users(id) on delete set null
);

alter table public.admin_capability_holders enable row level security;
alter table public.admin_capability_requests enable row level security;

create index admin_capability_holders_org_idx on public.admin_capability_holders(organization_id);
create index admin_capability_holders_holder_idx on public.admin_capability_holders(holder_user_id);
create index admin_capability_requests_org_idx on public.admin_capability_requests(organization_id);
create index admin_capability_requests_requester_idx on public.admin_capability_requests(requester_user_id);
