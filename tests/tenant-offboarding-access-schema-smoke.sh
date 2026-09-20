#!/usr/bin/env bash
set -euo pipefail

migration="supabase/migrations/20260920033000_tenant_offboarding_access_enforcement.sql"
reactivation_migration="supabase/migrations/20260920170000_tenant_reactivation_atomic.sql"
reactivation_regression="tests/tenant-reactivation-regression.sql"
regression="tests/tenant-offboarding-access-regression.sql"
edge="supabase/functions/disable-tenant-auth/index.ts"
workflow=".github/workflows/tenant-offboarding-auth.yml"

test -s "$migration"
test -s "$reactivation_migration"
test -s "$reactivation_regression"
test -s "$regression"
test -s "$edge"
test -s "$workflow"

grep -Fq 'create or replace function public.has_current_platform_access_v1()' "$migration"
grep -Fq "ur.role in ('root','admin','owner','employee')" "$migration"
grep -Fq "ur.role='tenant'" "$migration"
grep -Fq "t.status='active'" "$migration"
grep -Fq "o.status='active'" "$migration"
grep -Fq 'o.starts_on<=current_date' "$migration"
grep -Fq 'create or replace function public.get_tenant_offboarding_auth_state_v1' "$migration"
grep -Fq "'other_active_role',v_other_active_role" "$migration"
grep -Fq "'disable_auth',v_user_id is not null" "$migration"
grep -Fq 'create or replace function public.offboard_tenant_occupancy_v2' "$migration"
grep -Fq "set revoked_at=coalesce(revoked_at,now())" "$migration"
grep -Fq "role='tenant'" "$migration"
grep -Fq "'tenant_platform_access_revoked'" "$migration"
grep -Fq 'create or replace function public.restore_tenant_platform_access_v1' "$migration"
grep -Fq 'create or replace function public.reactivate_tenant_occupancy_v1' "$reactivation_migration"
grep -Fq "public.restore_tenant_platform_access_v1(" "$reactivation_migration"
grep -Fq "'tenant_occupancy_reactivated'" "$reactivation_migration"
grep -Fq 'reactivated tenant still lacks platform access' "$reactivation_regression"
grep -Fq 'failed reactivation did not preserve suspended occupancy' "$reactivation_regression"
grep -Fq "'tenant_platform_access_reactivated'" "$migration"
grep -Fq "'alter table public.%I enable row level security'" "$migration"
grep -Fq 'from public,anon,authenticated' "$migration"
grep -Fq 'to service_role' "$migration"
grep -Fq 'o.tenant_id=v_tenant_id' "$migration"
grep -Fq 'as restrictive for all to authenticated' "$migration"
grep -Fq "'tenant_tasks_v2'" "$migration"
grep -Fq "'notifications_v2'" "$migration"
grep -Fq "'workflow_executions_v2'" "$migration"
grep -Fq "bucket_id not in ('photo-verification','tenant-documents-v2','workflow-documents-v2')" "$migration"
grep -Fq 'revoke all on function public.has_current_platform_access_v1()' "$migration"
grep -Fq 'revoke all on function public.get_tenant_offboarding_auth_state_v1(uuid)' "$migration"

grep -Fq 'stale tenant JWT retained platform access' "$regression"
grep -Fq 'stale tenant JWT can still read archived occupancy' "$regression"
grep -Fq 'stale tenant JWT can still read assigned task' "$regression"
grep -Fq 'tenant role revoked despite another active occupancy' "$regression"
grep -Fq 'shared canonical tenant was archived while another occupancy remained active' "$regression"
grep -Fq 'returning tenant role was not restored' "$regression"
grep -Fq 'reactivated tenant did not regain platform access' "$regression"
grep -Fq 'remaining active occupancy did not preserve platform access' "$regression"

grep -Fq 'get_tenant_offboarding_auth_state_v1' "$edge"
grep -Fq 'occupancy_id?: string' "$edge"
! grep -Fq 'target_user_id?: string' "$edge"
grep -Fq 'admin.auth.admin.getUserById(targetUserId)' "$edge"
grep -Fq 'ban_duration: "876000h"' "$edge"
grep -Fq '"tenant_auth_disable_started"' "$edge"
grep -Fq '"tenant_auth_disabled"' "$edge"
grep -Fq '"tenant_auth_disable_audit_start_failed"' "$edge"
grep -Fq '"tenant_auth_disable_audit_failed"' "$edge"
grep -Fq 'delete metadata.role' "$edge"
grep -Fq 'delete metadata.organization_id' "$edge"
grep -Fq '"tenant_auth_disabled"' "$edge"
grep -Fq 'database_access_revoked: true' "$edge"

grep -Fq "supabase functions deploy disable-tenant-auth" "$workflow"
grep -Fq "supabase functions deploy send-external-welcome" "$workflow"
grep -Fq -- '--no-verify-jwt' "$workflow"
grep -Fq "branches: [main]" "$workflow"

grep -Fq 'supabase.functions.invoke("disable-tenant-auth"' docs/portfolio.js
grep -Fq 'supabase.rpc("reactivate_tenant_occupancy_v1"' docs/portfolio.js
grep -Fq 'Acceso suspendido' docs/portfolio-onboarding.js
grep -Fq 'Acceso pendiente de vincular' docs/portfolio-onboarding.js
grep -Fq 'supabase.rpc("has_current_platform_access_v1")' docs/auth-guard.js
grep -Fq 'supabase.rpc("has_current_platform_access_v1")' docs/login.js
grep -Fq 'supabase.auth.signOut({ scope: "global" })' docs/auth-guard.js
grep -Fq 'Tu acceso a Allaiso ya no está activo.' docs/login.js

echo 'Tenant offboarding access security contract passed'
