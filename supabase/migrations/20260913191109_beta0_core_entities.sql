
create extension if not exists pgcrypto;

create type public.app_role as enum ('root','admin','owner','employee','tenant');
create type public.record_status as enum ('active','blocked','archived');
create type public.property_status as enum ('onboarding','active','maintenance','blocked','offboarding','archived');
create type public.access_request_status as enum ('pending','approved','rejected','cancelled');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete restrict,
  organization_id uuid references public.organizations(id) on delete restrict,
  display_name text,
  email text,
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  organization_id uuid references public.organizations(id) on delete restrict,
  role public.app_role not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique(user_id, organization_id, role)
);

create table public.owners (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid references auth.users(id) on delete set null,
  full_name text not null,
  email text,
  phone text,
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

create table public.properties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  owner_id uuid not null references public.owners(id) on delete restrict,
  name text not null,
  address_line text not null,
  city text,
  postal_code text,
  country_code text not null default 'ES',
  status public.property_status not null default 'onboarding',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete restrict,
  label text not null,
  description text,
  status public.record_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique(property_id, label)
);
