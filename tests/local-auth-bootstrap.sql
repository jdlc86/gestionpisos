-- Local-only PostgreSQL auth emulation for isolated regression.
-- Application schema must come from tests/fixtures/20260913_remote_baseline.sql.

create schema auth;
create schema extensions;

create extension pgcrypto with schema extensions;

create role anon nologin;
create role authenticated nologin;
create role service_role nologin;

create table auth.users (
  id uuid primary key
);

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

grant usage on schema auth, public to authenticated, service_role;
grant execute on function auth.jwt(), auth.uid() to authenticated;
