create table if not exists public.incidents_v2 (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    property_id uuid not null references public.properties_v2(id),
    room_id uuid references public.rooms_v2(id),
    created_by uuid not null references auth.users(id),
    assigned_to uuid references auth.users(id),
    category text not null,
    description text not null,
    priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
    status text not null default 'reported' check (status in ('reported','triaged','assigned','in_progress','resolved','closed','rejected','reopened')),
    rejection_reason text,
    resolved_at timestamptz,
    closed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );

  create table if not exists public.incident_updates_v2 (
    id uuid primary key default gen_random_uuid(),
    incident_id uuid not null references public.incidents_v2(id),
    author_user_id uuid not null references auth.users(id),
    visibility text not null check (visibility in ('tenant','internal','owner')),
    body text not null,
    created_at timestamptz not null default now()
  );

  create table if not exists public.incident_evidence_v2 (
    id uuid primary key default gen_random_uuid(),
    incident_id uuid not null references public.incidents_v2(id),
    uploaded_by uuid not null references auth.users(id),
    visibility text not null default 'internal' check (visibility in ('tenant','internal','owner')),
    evidence_type text not null default 'photo',
    storage_path text not null,
    content_sha256 text,
    created_at timestamptz not null default now()
  );

  create index if not exists incidents_v2_property_status_idx on public.incidents_v2(property_id,status);
  create index if not exists incident_updates_v2_incident_idx on public.incident_updates_v2(incident_id,created_at);
  create index if not exists incident_evidence_v2_incident_idx on public.incident_evidence_v2(incident_id,created_at);

  alter table public.incidents_v2 enable row level security;
  alter table public.incident_updates_v2 enable row level security;
  alter table public.incident_evidence_v2 enable row level security;
