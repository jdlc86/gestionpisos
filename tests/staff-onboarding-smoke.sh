#!/usr/bin/env bash
set -euo pipefail

test -s docs/accept-invitation.html
test -s docs/accept-invitation.js
test -s docs/activate-account.html
test -s docs/activate-account.js
test -s docs/permissions-onboarding.js
node --check docs/accept-invitation.js
node --check docs/activate-account.js
node --check docs/permissions-onboarding.js

grep -Fq 'minlength="12"' docs/activate-account.html
grep -Fq 'id="passwordChecklist"' docs/activate-account.html
grep -Fq '12 caracteres como mínimo' docs/activate-account.html
grep -Fq 'Una letra minúscula' docs/activate-account.html
grep -Fq 'Una letra mayúscula' docs/activate-account.html
grep -Fq 'Un número' docs/activate-account.html
grep -Fq 'Un símbolo' docs/activate-account.html
grep -Fq 'Las contraseñas coinciden' docs/activate-account.html
grep -Fq 'complete-staff-onboarding' docs/activate-account.js
grep -Fq 'auth_metadata_synced' docs/activate-account.js
grep -Fq 'activate-account.js?v=2026091701' docs/activate-account.html
grep -Fq 'passwordPolicyValid()' docs/activate-account.js
grep -Fq 'symbolPattern.test(value)' docs/activate-account.js
grep -Fq 'updateUser({ password: password.value })' docs/activate-account.js
grep -Fq 'Cuenta activada. Ya puedes iniciar sesión.' docs/login.js
grep -Fq 'get_my_internal_staff_onboarding' docs/auth-guard.js

grep -Fq 'qsxtmmkftsohkqqmytbb.supabase.co' docs/accept-invitation.js
grep -Fq 'url.pathname !== "/auth/v1/verify"' docs/accept-invitation.js
grep -Fq 'history.replaceState' docs/accept-invitation.js
grep -Fq 'noindex,nofollow' docs/accept-invitation.html

test -s supabase/functions/_shared/staff-onboarding-email.ts
test -s supabase/functions/resend-staff-invitation/index.ts
test -s supabase/functions/complete-staff-onboarding/index.ts
grep -Fq 'provision_internal_staff_pending' supabase/functions/create-organization-user/index.ts
! grep -Fq 'provision_employee_profile_role' supabase/functions/create-organization-user/index.ts
grep -Fq 'sendStaffOnboardingInvitation' supabase/functions/create-organization-user/index.ts
grep -Fq 'onboarding_status: "pending"' supabase/functions/create-organization-user/index.ts
grep -Fq 'invitation_status: invitationStatus' supabase/functions/create-organization-user/index.ts
grep -Fq 'auth.admin.generateLink' supabase/functions/_shared/staff-onboarding-email.ts
grep -Fq 'type: "recovery"' supabase/functions/_shared/staff-onboarding-email.ts
grep -Fq 'https://api.resend.com/emails' supabase/functions/_shared/staff-onboarding-email.ts
grep -Fq 'RESEND_API_KEY' supabase/functions/_shared/staff-onboarding-email.ts
grep -Fq 'AUTH_EMAIL_FROM' supabase/functions/_shared/staff-onboarding-email.ts
grep -Fq 'accept-invitation.html' supabase/functions/_shared/staff-onboarding-email.ts
! grep -Fq 'action_link:' supabase/functions/create-organization-user/index.ts

grep -Fq 'complete_internal_staff_onboarding' supabase/functions/complete-staff-onboarding/index.ts
grep -Fq 'app_metadata: nextMetadata' supabase/functions/complete-staff-onboarding/index.ts
grep -Fq 'database_active: true' supabase/functions/complete-staff-onboarding/index.ts
grep -Fq 'role: String(onboarding.intended_role)' supabase/functions/complete-staff-onboarding/index.ts
grep -Fq 'organization_id: String(onboarding.organization_id)' supabase/functions/complete-staff-onboarding/index.ts

grep -Fq 'Pendiente de activación' docs/permissions-onboarding.js
grep -Fq 'Reenviar invitación' docs/permissions-onboarding.js
grep -Fq 'resend-staff-invitation' docs/permissions-onboarding.js
grep -Fq 'pending.has(option.value)' docs/permissions-onboarding.js
grep -Fq 'Crear e invitar' docs/permissions.html
grep -Fq 'permissions-onboarding.js?v=2026091601' docs/permissions.html

echo 'Staff onboarding smoke checks passed'
