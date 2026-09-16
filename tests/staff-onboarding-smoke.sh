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
grep -Fq 'complete_internal_staff_onboarding' docs/activate-account.js
grep -Fq 'updateUser({ password: password.value })' docs/activate-account.js
grep -Fq 'Cuenta activada. Ya puedes iniciar sesión.' docs/login.js
grep -Fq 'get_my_internal_staff_onboarding' docs/auth-guard.js

grep -Fq 'qsxtmmkftsohkqqmytbb.supabase.co' docs/accept-invitation.js
grep -Fq 'url.pathname !== "/auth/v1/verify"' docs/accept-invitation.js
grep -Fq 'history.replaceState' docs/accept-invitation.js
grep -Fq 'noindex,nofollow' docs/accept-invitation.html

test -s supabase/functions/_shared/staff-onboarding-email.ts
test -s supabase/functions/resend-staff-invitation/index.ts
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

grep -Fq 'Pendiente de activación' docs/permissions-onboarding.js
grep -Fq 'Reenviar invitación' docs/permissions-onboarding.js
grep -Fq 'resend-staff-invitation' docs/permissions-onboarding.js
grep -Fq 'pending.has(option.value)' docs/permissions-onboarding.js
grep -Fq 'Crear e invitar' docs/permissions.html
grep -Fq 'permissions-onboarding.js?v=2026091601' docs/permissions.html

echo 'Staff onboarding smoke checks passed'
