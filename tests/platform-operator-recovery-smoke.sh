#!/usr/bin/env bash
set -euo pipefail

test -s docs/operator-recovery.html
test -s docs/operator-recovery.js
test -s docs/operator-activate.html
test -s docs/operator-activate.js
test -s docs/emergency-operators.js
test -s supabase/functions/operator-mfa-recovery/index.ts
test -s supabase/functions/recover-privileged-mfa/index.ts
test -s supabase/functions/manage-platform-operators/index.ts
test -s supabase/migrations/20260917104118_platform_operator_mfa_console.sql
test -s supabase/migrations/20260917111858_root_platform_operator_management.sql
test -s supabase/migrations/20260918224500_invitation_email_invariant.sql

node --check docs/operator-recovery.js
node --check docs/operator-activate.js
node --check docs/emergency-operators.js

grep -Fq 'storageKey: "gestionpisos-platform-operator-auth"' docs/operator-recovery.js
grep -Fq 'operator-mfa-recovery' docs/operator-recovery.js
grep -Fq 'signInWithPassword' docs/operator-recovery.js
grep -Fq 'supabase.auth.mfa.challenge' docs/operator-recovery.js
grep -Fq 'supabase.auth.mfa.verify' docs/operator-recovery.js
grep -Fq 'Aprobar recuperación' docs/operator-recovery.js
grep -Fq 'Consola técnica separada de GestionPisos' docs/operator-recovery.html
grep -Fq 'noindex,nofollow,noarchive' docs/operator-recovery.html

grep -Fq 'platform_operator_invitation_pending' docs/operator-activate.js
grep -Fq 'supabase.auth.updateUser' docs/operator-activate.js
grep -Fq '12 caracteres como mínimo' docs/operator-activate.html
grep -Fq 'operator-recovery.html?activated=1' docs/operator-activate.js
grep -Fq 'operator-activate.js?v=2026091801' docs/operator-activate.html
grep -Fq 'enableVerifiedOperator' docs/operator-activate.js
grep -Fq 'operator-mfa-recovery' docs/operator-activate.js
grep -Fq 'reprovisione el operador' docs/operator-activate.js

grep -Fq 'platform_operators' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'aal2_required' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'self_approval_forbidden' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'root_recovery_capability_required' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'mfa_recovery_rejected' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'recover-privileged-mfa' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'operator_user_id: actor.id' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'identity_email' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'platform_operator_identity_email_mismatch' supabase/functions/operator-mfa-recovery/index.ts

grep -Fq 'id="emergencyOperatorsPanel"' docs/permissions.html
grep -Fq 'Operadores de emergencia' docs/permissions.html
grep -Fq 'emergency-operators.js' docs/permissions.html
grep -Fq 'manage-platform-operators' docs/emergency-operators.js
grep -Fq 'can_recover_root' docs/emergency-operators.js
grep -Fq 'self_operator_forbidden' docs/emergency-operators.js
grep -Fq 'dedicated_platform_identity_required' docs/emergency-operators.js
grep -Fq 'platform_operator_identity_email_mismatch' docs/emergency-operators.js
grep -Fq 'platform_operator_email_change_requires_reprovision' docs/emergency-operators.js
grep -Fq 'Email no coincide · reprovisionar' docs/emergency-operators.js
grep -Fq 'emergency-operators.js?v=2026091801' docs/permissions.html

grep -Fq 'role !== "root"' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'root_required' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'aal2_required' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'self_operator_forbidden' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'dedicated_platform_identity_required' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'manage_platform_operator_service' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'admin.auth.admin.createUser' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'admin.auth.admin.generateLink' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'operator-activate.html?operator=1' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'RESEND_API_KEY' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'AUTH_EMAIL_FROM' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'platform_operator_invitation_pending' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'identity_email' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'email_consistent' supabase/functions/manage-platform-operators/index.ts

grep -Fq 'security definer' supabase/migrations/20260917111858_root_platform_operator_management.sql
grep -Fq 'platform_operator_created' supabase/migrations/20260917111858_root_platform_operator_management.sql
grep -Fq 'platform_operator_updated' supabase/migrations/20260917111858_root_platform_operator_management.sql
grep -Fq 'audit_log_v2' supabase/migrations/20260917111858_root_platform_operator_management.sql
grep -Fq 'revoke all on function public.manage_platform_operator_service' supabase/migrations/20260917111858_root_platform_operator_management.sql
grep -Fq 'grant execute on function public.manage_platform_operator_service' supabase/migrations/20260917111858_root_platform_operator_management.sql

grep -Fq 'alter table public.platform_operators enable row level security' supabase/migrations/20260917104118_platform_operator_mfa_console.sql
grep -Fq 'revoke all on table public.platform_operators from public, anon, authenticated' supabase/migrations/20260917104118_platform_operator_mfa_console.sql
grep -Fq 'can_recover_root boolean not null default false' supabase/migrations/20260917104118_platform_operator_mfa_console.sql
grep -Fq 'add column if not exists identity_email text' supabase/migrations/20260918224500_invitation_email_invariant.sql
grep -Fq 'platform_operator_identity_email_backfill_inconsistent' supabase/migrations/20260918224500_invitation_email_invariant.sql
grep -Fq 'platform_operator_identity_email_immutable' supabase/migrations/20260918224500_invitation_email_invariant.sql
grep -Fq 'platform_operator_email_change_requires_reprovision' supabase/migrations/20260918224500_invitation_email_invariant.sql
grep -Fq 'platform_operator_identity_email_guard' supabase/migrations/20260918224500_invitation_email_invariant.sql

# The public UIs must not embed privileged backend credentials or call the destructive executor directly.
! grep -Fq 'service_role' docs/operator-recovery.html
! grep -Fq 'service_role' docs/operator-recovery.js
! grep -Fq 'service_role' docs/operator-activate.html
! grep -Fq 'service_role' docs/operator-activate.js
! grep -Fq 'service_role' docs/emergency-operators.js
! grep -Fq 'recover-privileged-mfa' docs/operator-recovery.js
! grep -Fq 'recover-privileged-mfa' docs/operator-activate.js
! grep -Fq 'recover-privileged-mfa' docs/emergency-operators.js
! grep -Fq '.from("platform_operators")' docs/emergency-operators.js
! grep -Fq 'manage-platform-operators' docs/operator-recovery.js

# Operator onboarding must not use a known temporary password.
! grep -Fq 'temporary_password' supabase/functions/manage-platform-operators/index.ts
! grep -Fq 'temp_password' supabase/functions/manage-platform-operators/index.ts

echo 'Platform operator recovery, ROOT management and activation smoke checks passed'
