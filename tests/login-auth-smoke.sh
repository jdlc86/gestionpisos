#!/usr/bin/env bash
set -euo pipefail

test -s docs/login.html
test -s docs/login.js
test -s docs/sw.js

node --check docs/login.js
node --check docs/sw.js

grep -Fq 'id="loginForm" class="auth-form" method="post"' docs/login.html
! grep -Fq 'name="email"' docs/login.html
! grep -Fq 'name="password"' docs/login.html
grep -Fq 'event => event.preventDefault()' docs/login.html
grep -Fq 'login.js?v=2026091602' docs/login.html

grep -Fq 'signInWithPassword' docs/login.js
grep -Fq 'login_request_failed' docs/login.js
grep -Fq 'No se pudo contactar con el servicio de acceso.' docs/login.js

grep -Fq "gestionpisos-shell-v3" docs/sw.js
grep -Fq "if(url.origin!==self.location.origin) return;" docs/sw.js
grep -Fq "caches.match(event.request,{ignoreSearch:true})" docs/sw.js
grep -Fq "if(event.request.mode==='navigate')" docs/sw.js
! grep -Fq "r||caches.match('./login.html')" docs/sw.js

echo 'Login auth smoke checks passed'
