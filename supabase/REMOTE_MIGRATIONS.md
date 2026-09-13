# Supabase remote migration history

Project: `qsxtmmkftsohkqqmytbb`

This file records migrations already applied remotely during Beta 0 bootstrap.

## Active model

Application code must target:
- organizations
- profiles
- user_roles
- owners
- properties_v2
- rooms_v2
- occupancies_v2
- property_staff_access_v3
- property_qr_tokens
- access_requests
- admin_capability_holders
- admin_capability_requests
- audit_log_v2

Legacy bootstrap tables `properties`, `rooms`, `tenancies`, `property_staff_assignments` and `property_staff_access_v2` must not receive new application data.

## Applied migrations

- 20260913191109 beta0_core_entities
- 20260913191123 beta0_tenancies_and_staff
- 20260913191136 beta0_enable_rls
- 20260913191143 beta0_protect_root
- 20260913191216 beta0_foreign_key_indexes
- 20260913191234 beta0_identity_read_policies
- 20260913191243 beta0_resource_read_policies
- 20260913191257 beta0_staff_org_scope
- 20260913191826 beta0_create_staff_access_v2
- 20260913191833 beta0_enable_staff_access_v2_rls
- 20260913191836 beta0_staff_access_v2_employee_read
- 20260913191842 beta0_staff_access_v2_admin_read
- 20260913191849 beta0_create_properties_v2
- 20260913191914 beta0_qr_tokens
- 20260913191920 beta0_access_requests
- 20260913191930 beta0_rooms_v2
- 20260913192154 beta0_occupancies_v2
- 20260913192729 beta0_enable_occupancies_v2_rls
- 20260913192741 beta0_occupancies_v2_relations
- 20260913192752 beta0_property_staff_access_v3
- 20260913192810 beta0_property_staff_access_v3_policies
- 20260913192821 beta0_occupancies_v2_read_policies
- 20260913192825 beta0_properties_v2_read_policies
- 20260913192843 beta0_rooms_v2_read_policy
- 20260913192859 beta0_rooms_v2_write_policies
- 20260913192914 beta0_access_requests_read_update
- 20260913192921 beta0_qr_admin_policies
- 20260913192933 beta0_v2_v3_indexes
- 20260913192943 beta0_admin_capability_control
- 20260913192948 beta0_admin_capability_read_policies
- 20260913193123 beta0_properties_v2_write_policies
- 20260913193138 beta0_audit_and_capability_transfer
- 20260913193156 beta0_occupancies_v2_write_policies
- 20260913193201 beta0_admin_audit_indexes
- 20260913200133 beta0_create_allaiso_organization
- 20260913202214 portfolio_channel_probe
- 20260913202901 beta0_incidents
- 20260913202908 beta0_incidents_rls
- 20260913203106 beta0_cleaning_core
- 20260913203112 beta0_cleaning_admin_rls
- 20260913205141 close_owners_and_occupancy_blockers

The SQL for `20260913205141 close_owners_and_occupancy_blockers` is versioned at
`supabase/migrations/20260913205141_close_owners_and_occupancy_blockers.sql`.
The preceding remote entries are recorded here, but their SQL source files are
not present in this repository; this reproducibility debt remains open in
`docs/OPEN_BLOCKERS.md`.

## Security status

After `20260913205141`, Supabase Security Advisor reports no critical findings.
Two pre-existing notices remain:

- `Leaked Password Protection Disabled` (`WARN`), accepted for the current plan;
- `cleaning_swap_requests_v2` has RLS enabled with no policy (`INFO`), safely
  deny-by-default but incomplete for the future tenant swap flow.

The Performance Advisor reports no critical findings. Its existing backlog is
22 unindexed foreign keys, 27 RLS init-plan warnings, 50 unused indexes (the
new exclusion index is unused because the active tables contain no rows), and
4 multiple-permissive-policy warnings.

Beta 0 is not stable until the full role-isolation matrix is executed with
users created through Supabase Auth.
