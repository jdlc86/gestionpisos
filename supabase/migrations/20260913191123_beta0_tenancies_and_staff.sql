
create table public.tenancies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  property_id uuid not null references public.properties(id) on delete restrict,
  room_id uuid not null references public.rooms(id) on delete restrict,
  user_id uuid references auth.users(id) on delete restrict,
  tenant_email text not null,
  starts_on date not null,
  ends_on date,
  status public.record_status not null default 'active',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  check (ends_on is null or ends_on >= starts_on)
);

create table public.property_staff_assignments (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete restrict,
  employee_user_id uuid not null references auth.users(id) on delete restrict,
  assignment_type text not null check (assignment_type in ('responsible','delegate','reader')),
  can_write boolean not null default false,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  granted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
