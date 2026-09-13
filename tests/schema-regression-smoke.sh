#!/usr/bin/env bash
set -euo pipefail

migration="supabase/migrations/20260913205141_close_owners_and_occupancy_blockers.sql"
test_sql="tests/database-regression.sql"

test -s "$migration"
test -s "$test_sql"
test -s tests/database-regression.sh
test -s tests/local-schema-fixture.sql

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

echo 'Schema regression smoke checks passed'
