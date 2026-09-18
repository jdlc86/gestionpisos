create table if not exists public.platform_operators (
  user_id uuid primary key references auth.users(id) on delete restrict,
  display_name text not null,
  active boolean not null default true,
  can_recover_root boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  check (char_length(trim(display_name)) between 2 and 120)
);

alter table public.platform_operators enable row level security;

revoke all on table public.platform_operators from public, anon, authenticated;

do $$ begin
  create index platform_operators_active_idx
    on public.platform_operators (active)
    where active = true;
exception when duplicate_table then null;
end $$;

comment on table public.platform_operators is
  'Allaiso platform operators authorized for emergency operations. No direct client access; service-role backend only.';
