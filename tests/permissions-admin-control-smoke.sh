#!/usr/bin/env bash
set -euo pipefail

node --check docs/permissions.js
grep -Fq 'import("./permissions.js?v=202609169")' docs/permissions.html
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
! grep -Fq 'capability==="permission_management"' docs/permissions.js

echo 'Permissions administrative control smoke checks passed'
