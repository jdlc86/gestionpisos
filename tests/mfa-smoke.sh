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
grep -Fq 'supabase.auth.mfa.challenge' docs/mfa-setup.js
grep -Fq 'supabase.auth.mfa.verify' docs/mfa-setup.js
grep -Fq 'currentLevel !== "aal2"' docs/mfa-setup.js
grep -Fq 'Cancelar y cerrar sesión' docs/mfa-setup.html
grep -Fq 'No la compartas con nadie.' docs/mfa-setup.html

grep -Fq 'listFactors' docs/mfa-challenge.js
grep -Fq 'factor.status === "verified"' docs/mfa-challenge.js
grep -Fq 'currentLevel !== "aal2"' docs/mfa-challenge.js
grep -Fq 'autocomplete="one-time-code"' docs/mfa-challenge.html

grep -Fq 'privilegedMfaRoute(supabase, session)' docs/auth-guard.js
grep -Fq 'Configurar MFA' docs/auth-guard.js
grep -Fq 'authFlowUrl(mfa.route' docs/auth-guard.js
grep -Fq 'privilegedMfaRoute(supabase, session)' docs/login.js
grep -Fq 'mfa_check_timeout' docs/login.js

grep -Fq "gestionpisos-shell-v2" docs/sw.js
grep -Fq "'./mfa-setup.html'" docs/sw.js
grep -Fq "'./mfa-challenge.html'" docs/sw.js

echo 'MFA smoke checks passed'
