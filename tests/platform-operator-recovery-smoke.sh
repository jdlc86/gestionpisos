#!/usr/bin/env bash
set -euo pipefail

test -s docs/operator-recovery.html
test -s docs/operator-recovery.js
test -s docs/emergency-operators.js
test -s supabase/functions/operator-mfa-recovery/index.ts
test -s supabase/functions/recover-privileged-mfa/index.ts
test -s supabase/functions/manage-platform-operators/index.ts
test -s supabase/migrations/20260917123000_platform_operator_mfa_console.sql

node --check docs/operator-recovery.js
node --check docs/emergency-operators.js

grep -Fq 'storageKey: "gestionpisos-platform-operator-auth"' docs/operator-recovery.js
grep -Fq 'operator-mfa-recovery' docs/operator-recovery.js
grep -Fq 'signInWithPassword' docs/operator-recovery.js
grep -Fq 'supabase.auth.mfa.challenge' docs/operator-recovery.js
grep -Fq 'supabase.auth.mfa.verify' docs/operator-recovery.js
grep -Fq 'Aprobar recuperación' docs/operator-recovery.js
grep -Fq 'Consola técnica separada de GestionPisos' docs/operator-recovery.html
grep -Fq 'noindex,nofollow,noarchive' docs/operator-recovery.html

grep -Fq 'platform_operators' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'aal2_required' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'self_approval_forbidden' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'root_recovery_capability_required' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'mfa_recovery_rejected' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'recover-privileged-mfa' supabase/functions/operator-mfa-recovery/index.ts
grep -Fq 'operator_user_id: actor.id' supabase/functions/operator-mfa-recovery/index.ts

grep -Fq 'id="emergencyOperatorsPanel"' docs/permissions.html
grep -Fq 'Operadores de emergencia' docs/permissions.html
grep -Fq 'emergency-operators.js' docs/permissions.html
grep -Fq 'manage-platform-operators' docs/emergency-operators.js
grep -Fq 'can_recover_root' docs/emergency-operators.js
grep -Fq 'self_operator_forbidden' docs/emergency-operators.js
grep -Fq 'dedicated_platform_identity_required' docs/emergency-operators.js

grep -Fq 'role !== "root"' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'root_required' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'aal2_required' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'self_operator_forbidden' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'dedicated_platform_identity_required' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'platform_operator_created' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'platform_operator_updated' supabase/functions/manage-platform-operators/index.ts
grep -Fq 'audit_log_v2' supabase/functions/manage-platform-operators/index.ts

grep -Fq 'alter table public.platform_operators enable row level security' supabase/migrations/20260917123000_platform_operator_mfa_console.sql
grep -Fq 'revoke all on table public.platform_operators from public, anon, authenticated' supabase/migrations/20260917123000_platform_operator_mfa_console.sql
grep -Fq 'can_recover_root boolean not null default false' supabase/migrations/20260917123000_platform_operator_mfa_console.sql

# The public UIs must not embed privileged backend credentials or call the destructive executor directly.
! grep -Fq 'service_role' docs/operator-recovery.html
! grep -Fq 'service_role' docs/operator-recovery.js
! grep -Fq 'service_role' docs/emergency-operators.js
! grep -Fq 'recover-privileged-mfa' docs/operator-recovery.js
! grep -Fq 'recover-privileged-mfa' docs/emergency-operators.js
! grep -Fq '.from("platform_operators")' docs/emergency-operators.js
! grep -Fq 'manage-platform-operators' docs/operator-recovery.js

echo 'Platform operator recovery and ROOT management smoke checks passed'
