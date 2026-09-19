#!/usr/bin/env bash
set -euo pipefail

node --check docs/permissions.js
grep -Fq 'import("./permissions.js?v=202609170")' docs/permissions.html
grep -Fq 'assign_initial_admin_write_control' docs/permissions.js
grep -Fq 'id="initialWriteControlAdmin"' docs/permissions.js
grep -Fq 'Control administrativo de escritura' docs/permissions.js
grep -Fq 'writeHolder?.holder_user_id===me' docs/permissions.js
grep -Fq 'root_set_admin_write_control' docs/permissions.js
grep -Fq 'id="rootWriteControlAdmin"' docs/permissions.js
grep -Fq 'id="rootTransferWriteControl"' docs/permissions.js
grep -Fq 'id="rootRevokeWriteControl"' docs/permissions.js
grep -Fq 'Supervisión ROOT' docs/permissions.js
grep -Fq 'p_admin_user_id:null' docs/permissions.js
grep -Fq 'class="ghost remove-staff"' docs/permissions.js
grep -Fq 'deactivate_internal_staff_user' docs/permissions.js
grep -Fq 'disable-internal-staff-auth' docs/permissions.js
grep -Fq 'staff_write_control_transfer_required' supabase/migrations/20260916004853_internal_staff_deactivation.sql
grep -Fq 'staff_responsible_reassignment_required' supabase/migrations/20260916004853_internal_staff_deactivation.sql
! grep -Fq 'capability==="permission_management"' docs/permissions.js

echo 'Permissions administrative control smoke checks passed'

grep -Fq '<span>Puede recuperar ROOT</span>' docs/permissions.html
grep -Fq '.emergency-root-capability input[type="checkbox"]' docs/permissions.css
grep -Fq '[hidden]{display:none!important}' docs/app.css
