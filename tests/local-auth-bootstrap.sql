-- Local-only PostgreSQL auth emulation for isolated regression.
-- Application schema must come from tests/fixtures/20260913_remote_baseline.sql.

create schema auth;
create schema extensions;
create schema storage;

create extension pgcrypto with schema extensions;

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

create table auth.users (
  id uuid primary key
);

create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);

create table storage.objects (
  id uuid primary key default extensions.gen_random_uuid(),
  bucket_id text not null,
  name text not null,
  owner_id text,
  unique(bucket_id,name)
);

alter table storage.objects enable row level security;

-- Minimal Supabase Storage helper needed by historical storage policies.
-- The regression harness only needs folder segment resolution; production
-- provides this function natively through the Storage schema.
create function storage.foldername(name text)
returns text[]
language sql
immutable
as $foldername$
  select string_to_array(name, '/');
$foldername$;

create function auth.jwt()
returns jsonb
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb,
    '{}'::jsonb
  );
$$;

create function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid;
$$;

grant usage on schema auth, public, storage to authenticated, service_role;
grant execute on function auth.jwt(), auth.uid() to authenticated;
