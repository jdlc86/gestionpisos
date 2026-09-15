-- Separate tenant identity from occupancy history.
create table if not exists public.tenants_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  full_name text not null check (length(btrim(full_name)) >= 2),
  document_type text not null check (document_type in ('dni','nie','passport','other')),
  document_number text not null check (length(btrim(document_number)) >= 3),
  email text not null,
  status public.record_status not null default 'active',
  user_id uuid null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz null,
  unique (organization_id, document_type, document_number)
);

alter table public.occupancies_v2 add column if not exists tenant_id uuid null references public.tenants_v2(id) on delete restrict;

-- Backward-compatible: existing occupancy rows may remain without tenant_id.
create index if not exists tenants_v2_org_status_idx on public.tenants_v2(organization_id,status);
create index if not exists occupancies_v2_tenant_idx on public.occupancies_v2(tenant_id);

alter table public.tenants_v2 enable row level security;

create policy tenants_v2_root_all on public.tenants_v2 for all to authenticated
using ((auth.jwt()->'app_metadata'->>'role')='root')
with check ((auth.jwt()->'app_metadata'->>'role')='root');

create policy tenants_v2_admin_org_all on public.tenants_v2 for all to authenticated
using ((auth.jwt()->'app_metadata'->>'role')='admin' and organization_id=(auth.jwt()->'app_metadata'->>'organization_id')::uuid)
with check ((auth.jwt()->'app_metadata'->>'role')='admin' and organization_id=(auth.jwt()->'app_metadata'->>'organization_id')::uuid);

comment on table public.tenants_v2 is 'Tenant identity independent from occupancy history and authentication account.';
comment on column public.occupancies_v2.tenant_id is 'Tenant identity for this occupancy; nullable for legacy rows.';
