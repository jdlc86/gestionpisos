#!/usr/bin/env bash
set -euo pipefail

test -s docs/mfa-common.js
test -s docs/mfa-setup.html
test -s docs/mfa-setup.js
test -s docs/mfa-challenge.html
test -s docs/mfa-challenge.js
test -s supabase/functions/rename-mfa-factor/index.ts
test -s supabase/functions/request-mfa-recovery/index.ts
test -s supabase/functions/recover-privileged-mfa/index.ts
test -s docs/MFA_RECOVERY_RUNBOOK.md

node --check docs/mfa-common.js
node --check docs/mfa-setup.js
node --check docs/mfa-challenge.js
node --check docs/auth-guard.js
node --check docs/login.js

grep -Fq 'new Set(["root", "admin"])' docs/mfa-common.js
grep -Fq 'getAuthenticatorAssuranceLevel' docs/mfa-common.js
grep -Fq 'mfa-challenge.html' docs/mfa-common.js
grep -Fq 'requireEnrollment ? "mfa-setup.html" : null' docs/mfa-common.js

grep -Fq 'factorType: "totp"' docs/mfa-setup.js
grep -Fq 'friendlyName' docs/mfa-setup.js
grep -Fq 'supabase.auth.mfa.challenge' docs/mfa-setup.js
grep -Fq 'supabase.auth.mfa.verify' docs/mfa-setup.js
grep -Fq 'supabase.auth.mfa.unenroll' docs/mfa-setup.js
grep -Fq 'verifiedFactors.length <= 1' docs/mfa-setup.js
grep -Fq 'supabase.functions.invoke("rename-mfa-factor"' docs/mfa-setup.js
grep -Fq 'Renombrar' docs/mfa-setup.js
grep -Fq 'mfaQrLoading' docs/mfa-setup.js
grep -Fq 'Añadir factor de respaldo' docs/mfa-setup.html
grep -Fq 'Tus autenticadores' docs/mfa-setup.html
grep -Fq 'Móvil personal' docs/mfa-setup.html
grep -Fq 'id="mfaQrLoading"' docs/mfa-setup.html
grep -Fq 'id="mfaQr" class="mfa-qr"' docs/mfa-setup.html
grep -Fq 'Cancelar y cerrar sesión' docs/mfa-setup.html
grep -Fq 'No la compartas con nadie.' docs/mfa-setup.html
grep -Fq 'auth.css?v=2026091704' docs/mfa-setup.html
grep -Fq 'mfa-setup.js?v=2026091703' docs/mfa-setup.html
grep -Fq '.auth-card [hidden]{display:none!important}' docs/auth.css

grep -Fq 'listFactors' docs/mfa-challenge.js
grep -Fq 'factor.status === "verified"' docs/mfa-challenge.js
grep -Fq 'factorSelect.addEventListener("change"' docs/mfa-challenge.js
grep -Fq 'id="mfaFactorSelect"' docs/mfa-challenge.html
grep -Fq 'autocomplete="one-time-code"' docs/mfa-challenge.html
grep -Fq 'No tengo acceso a mis autenticadores' docs/mfa-challenge.html
grep -Fq 'id="mfaRecoveryRequestId"' docs/mfa-challenge.html
grep -Fq 'mfa-challenge.js?v=2026091703' docs/mfa-challenge.html
grep -Fq 'supabase.functions.invoke("request-mfa-recovery"' docs/mfa-challenge.js
grep -Fq 'lost_all_available_authenticators' docs/mfa-challenge.js
! grep -Fq 'recover-privileged-mfa' docs/mfa-challenge.js

grep -Fq 'privilegedMfaRoute(supabase, session, { requireEnrollment: true })' docs/auth-guard.js
grep -Fq 'setupHomeAccountMenu(session)' docs/auth-guard.js
grep -Fq 'mfaAction.hidden = !requiresPrivilegedMfa(session)' docs/auth-guard.js
grep -Fq 'Seguridad MFA' docs/index.html
grep -Fq 'authFlowUrl(mfa.route' docs/auth-guard.js
grep -Fq 'const isHomePage = currentPage === "index.html"' docs/auth-guard.js
grep -Fq 'if (isHomePage) {' docs/auth-guard.js
grep -Fq 'setupHomeAccountMenu(session);' docs/auth-guard.js
grep -Fq 'mountNotificationCenter({ supabase, session })' docs/auth-guard.js
grep -Fq 'id="homeAccountAction"' docs/index.html
grep -Fq 'id="logoutBtn"' docs/index.html
grep -Fq 'privilegedMfaRoute(supabase, session, { requireEnrollment: true })' docs/login.js
grep -Fq 'mfa_check_timeout' docs/login.js

# The privileged MFA header action is centralized in auth-guard.js. Every protected
# screen that exposes the application shell must consume that same implementation.
for protected_screen in \
  docs/index.html \
  docs/portfolio.html \
  docs/operations.html \
  docs/workflows.html \
  docs/workflow-builder.html \
  docs/workflow-applications.html \
  docs/workflow-tasks.html \
  docs/cleaning.html \
  docs/incidents.html \
  docs/permissions.html \
  docs/configuration-resources.html \
  docs/photo-verifications.html \
  docs/photo-patterns.html \
  docs/photo-pattern-editor.html \
  docs/photo-camera.html
do
  grep -Fq './auth-guard.js' "$protected_screen"
done

grep -Fq 'aal2_required' supabase/functions/rename-mfa-factor/index.ts
grep -Fq 'privileged_role_required' supabase/functions/rename-mfa-factor/index.ts
grep -Fq '/auth/v1/admin/users/${actor.id}/factors' supabase/functions/rename-mfa-factor/index.ts
grep -Fq 'friendly_name_conflict' supabase/functions/rename-mfa-factor/index.ts

# Recovery request is user-authenticated but never destructive.
grep -Fq 'privileged_role_required' supabase/functions/request-mfa-recovery/index.ts
grep -Fq 'mfa_recovery_not_needed' supabase/functions/request-mfa-recovery/index.ts
grep -Fq 'no_verified_factor_to_recover' supabase/functions/request-mfa-recovery/index.ts
grep -Fq 'mfa_recovery_requested' supabase/functions/request-mfa-recovery/index.ts
grep -Fq 'expires_in_minutes: 60' supabase/functions/request-mfa-recovery/index.ts
! grep -Fq 'deleteFactor' supabase/functions/request-mfa-recovery/index.ts
! grep -Fq 'updateUserById' supabase/functions/request-mfa-recovery/index.ts

# Break-glass executor is backend-only and closes every escape hatch before clearing MFA.
grep -Fq 'callerToken !== serviceKey' supabase/functions/recover-privileged-mfa/index.ts
grep -Fq 'platform_operator_required' supabase/functions/recover-privileged-mfa/index.ts
grep -Fq 'recovery_request_expired' supabase/functions/recover-privileged-mfa/index.ts
grep -Fq 'target_not_privileged' supabase/functions/recover-privileged-mfa/index.ts
grep -Fq 'admin.auth.admin.mfa.deleteFactor' supabase/functions/recover-privileged-mfa/index.ts
grep -Fq 'password: emergencyPassword()' supabase/functions/recover-privileged-mfa/index.ts
grep -Fq 'resetPasswordForEmail' supabase/functions/recover-privileged-mfa/index.ts
grep -Fq 'mfa_recovery_partial' supabase/functions/recover-privileged-mfa/index.ts
grep -Fq 'mfa_recovery_completed' supabase/functions/recover-privileged-mfa/index.ts
grep -Fq 'operator_reference' supabase/functions/recover-privileged-mfa/index.ts
grep -Fq 'verification_note' supabase/functions/recover-privileged-mfa/index.ts

grep -Fq 'Nunca aprobar una recuperación únicamente por conocer el código de solicitud' docs/MFA_RECOVERY_RUNBOOK.md
grep -Fq 'el navegador nunca llama directamente a `recover-privileged-mfa`' docs/MFA_RECOVERY_RUNBOOK.md

grep -Fq "gestionpisos-shell-v39" docs/sw.js
grep -Fq "'./mfa-setup.html'" docs/sw.js
grep -Fq "'./mfa-challenge.html'" docs/sw.js

echo 'MFA smoke checks passed'
