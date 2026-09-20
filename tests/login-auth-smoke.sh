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
node --check docs/mfa-code-input.js
node --check docs/auth-guard.js

grep -Fq 'id="loginForm" class="auth-form" method="post"' docs/login.html
! grep -Fq 'name="email"' docs/login.html
! grep -Fq 'name="password"' docs/login.html
grep -Fq 'event => event.preventDefault()' docs/login.html
grep -Fq 'allaiso-login-module-recovery-v2' docs/login.html
grep -Fq 'navigator.serviceWorker.getRegistrations()' docs/login.html
grep -Fq 'key.startsWith("gestionpisos-shell-")' docs/login.html
grep -Fq 'auth_refresh", "2026092001"' docs/login.html
grep -Fq 'import("./login.js?v=2026092001")' docs/login.html
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
grep -Fq 'supabase.rpc("has_current_platform_access_v1")' docs/login.js
grep -Fq '"platform_access_revoked"' docs/login.js
grep -Fq 'supabase.auth.signOut({ scope: "global" })' docs/login.js
grep -Fq 'Tu acceso a Allaiso ya no está activo.' docs/login.js
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
grep -Fq 'id="mfaCodeBoxes" class="mfa-code-boxes"' docs/mfa-challenge.html
grep -Fq 'autocomplete=index===0?"one-time-code":"off"' docs/mfa-code-input.js

grep -Fq 'privilegedMfaRoute(supabase, session, { requireEnrollment: true })' docs/auth-guard.js
grep -Fq 'setupHomeAccountMenu(session)' docs/auth-guard.js
grep -Fq 'mfaAction.hidden = !requiresPrivilegedMfa(session)' docs/auth-guard.js
grep -Fq 'Seguridad MFA' docs/index.html
grep -Fq 'authFlowUrl(mfa.route' docs/auth-guard.js
grep -Fq 'supabase.rpc("has_current_platform_access_v1")' docs/auth-guard.js
grep -Fq 'revokeLocalSessionAndReturnToLogin' docs/auth-guard.js
grep -Fq 'supabase.auth.signOut({ scope: "global" })' docs/auth-guard.js
grep -Fq 'deniedUrl.searchParams.set("access", "revoked")' docs/auth-guard.js
grep -Fq 'const isHomePage = currentPage === "index.html"' docs/auth-guard.js
grep -Fq 'if (isHomePage) {' docs/auth-guard.js
grep -Fq 'setupHomeAccountMenu(session);' docs/auth-guard.js
grep -Fq 'mountNotificationCenter({ supabase, session })' docs/auth-guard.js
grep -Fq 'id="homeAccountAction"' docs/index.html
grep -Fq 'id="logoutBtn"' docs/index.html

grep -Fq 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.116.0/+esm' docs/supabase-client.js
grep -Fq 'https://esm.sh/@supabase/supabase-js@2.116.0' docs/supabase-client.js
grep -Fq 'supabase_client_module_load_failed' docs/supabase-client.js
! grep -Fq '@supabase/supabase-js@2.57.4' docs/supabase-client.js

grep -Fq "gestionpisos-shell-v47" docs/sw.js
grep -Fq "'./mfa-setup.html'" docs/sw.js
grep -Fq "'./mfa-challenge.html'" docs/sw.js
grep -Fq "if(url.origin!==self.location.origin) return;" docs/sw.js
grep -Fq "caches.match(event.request,{ignoreSearch:true})" docs/sw.js
grep -Fq "if(event.request.mode==='navigate')" docs/sw.js
! grep -Fq "r||caches.match('./login.html')" docs/sw.js

echo 'Login auth smoke checks passed'
