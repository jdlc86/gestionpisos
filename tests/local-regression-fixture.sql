-- Test-only seed data. No production identifiers or data are copied.

insert into public.organizations (id, name)
values (gen_random_uuid(), 'Allaiso')
returning id gset allaiso_

insert into auth.users (id)
values (gen_random_uuid())
returning id gset root_

insert into public.user_roles (user_id, organization_id, role)
values (:'root_id', :'allaiso_id', 'root');
