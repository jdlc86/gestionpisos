create table if not exists public.cleaning_plans_v2 (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    property_id uuid not null references public.properties_v2(id),
    name text not null,
    cadence text not null default 'weekly',
    active boolean not null default true,
    created_by uuid references auth.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );

  create table if not exists public.cleaning_tasks_v2 (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    property_id uuid not null references public.properties_v2(id),
    room_id uuid references public.rooms_v2(id),
    plan_id uuid references public.cleaning_plans_v2(id),
    assigned_user_id uuid references auth.users(id),
    task_date date not null,
    status text not null default 'pending' check (status in ('pending','accepted','in_progress','submitted','approved','rejected','swapped','missed','cancelled')),
    verification_mode text not null default 'manual' check (verification_mode in ('manual','ai','hybrid')),
    submitted_at timestamptz,
    reviewed_at timestamptz,
    reviewed_by uuid references auth.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
  );

  create table if not exists public.cleaning_swap_requests_v2 (
    id uuid primary key default gen_random_uuid(),
    cleaning_task_id uuid not null references public.cleaning_tasks_v2(id),
    requester_user_id uuid not null references auth.users(id),
    target_user_id uuid not null references auth.users(id),
    status text not null default 'pending' check (status in ('pending','accepted','rejected','cancelled')),
    requested_at timestamptz not null default now(),
    decided_at timestamptz
  );

  create table if not exists public.cleaning_debts_v2 (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organizations(id),
    property_id uuid not null references public.properties_v2(id),
    debtor_user_id uuid not null references auth.users(id),
    creditor_user_id uuid not null references auth.users(id),
    source_task_id uuid references public.cleaning_tasks_v2(id),
    amount integer not null default 1 check (amount > 0),
    status text not null default 'open' check (status in ('open','settled','cancelled')),
    created_at timestamptz not null default now(),
    settled_at timestamptz
  );

  alter table public.cleaning_plans_v2 enable row level security;
  alter table public.cleaning_tasks_v2 enable row level security;
  alter table public.cleaning_swap_requests_v2 enable row level security;
  alter table public.cleaning_debts_v2 enable row level security;

  create index if not exists cleaning_tasks_property_date_idx on public.cleaning_tasks_v2(property_id,task_date);
  create index if not exists cleaning_tasks_assignee_idx on public.cleaning_tasks_v2(assigned_user_id,status);
  create index if not exists cleaning_swaps_task_idx on public.cleaning_swap_requests_v2(cleaning_task_id,status);
  create index if not exists cleaning_debts_debtor_idx on public.cleaning_debts_v2(debtor_user_id,status);
  create index if not exists cleaning_debts_creditor_idx on public.cleaning_debts_v2(creditor_user_id,status);
