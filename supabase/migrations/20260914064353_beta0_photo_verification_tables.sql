
create table if not exists public.verification_policies_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  property_id uuid not null references public.properties_v2(id),
  user_id uuid references auth.users(id),
  verification_mode text not null default 'manual'
    check (verification_mode in ('manual','ai','hybrid')),
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.photo_patterns_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  property_id uuid not null references public.properties_v2(id),
  name text not null,
  target_type text not null
    check (target_type in ('cleaning','zone','equipment','inspection')),
  target_key text,
  reference_storage_path text not null,
  silhouette_storage_path text,
  contour_data jsonb,
  version integer not null default 1 check (version > 0),
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  retired_at timestamptz
);

create table if not exists public.photo_verification_runs_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  property_id uuid not null references public.properties_v2(id),
  room_id uuid references public.rooms_v2(id),
  actor_user_id uuid not null references auth.users(id),
  source_type text not null
    check (source_type in ('cleaning_task','inspection','random_request','manual')),
  source_id uuid,
  verification_mode text not null
    check (verification_mode in ('manual','ai','hybrid')),
  status text not null default 'capturing'
    check (status in ('capturing','submitted','ai_review','manual_review','approved','rejected','cancelled')),
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id),
  rejection_reason text
);

create table if not exists public.photo_verification_items_v2 (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.photo_verification_runs_v2(id),
  pattern_id uuid not null references public.photo_patterns_v2(id),
  storage_path text not null,
  captured_at timestamptz not null default now(),
  alignment_score numeric(5,4)
    check (alignment_score is null or (alignment_score >= 0 and alignment_score <= 1)),
  ai_score numeric(5,4)
    check (ai_score is null or (ai_score >= 0 and ai_score <= 1)),
  ai_result text
    check (ai_result is null or ai_result in ('pass','fail','uncertain')),
  manual_result text
    check (manual_result is null or manual_result in ('approved','rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz
);

create table if not exists public.random_photo_requests_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  property_id uuid not null references public.properties_v2(id),
  assigned_user_id uuid not null references auth.users(id),
  pattern_id uuid not null references public.photo_patterns_v2(id),
  status text not null default 'pending'
    check (status in ('pending','opened','submitted','approved','rejected','expired','cancelled')),
  requested_by uuid references auth.users(id),
  requested_at timestamptz not null default now(),
  due_at timestamptz,
  completed_run_id uuid references public.photo_verification_runs_v2(id)
);

alter table public.verification_policies_v2 enable row level security;
alter table public.photo_patterns_v2 enable row level security;
alter table public.photo_verification_runs_v2 enable row level security;
alter table public.photo_verification_items_v2 enable row level security;
alter table public.random_photo_requests_v2 enable row level security;
