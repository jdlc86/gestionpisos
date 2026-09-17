#!/usr/bin/env bash
set -euo pipefail

test -s docs/mfa-common.js
test -s docs/mfa-setup.html
test -s docs/mfa-setup.js
test -s docs/mfa-challenge.html
test -s docs/mfa-challenge.js

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
grep -Fq 'Añadir factor de respaldo' docs/mfa-setup.html
grep -Fq 'Tus autenticadores' docs/mfa-setup.html
grep -Fq 'Cancelar y cerrar sesión' docs/mfa-setup.html
grep -Fq 'No la compartas con nadie.' docs/mfa-setup.html
grep -Fq 'mfa-setup.js?v=2026091702' docs/mfa-setup.html

grep -Fq 'listFactors' docs/mfa-challenge.js
grep -Fq 'factor.status === "verified"' docs/mfa-challenge.js
grep -Fq 'factorSelect.addEventListener("change"' docs/mfa-challenge.js
grep -Fq 'id="mfaFactorSelect"' docs/mfa-challenge.html
grep -Fq 'autocomplete="one-time-code"' docs/mfa-challenge.html
grep -Fq 'mfa-challenge.js?v=2026091702' docs/mfa-challenge.html

grep -Fq 'privilegedMfaRoute(supabase, session, { requireEnrollment: true })' docs/auth-guard.js
grep -Fq 'Seguridad MFA' docs/auth-guard.js
grep -Fq 'authFlowUrl(mfa.route' docs/auth-guard.js
grep -Fq 'privilegedMfaRoute(supabase, session, { requireEnrollment: true })' docs/login.js
grep -Fq 'mfa_check_timeout' docs/login.js

grep -Fq "gestionpisos-shell-v2" docs/sw.js
grep -Fq "'./mfa-setup.html'" docs/sw.js
grep -Fq "'./mfa-challenge.html'" docs/sw.js

echo 'MFA smoke checks passed'
