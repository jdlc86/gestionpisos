#!/usr/bin/env bash
set -euo pipefail

migration="supabase/migrations/20260916023500_internal_staff_deactivation.sql"
test -s "$migration"
grep -Fq 'create or replace function public.deactivate_internal_staff_user' "$migration"
grep -Fq "raise exception 'self_deactivation_not_allowed'" "$migration"
grep -Fq "raise exception 'target_internal_staff_required'" "$migration"
grep -Fq "raise exception 'staff_responsible_reassignment_required'" "$migration"
grep -Fq "raise exception 'staff_write_control_transfer_required'" "$migration"
grep -Fq "assignment_type='access'" "$migration"
grep -Fq "status='cancelled'" "$migration"
grep -Fq "role in ('admin','employee')" "$migration"
grep -Fq "status='archived'" "$migration"
grep -Fq "'deactivate_internal_staff'" "$migration"
grep -Fq 'revoke all on function public.deactivate_internal_staff_user' "$migration"
grep -Fq 'grant execute on function public.deactivate_internal_staff_user' "$migration"

test -s supabase/functions/disable-internal-staff-auth/index.ts
grep -Fq 'can_manage_permissions' supabase/functions/disable-internal-staff-auth/index.ts
grep -Fq 'staff_still_active' supabase/functions/disable-internal-staff-auth/index.ts
grep -Fq 'ban_duration: "876000h"' supabase/functions/disable-internal-staff-auth/index.ts
grep -Fq 'retiredEmailFor' supabase/functions/disable-internal-staff-auth/index.ts
grep -Fq '@deleted.invalid' supabase/functions/disable-internal-staff-auth/index.ts
grep -Fq 'auth_email_retire_failed' supabase/functions/disable-internal-staff-auth/index.ts

test -s supabase/functions/create-organization-user/index.ts
grep -Fq 'retireArchivedEmailOwner' supabase/functions/create-organization-user/index.ts
grep -Fq '.eq("status", "archived")' supabase/functions/create-organization-user/index.ts
grep -Fq 'hasActiveRole' supabase/functions/create-organization-user/index.ts
grep -Fq 'wasInternalStaffHere' supabase/functions/create-organization-user/index.ts
grep -Fq 'bannedUntil' supabase/functions/create-organization-user/index.ts
grep -Fq 'email_in_use' supabase/functions/create-organization-user/index.ts
grep -Fq 'reclaimed_archived_email' supabase/functions/create-organization-user/index.ts

echo 'Internal staff deactivation and email reuse schema contract passed'
