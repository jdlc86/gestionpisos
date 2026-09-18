#!/usr/bin/env bash
set -euo pipefail

migration="supabase/migrations/20260916001312_unify_admin_write_control.sql"
override_migration="supabase/migrations/20260916002605_root_write_control_override.sql"
test -s "$migration"
test -s "$override_migration"
grep -Fq "'property_lifecycle','permission_management','write_control'" "$migration"
grep -Fq "'property_lifecycle','write_control'" "$migration"
grep -Fq "h.capability='write_control'" "$migration"
grep -Fq 'create or replace function public.assign_initial_admin_write_control' "$migration"
grep -Fq "raise exception 'root_required'" "$migration"
grep -Fq "raise exception 'target_admin_required'" "$migration"
grep -Fq "raise exception 'write_control_already_assigned'" "$migration"
grep -Fq "'assign_initial_admin_write_control'" "$migration"
grep -Fq 'revoke all on function public.assign_initial_admin_write_control' "$migration"
grep -Fq 'grant execute on function public.assign_initial_admin_write_control' "$migration"

grep -Fq 'create or replace function public.root_set_admin_write_control' "$override_migration"
grep -Fq "raise exception 'root_required'" "$override_migration"
grep -Fq "raise exception 'target_admin_required'" "$override_migration"
grep -Fq "'root_revoke_admin_write_control'" "$override_migration"
grep -Fq "'root_transfer_admin_write_control'" "$override_migration"
grep -Fq "capability='write_control'" "$override_migration"
grep -Fq 'revoke all on function public.root_set_admin_write_control' "$override_migration"
grep -Fq 'grant execute on function public.root_set_admin_write_control' "$override_migration"

echo 'Administrative write control schema contract passed'
