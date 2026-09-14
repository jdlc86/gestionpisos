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
- 20260914064224 beta0_cleaning_swap_participant_read
- 20260914064231 beta0_cleaning_swap_write_policies
- 20260914064239 beta0_cleaning_swap_integrity
- 20260914064248 beta0_cleaning_swap_validation_trigger
- 20260914064258 beta0_cleaning_swap_decision_trigger
- 20260914064353 beta0_photo_verification_tables
- 20260914064402 beta0_photo_verification_rls
- 20260914064410 beta0_photo_verification_storage
- 20260914064421 beta0_photo_storage_org_scope
- 20260914074246 beta0_photo_verification_write_policies
- 20260914074301 beta0_photo_storage_read_org_hardening

The SQL for `20260913205141 close_owners_and_occupancy_blockers` is versioned at
`supabase/migrations/20260913205141_close_owners_and_occupancy_blockers.sql`.
The preceding remote entries are recorded here, but their SQL source files are
not present in this repository; this reproducibility debt remains open in
`docs/OPEN_BLOCKERS.md`.

The five B-08 migrations and four foundational B-10 migrations listed above
were recovered from the remote migration history's `statements` field and are
versioned with their exact remote timestamps and names. The two final B-10
policy migrations were generated locally, applied remotely and renamed to the
versions assigned by the remote history.

## Security status

After `20260914074301`, Supabase Security Advisor reports no critical findings.
One accepted notice remains:

- `Leaked Password Protection Disabled` (`WARN`), accepted for the current plan.

The Performance Advisor reports no critical findings. Its existing backlog is
22 unindexed foreign keys, 27 RLS init-plan warnings, 50 unused indexes (the
new exclusion index is unused because the active tables contain no rows), and
4 multiple-permissive-policy warnings.

Beta 0 is not stable until the full role-isolation matrix is executed with
users created through Supabase Auth.


## Photo alignment migrations — 2026-09-14

Applied remotely:
- 20260914135759 beta0_photo_alignment_meta
- 20260914135829 beta0_photo_alignment_meta_check_add

Reconciliation status:
- 20260914135759 is versioned in Git.
- 20260914135829 exists remotely; its exact SQL file is still blocked by the tool layer when written to Git.
- The restrictive storage-path policy is not applied yet.
- Run finalization is not applied yet.

Do not consider photo-capture persistence closed until remote and Git are fully reconciled.


## Photo capture persistence — retry 2026-09-14

Applied remotely:
- 20260914140530 beta0_photo_item_storage_path_restrictive_min
- 20260914140615 beta0_submit_photo_verification_run_fn

The restrictive INSERT policy now forces the deterministic item path:
`organization_id/run_id/item_id.jpg`.

The run-finalization function exists remotely and verifies:
- authenticated identity via `auth.uid()`;
- actor ownership of the run;
- matching item;
- run status `capturing`;
- existence of the object in the private `photo-verification` bucket;
- object ownership by the same actor.

IMPORTANT: the attempted permission hardening for this SECURITY DEFINER function
was intercepted before reaching Supabase. Security Advisor currently reports:
- anon_security_definer_function_executable;
- authenticated_security_definer_function_executable.

Therefore the function must NOT be considered security-closed yet. Do not wire
the production frontend to this RPC until its EXECUTE privileges are narrowed
or the design is replaced by an equivalent non-warning implementation.

Git reconciliation also remains incomplete for some SQL files because writing
their exact contents was intercepted by the tool layer.
