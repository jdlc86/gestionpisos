alter table public.property_staff_access_v3
  drop constraint if exists property_staff_access_v3_assignment_type_check;

alter table public.property_staff_access_v3
  add constraint property_staff_access_v3_assignment_type_check
  check (assignment_type in ('responsible','access','delegate','reader'));

comment on constraint property_staff_access_v3_assignment_type_check
  on public.property_staff_access_v3
  is 'V3 canonical assignments are responsible/access; delegate/reader remain accepted for backward compatibility with earlier schema.';
