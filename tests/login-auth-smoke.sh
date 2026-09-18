#!/usr/bin/env bash
set -euo pipefail

test -s docs/login.html
test -s docs/login.js
test -s docs/supabase-client.js
test -s docs/sw.js
test -s docs/mfa-common.js
test -s docs/mfa-setup.html
test -s docs/mfa-setup.js
test -s docs/mfa-challenge.html
test -s docs/mfa-challenge.js

node --check docs/login.js
node --check docs/sw.js
node --check docs/mfa-common.js
node --check docs/mfa-setup.js
node --check docs/mfa-challenge.js
node --check docs/auth-guard.js

grep -Fq 'id="loginForm" class="auth-form" method="post"' docs/login.html
! grep -Fq 'name="email"' docs/login.html
! grep -Fq 'name="password"' docs/login.html
grep -Fq 'event => event.preventDefault()' docs/login.html
grep -Fq 'allaiso-login-module-recovery-v2' docs/login.html
grep -Fq 'navigator.serviceWorker.getRegistrations()' docs/login.html
grep -Fq 'key.startsWith("gestionpisos-shell-")' docs/login.html
grep -Fq 'auth_refresh", "2026091702"' docs/login.html
grep -Fq 'import("./login.js?v=2026091702")' docs/login.html
grep -Fq 'No se pudo cargar el módulo de acceso.' docs/login.html

grep -Fq 'supabase-client.js?v=2026091603' docs/login.js
grep -Fq 'mfa-common.js?v=2026091701' docs/login.js
grep -Fq 'window.__loginModuleReady = true' docs/login.js
grep -Fq 'form.addEventListener("submit"' docs/login.js
grep -Fq 'withTimeout(getCurrentSession(), 4000' docs/login.js
grep -Fq 'signInWithPassword' docs/login.js
grep -Fq 'privilegedMfaRoute(supabase, session, { requireEnrollment: true })' docs/login.js
grep -Fq '"login_timeout"' docs/login.js
grep -Fq '"mfa_check_timeout"' docs/login.js
grep -Fq 'login_request_failed' docs/login.js
grep -Fq 'El servicio de acceso no respondió a tiempo.' docs/login.js

grep -Fq 'new Set(["root", "admin"])' docs/mfa-common.js
grep -Fq 'getAuthenticatorAssuranceLevel' docs/mfa-common.js
grep -Fq 'mfa-challenge.html' docs/mfa-common.js
grep -Fq 'requireEnrollment ? "mfa-setup.html" : null' docs/mfa-common.js

grep -Fq 'factorType: "totp"' docs/mfa-setup.js
grep -Fq 'friendlyName' docs/mfa-setup.js
grep -Fq 'supabase.auth.mfa.challenge' docs/mfa-setup.js
grep -Fq 'supabase.auth.mfa.verify' docs/mfa-setup.js
grep -Fq 'supabase.auth.mfa.unenroll' docs/mfa-setup.js
grep -Fq 'Añadir factor de respaldo' docs/mfa-setup.html
grep -Fq 'No la compartas con nadie.' docs/mfa-setup.html

grep -Fq 'listFactors' docs/mfa-challenge.js
grep -Fq 'factor.status === "verified"' docs/mfa-challenge.js
grep -Fq 'id="mfaFactorSelect"' docs/mfa-challenge.html
grep -Fq 'autocomplete="one-time-code"' docs/mfa-challenge.html

grep -Fq 'privilegedMfaRoute(supabase, session, { requireEnrollment: true })' docs/auth-guard.js
grep -Fq '🛡️ MFA' docs/auth-guard.js
! grep -Fq 'Seguridad MFA' docs/auth-guard.js
grep -Fq 'authFlowUrl(mfa.route' docs/auth-guard.js

grep -Fq 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.116.0/+esm' docs/supabase-client.js
grep -Fq 'https://esm.sh/@supabase/supabase-js@2.116.0' docs/supabase-client.js
grep -Fq 'supabase_client_module_load_failed' docs/supabase-client.js
! grep -Fq '@supabase/supabase-js@2.57.4' docs/supabase-client.js

grep -Fq "gestionpisos-shell-v11" docs/sw.js
grep -Fq "'./mfa-setup.html'" docs/sw.js
grep -Fq "'./mfa-challenge.html'" docs/sw.js
grep -Fq "if(url.origin!==self.location.origin) return;" docs/sw.js
grep -Fq "caches.match(event.request,{ignoreSearch:true})" docs/sw.js
grep -Fq "if(event.request.mode==='navigate')" docs/sw.js
! grep -Fq "r||caches.match('./login.html')" docs/sw.js

echo 'Login auth smoke checks passed'
