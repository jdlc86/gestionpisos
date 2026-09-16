#!/usr/bin/env bash
set -euo pipefail

migration='supabase/migrations/20260916115000_responsibility_resolution.sql'
test -s "$migration"

grep -Fq 'create or replace function public.assign_property_responsible_v3' "$migration"
grep -Fq 'if p_employee_user_id is null then' "$migration"
grep -Fq "'unassign_property_responsible'" "$migration"
grep -Fq 'create or replace function public.deactivate_internal_staff_user_v2' "$migration"
grep -Fq "p_responsibility_mode text default 'block'" "$migration"
grep -Fq "p_responsibility_mode not in ('block','unassign','reassign')" "$migration"
grep -Fq "'resolve_staff_responsibilities_for_deactivation'" "$migration"
grep -Fq 'v_result:=public.deactivate_internal_staff_user' "$migration"
grep -Fq 'grant execute on function public.deactivate_internal_staff_user_v2' "$migration"
grep -Fq 'revoke execute on function public.deactivate_internal_staff_user_v2' "$migration"

echo 'Responsibility resolution schema smoke checks passed'
