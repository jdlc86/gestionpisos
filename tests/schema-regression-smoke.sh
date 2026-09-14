#!/usr/bin/env bash
set -euo pipefail

migration="supabase/migrations/20260913205141_close_owners_and_occupancy_blockers.sql"
test_sql="tests/database-regression.sql"
photo_migration="supabase/migrations/20260914074246_beta0_photo_verification_write_policies.sql"
storage_migration="supabase/migrations/20260914074301_beta0_photo_storage_read_org_hardening.sql"
photo_test_sql="tests/photo-verification-regression.sql"

test -s "$migration"
test -s "$test_sql"
test -s tests/database-regression.sh
test -s tests/local-schema-fixture.sql
test -s "$photo_migration"
test -s "$storage_migration"
test -s "$photo_test_sql"

for historical_migration in \
  supabase/migrations/20260914064224_beta0_cleaning_swap_participant_read.sql \
  supabase/migrations/20260914064231_beta0_cleaning_swap_write_policies.sql \
  supabase/migrations/20260914064239_beta0_cleaning_swap_integrity.sql \
  supabase/migrations/20260914064248_beta0_cleaning_swap_validation_trigger.sql \
  supabase/migrations/20260914064258_beta0_cleaning_swap_decision_trigger.sql \
  supabase/migrations/20260914064353_beta0_photo_verification_tables.sql \
  supabase/migrations/20260914064402_beta0_photo_verification_rls.sql \
  supabase/migrations/20260914064410_beta0_photo_verification_storage.sql \
  supabase/migrations/20260914064421_beta0_photo_storage_org_scope.sql
do
  test -s "$historical_migration"
done

grep -q 'owners_insert_root_admin' "$migration"
grep -q 'owners_update_root_admin' "$migration"
grep -q 'trg_audit_owner_change' "$migration"
grep -q 'revoke delete on table public.owners from authenticated' "$migration"
grep -q 'owners_archive_state_check' "$migration"
grep -q 'occupancies_v2_dates_check' "$migration"
grep -q 'occupancies_v2_no_active_room_overlap' "$migration"
grep -q 'exclude using gist' "$migration"

grep -q 'second open active occupancy unexpectedly succeeded' "$test_sql"
grep -q 'cross-organization ADMIN insert unexpectedly succeeded' "$test_sql"
grep -q 'ROOT role mutation unexpectedly succeeded' "$test_sql"

grep -q 'verification_policies_root_admin_insert' "$photo_migration"
grep -q 'photo_patterns_root_admin_update' "$photo_migration"
grep -q 'photo_items_actor_insert' "$photo_migration"
grep -q 'random_photo_requests_root_admin_update' "$photo_migration"
! grep -q 'for delete to authenticated' "$photo_migration"
grep -q "storage.foldername(name)" "$storage_migration"
grep -q 'cross-organization ADMIN pattern insert unexpectedly succeeded' "$photo_test_sql"
grep -q 'assigned user random request insert unexpectedly succeeded' "$photo_test_sql"
grep -q 'actor insert into another run unexpectedly succeeded' "$photo_test_sql"

echo 'Schema regression smoke checks passed'
