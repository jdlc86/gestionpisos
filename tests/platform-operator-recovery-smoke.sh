#!/usr/bin/env bash
set -euo pipefail

test -s docs/operator-recovery.html
test -s docs/operator-recovery.js
test -s supabase/functions/operator-mfa-recovery/index.ts
test -s supabase/functions/recover-privileged-mfa/index.ts
test -s supabase/migrations/20260917123000_platform_operator_mfa_console.sql

node --check docs/operator-recovery.js

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

grep -Fq 'alter table public.platform_operators enable row level security' supabase/migrations/20260917123000_platform_operator_mfa_console.sql
grep -Fq 'revoke all on table public.platform_operators from public, anon, authenticated' supabase/migrations/20260917123000_platform_operator_mfa_console.sql
grep -Fq 'can_recover_root boolean not null default false' supabase/migrations/20260917123000_platform_operator_mfa_console.sql

# No privileged backend credential may be embedded into the public console.
! grep -Fq 'service_role' docs/operator-recovery.html
! grep -Fq 'service_role' docs/operator-recovery.js
! grep -Fq 'recover-privileged-mfa' docs/operator-recovery.js

echo 'Platform operator recovery smoke checks passed'
