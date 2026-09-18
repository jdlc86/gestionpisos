#!/usr/bin/env bash
set -euo pipefail

test -s docs/activate-external-account.html
test -s docs/activate-external-account.js
test -s docs/portfolio-onboarding.js
test -s supabase/functions/send-external-welcome/index.ts
test -s supabase/functions/complete-external-onboarding/index.ts
test -s supabase/functions/_shared/external-onboarding-email.ts
test -s supabase/functions/_shared/external-onboarding-revocation.ts
test -s supabase/functions/revoke-external-welcome/index.ts

node --check docs/activate-external-account.js
node --check docs/portfolio-onboarding.js
node --check docs/portfolio.js

grep -Fq 'minlength="12"' docs/activate-external-account.html
grep -Fq 'id="passwordChecklist"' docs/activate-external-account.html
grep -Fq '12 caracteres como mínimo' docs/activate-external-account.html
grep -Fq 'Una letra minúscula' docs/activate-external-account.html
grep -Fq 'Una letra mayúscula' docs/activate-external-account.html
grep -Fq 'Un número' docs/activate-external-account.html
grep -Fq 'Un símbolo' docs/activate-external-account.html
grep -Fq 'Las contraseñas coinciden' docs/activate-external-account.html
grep -Fq 'activate-external-account.js?v=2026091701' docs/activate-external-account.html
grep -Fq 'passwordPolicyValid()' docs/activate-external-account.js
grep -Fq 'symbolPattern.test(value)' docs/activate-external-account.js
grep -Fq 'complete-external-onboarding' docs/activate-external-account.js
grep -Fq 'auth_metadata_synced' docs/activate-external-account.js
grep -Fq 'get_my_external_account_onboarding' docs/auth-guard.js
grep -Fq 'activate-external-account.html' docs/auth-guard.js

grep -Fq 'portfolio-onboarding.js?v=2026091803' docs/portfolio.html
grep -Fq 'Guardar y enviar bienvenida' docs/portfolio.html
grep -Fq 'Bienvenida del propietario' docs/portfolio-onboarding.js
grep -Fq 'Enviar bienvenida' docs/portfolio-onboarding.js
grep -Fq 'Reenviar bienvenida' docs/portfolio-onboarding.js
grep -Fq 'get_external_onboarding_statuses' docs/portfolio-onboarding.js
grep -Fq 'send-external-welcome' docs/portfolio-onboarding.js
grep -Fq 'email_internal_identity_conflict' docs/portfolio-onboarding.js
grep -Fq 'delivery==="failed"?"Envío no confirmado":"Invitación pendiente"' docs/portfolio-onboarding.js
grep -Fq 'Email cambiado · nueva invitación necesaria' docs/portfolio-onboarding.js
grep -Fq 'Cambiar el email invalidará la invitación enviada a ' docs/portfolio-onboarding.js
grep -Fq 'revoke-external-welcome' docs/portfolio-onboarding.js
grep -Fq 'externalEmailChangeBypass' docs/portfolio-onboarding.js
grep -Fq 'scheduleRefresh(250);' docs/portfolio-onboarding.js
grep -Fq 'gestionpisos:portfolio-rendered' docs/portfolio.js
grep -Fq 'gestionpisos:portfolio-rendered' docs/portfolio-onboarding.js
! grep -Fq 'new MutationObserver' docs/portfolio-onboarding.js
grep -Fq 'portfolio.js?v=2026091802' docs/portfolio.html
grep -Fq 'external_active_account_email_change_requires_account_flow' docs/portfolio-onboarding.js
grep -Fq 'external_onboarding_email_change_requires_revocation' docs/portfolio.js

grep -Fq 'auth.admin.generateLink' supabase/functions/_shared/external-onboarding-email.ts
grep -Fq 'https://api.resend.com/emails' supabase/functions/_shared/external-onboarding-email.ts
grep -Fq 'RESEND_API_KEY' supabase/functions/_shared/external-onboarding-email.ts
grep -Fq 'AUTH_EMAIL_FROM' supabase/functions/_shared/external-onboarding-email.ts
grep -Fq 'accept-invitation.html' supabase/functions/_shared/external-onboarding-email.ts

grep -Fq 'email_internal_identity_conflict' supabase/functions/send-external-welcome/index.ts
grep -Fq 'email_external_identity_conflict' supabase/functions/send-external-welcome/index.ts
grep -Fq 'email_auth_identity_conflict' supabase/functions/send-external-welcome/index.ts
grep -Fq 'can_manage_permissions' supabase/functions/send-external-welcome/index.ts
grep -Fq 'can_operate_property_v3' supabase/functions/send-external-welcome/index.ts
! grep -Fq 'password:' supabase/functions/send-external-welcome/index.ts
grep -Fq 'disableAndRevokeExternalOnboarding' supabase/functions/send-external-welcome/index.ts
grep -Fq 'external_stale_onboarding_revoke_failed' supabase/functions/send-external-welcome/index.ts
grep -Fq 'admin.auth.admin.deleteUser(input.authUserId, true)' supabase/functions/_shared/external-onboarding-revocation.ts
grep -Fq 'revoke_external_account_onboarding_v1' supabase/functions/_shared/external-onboarding-revocation.ts
grep -Fq 'disableAndRevokeExternalOnboarding' supabase/functions/revoke-external-welcome/index.ts
grep -Fq 'external_active_account_email_change_requires_account_flow' supabase/functions/revoke-external-welcome/index.ts
grep -Fq 'external_welcome_permission_required' supabase/functions/revoke-external-welcome/index.ts

# Claims may only be published after the authoritative DB completion call.
FILE='supabase/functions/complete-external-onboarding/index.ts'
db_line=$(grep -n 'complete_external_account_onboarding' "$FILE" | head -1 | cut -d: -f1)
claims_line=$(grep -n 'app_metadata: nextMetadata' "$FILE" | head -1 | cut -d: -f1)
if [ -z "$db_line" ] || [ -z "$claims_line" ] || [ "$db_line" -ge "$claims_line" ]; then
  echo 'External Auth claims must only be synchronized after authoritative DB activation.' >&2
  exit 1
fi
grep -Fq 'external_auth_metadata_sync_failed' "$FILE"
grep -Fq 'database_active: true' "$FILE"

echo 'External owner/tenant onboarding smoke checks passed'
