-- Test-only deterministic seed data. No production identifiers are copied.

insert into public.organizations (id, name)
values ('11111111-1111-4111-8111-111111111111', 'Allaiso');

insert into auth.users (id)
values ('22222222-2222-4222-8222-222222222222');

insert into public.user_roles (user_id, organization_id, role)
values (
  '22222222-2222-4222-8222-222222222222',
  '11111111-1111-4111-8111-111111111111',
  'root'
);
