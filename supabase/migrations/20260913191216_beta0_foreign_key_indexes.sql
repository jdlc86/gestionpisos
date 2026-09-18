
create index owners_organization_idx on public.owners(organization_id);
create index owners_user_idx on public.owners(user_id);
create index profiles_organization_idx on public.profiles(organization_id);
create index properties_organization_idx on public.properties(organization_id);
create index properties_owner_idx on public.properties(owner_id);
create index property_staff_property_idx on public.property_staff_assignments(property_id);
create index property_staff_employee_idx on public.property_staff_assignments(employee_user_id);
create index property_staff_granted_by_idx on public.property_staff_assignments(granted_by);
create index tenancies_organization_idx on public.tenancies(organization_id);
create index tenancies_property_idx on public.tenancies(property_id);
create index tenancies_room_idx on public.tenancies(room_id);
create index tenancies_user_idx on public.tenancies(user_id);
create index tenancies_created_by_idx on public.tenancies(created_by);
create index user_roles_organization_idx on public.user_roles(organization_id);
create index user_roles_created_by_idx on public.user_roles(created_by);
