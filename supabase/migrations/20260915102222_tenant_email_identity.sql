-- Canonical tenant email identity inside an organization.
-- Preflight prevents silently collapsing existing conflicting identities.
do $$
begin
  if exists (
    select 1 from public.tenants_v2
    group by organization_id, lower(btrim(email))
    having count(*) > 1
  ) then
    raise exception 'Duplicate tenant emails exist; review before applying unique identity constraint';
  end if;
end $$;

create unique index if not exists tenants_v2_org_email_uidx
on public.tenants_v2 (organization_id, lower(btrim(email)));

comment on index public.tenants_v2_org_email_uidx is
'One tenant identity per normalized email within each organization.';

-- Legacy occupancies predate tenants_v2. Do not delete historical rows automatically:
-- hide them from the new tenant UI until explicitly migrated or purged with verified scope.
