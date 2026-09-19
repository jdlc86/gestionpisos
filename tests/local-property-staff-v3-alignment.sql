-- Test-only: alinea el snapshot local antiguo de property_staff_access_v3
-- con las columnas canónicas que ya existen en producción.

alter table public.property_staff_access_v3
  add column if not exists organization_id uuid references public.organizations(id) on delete restrict,
  add column if not exists assignment_type text,
  add column if not exists can_write boolean not null default false,
  add column if not exists valid_from timestamptz not null default now(),
  add column if not exists granted_by uuid references auth.users(id) on delete set null,
  add column if not exists created_at timestamptz not null default now();

update public.property_staff_access_v3 a
set organization_id=p.organization_id
from public.properties_v2 p
where p.id=a.property_id
  and a.organization_id is null;

update public.property_staff_access_v3
set assignment_type='access'
where assignment_type is null;

alter table public.property_staff_access_v3
  alter column organization_id set not null,
  alter column assignment_type set not null;

alter table public.property_staff_access_v3
  drop constraint if exists property_staff_access_v3_assignment_type_check;

alter table public.property_staff_access_v3
  add constraint property_staff_access_v3_assignment_type_check
  check (assignment_type in ('responsible','access','delegate','reader'));

create unique index if not exists property_staff_access_v3_one_current_responsible_per_property
  on public.property_staff_access_v3(property_id)
  where assignment_type='responsible' and revoked_at is null;
