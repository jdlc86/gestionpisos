-- Tenant lifecycle: active, suspended, offboarding candidate, then verified purge.
alter table public.tenants_v2 add column if not exists deletion_requested_at timestamptz;
alter table public.tenants_v2 add column if not exists deletion_requested_by uuid references auth.users(id) on delete restrict;
alter table public.tenants_v2 add column if not exists deletion_note text;

create table if not exists public.tenant_privacy_events_v2 (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete restrict,
 tenant_id uuid,
 event_type text not null check(event_type in ('suspended','reactivated','offboarding_started','purged')),
 actor_user_id uuid references auth.users(id) on delete set null,
 recipient_email text,
 summary jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
alter table public.tenant_privacy_events_v2 enable row level security;
create policy tenant_privacy_events_root_select on public.tenant_privacy_events_v2 for select to authenticated using ((auth.jwt()->'app_metadata'->>'role')='root');
create policy tenant_privacy_events_admin_select on public.tenant_privacy_events_v2 for select to authenticated using ((auth.jwt()->'app_metadata'->>'role')='admin' and organization_id=(auth.jwt()->'app_metadata'->>'organization_id')::uuid);

comment on column public.tenants_v2.deletion_requested_at is 'Marks offboarding/deletion candidacy. Purge is a separate privileged workflow.';
comment on table public.tenant_privacy_events_v2 is 'Minimal non-documentary audit of tenant privacy lifecycle; must not contain identity documents.';
