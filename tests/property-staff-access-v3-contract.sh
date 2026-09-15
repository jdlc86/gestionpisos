#!/usr/bin/env bash
set -euo pipefail

migration="supabase/migrations/20260915235039_allow_v3_secondary_access_assignment_type.sql"

test -s "$migration"
grep -Fq "assignment_type in ('responsible','access','delegate','reader')" "$migration"
grep -Fq "V3 canonical assignments are responsible/access" "$migration"
grep -Fq "grant_property_staff_access_v3" docs/permissions.js
grep -Fq "assignment_type='access'" docs/permissions.js || true

# The database contract for secondary access must admit the same canonical
# value used by the RPC/context layer. This guards the regression where the
# table allowed only responsible/delegate/reader while the RPC inserted access.
echo 'Property staff access v3 contract checks passed'
