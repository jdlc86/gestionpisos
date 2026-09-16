#!/usr/bin/env bash
set -euo pipefail

node --check docs/login.js
node --check docs/reset-password.js

test -s docs/login.html
test -s docs/reset-password.html

grep -Fq 'resetPasswordForEmail' docs/login.js
grep -Fq 'redirectTo: recoveryRedirectUrl()' docs/login.js
grep -Fq 'if (error)' docs/login.js
grep -Fq 'Si la cuenta existe, recibirás un enlace' docs/login.js
grep -Fq 'import("./login.js?v=2026091603")' docs/login.html

grep -Fq 'id="confirmPassword"' docs/reset-password.html
grep -Fq 'Validando enlace de recuperación' docs/reset-password.html
grep -Fq 'reset-password.js?v=2026091601' docs/reset-password.html
grep -Fq 'PASSWORD_RECOVERY' docs/reset-password.js
grep -Fq 'allaiso-password-recovery' docs/reset-password.js
grep -Fq 'password.value !== confirmPassword.value' docs/reset-password.js
grep -Fq 'supabase.auth.updateUser({ password: password.value })' docs/reset-password.js
grep -Fq 'supabase.auth.signOut()' docs/reset-password.js
grep -Fq './login.html?password=updated' docs/reset-password.js

grep -Fq 'hash.get("type") !== "recovery"' docs/index.html
grep -Fq 'reset-password.html' docs/index.html
grep -Fq 'target.hash = window.location.hash' docs/index.html

echo 'Auth recovery smoke checks passed'
