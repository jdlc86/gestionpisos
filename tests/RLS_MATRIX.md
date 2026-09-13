# Beta 0 RLS isolation matrix

These tests are mandatory before Beta 0 can be declared stable.

Test identities must be created through Supabase Auth. Never seed `auth.users` with direct SQL.

## Fixtures

Create two organizations, two properties and the following test identities:

- ROOT
- ADMIN_A holder of `property_lifecycle`
- ADMIN_A_2 without the capability
- ADMIN_B
- EMPLOYEE_A responsible/write on PROPERTY_A
- EMPLOYEE_A_READER read-only on PROPERTY_A
- EMPLOYEE_B assigned to PROPERTY_B
- OWNER_A owner of PROPERTY_A
- OWNER_B owner of PROPERTY_B
- TENANT_A active occupant of ROOM_A / PROPERTY_A
- TENANT_B active occupant of ROOM_B / PROPERTY_B

## Required positive tests

- ROOT reads both organizations and both properties.
- ADMIN_A reads organization A and PROPERTY_A.
- ADMIN_A holder can create/update PROPERTY_A.
- EMPLOYEE_A reads PROPERTY_A and its rooms.
- EMPLOYEE_A with can_write=true can update allowed operational room data.
- OWNER_A reads PROPERTY_A.
- TENANT_A reads PROPERTY_A, ROOM_A and own active occupancy.
- ADMIN can read access requests for its organization.
- Current capability holder can approve a pending transfer request.

## Required negative tests

- ADMIN_A cannot read organization B data.
- ADMIN_A_2 cannot create/update a property without `property_lifecycle`.
- EMPLOYEE_A cannot read PROPERTY_B.
- EMPLOYEE_A_READER cannot write PROPERTY_A.
- EMPLOYEE_B cannot read or modify PROPERTY_A.
- OWNER_A cannot read PROPERTY_B.
- TENANT_A cannot read PROPERTY_B or TENANT_B occupancy.
- Tenant cannot approve its own access request.
- Tenant cannot read raw QR token rows.
- Revoked/expired staff assignment does not grant access.
- Expired occupancy does not grant tenant property access.
- Non-holder ADMIN cannot approve capability transfer.
- ADMIN cannot mutate ROOT.
- Client cannot write audit rows for privileged operations.

## Exit criteria

All positive tests pass and all negative tests are denied at database/API level, not merely hidden in the UI.

After tests:
- run Security Advisor;
- review Performance Advisor;
- document failures/fixes;
- update STABLE_RELEASE.md only when all critical checks are green.

## Automated targeted regression

`tests/database-regression.sql` covers the targeted B-01/B-02 and ROOT guard
cases without creating Auth users. It is executed against the faithful,
ephemeral PostgreSQL fixture in `tests/local-schema-fixture.sql` and rolls back
all test rows.

Covered positive cases:

- ROOT creates and archives an owner;
- ADMIN creates and updates an owner in its organization;
- a non-overlapping active occupancy is accepted.

Covered negative cases:

- owner, employee and tenant cannot create or update owners;
- ADMIN cannot write an owner in another organization;
- authenticated clients, including ROOT, cannot physically delete owners;
- a second open occupancy for one room is rejected;
- overlapping dated occupancies and inverted dates are rejected;
- the ROOT role cannot be changed through an ordinary update.

This targeted regression does not replace the full matrix above with real
Supabase Auth identities.
