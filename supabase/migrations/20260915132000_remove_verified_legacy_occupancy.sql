-- Remove the verified legacy test occupancy that predates tenants_v2.
delete from public.occupancies_v2
where id = '85b5ced7-c133-42d0-8499-2eab75c6ca73'
  and tenant_id is null
  and starts_on = date '2026-09-16'
  and ends_on = date '2027-02-27'
  and status = 'active';
