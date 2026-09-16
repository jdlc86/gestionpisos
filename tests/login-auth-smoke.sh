#!/usr/bin/env bash
set -euo pipefail

test -s docs/login.html
test -s docs/login.js
test -s docs/supabase-client.js
test -s docs/sw.js

node --check docs/login.js
node --check docs/sw.js

grep -Fq 'id="loginForm" class="auth-form" method="post"' docs/login.html
! grep -Fq 'name="email"' docs/login.html
! grep -Fq 'name="password"' docs/login.html
grep -Fq 'event => event.preventDefault()' docs/login.html
grep -Fq 'allaiso-login-module-recovery-v2' docs/login.html
grep -Fq 'navigator.serviceWorker.getRegistrations()' docs/login.html
grep -Fq 'key.startsWith("gestionpisos-shell-")' docs/login.html
grep -Fq 'auth_refresh", "2026091604"' docs/login.html
grep -Fq 'import("./login.js?v=2026091604")' docs/login.html
grep -Fq 'No se pudo cargar el módulo de acceso.' docs/login.html

grep -Fq 'supabase-client.js?v=2026091603' docs/login.js
grep -Fq 'window.__loginModuleReady = true' docs/login.js
grep -Fq 'form.addEventListener("submit"' docs/login.js
grep -Fq 'withTimeout(getCurrentSession(), 4000' docs/login.js
grep -Fq 'signInWithPassword' docs/login.js
grep -Fq '"login_timeout"' docs/login.js
grep -Fq 'login_request_failed' docs/login.js
grep -Fq 'El servicio de acceso no respondió a tiempo.' docs/login.js

grep -Fq 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.116.0/+esm' docs/supabase-client.js
grep -Fq 'https://esm.sh/@supabase/supabase-js@2.116.0' docs/supabase-client.js
grep -Fq 'supabase_client_module_load_failed' docs/supabase-client.js
! grep -Fq '@supabase/supabase-js@2.57.4' docs/supabase-client.js

grep -Fq "gestionpisos-shell-v2" docs/sw.js
grep -Fq "if(url.origin!==self.location.origin) return;" docs/sw.js
grep -Fq "caches.match(event.request,{ignoreSearch:true})" docs/sw.js
grep -Fq "if(event.request.mode==='navigate')" docs/sw.js
! grep -Fq "r||caches.match('./login.html')" docs/sw.js

echo 'Login auth smoke checks passed'
