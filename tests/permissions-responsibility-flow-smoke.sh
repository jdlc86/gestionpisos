#!/usr/bin/env bash
set -euo pipefail

test -s docs/permissions-responsibility-flow.js
test -s docs/permissions-responsibility-flow.css
node --check docs/permissions-responsibility-flow.js

grep -Fq 'permissions-responsibility-flow.css?v=2026091601' docs/permissions.html
grep -Fq 'permissions-responsibility-flow.js?v=2026091601' docs/permissions.html
grep -Fq 'NO ASIGNADO' docs/permissions-responsibility-flow.js
grep -Fq 'deactivate_internal_staff_user_v2' docs/permissions-responsibility-flow.js
grep -Fq 'Dejar sin asignar' docs/permissions-responsibility-flow.js
grep -Fq 'Reasignar y eliminar' docs/permissions-responsibility-flow.js
grep -Fq 'Ver viviendas (' docs/permissions-responsibility-flow.js
grep -Fq 'properties.length<=3' docs/permissions-responsibility-flow.js
grep -Fq 'p_employee_user_id:null' docs/permissions-responsibility-flow.js

echo 'Permissions responsibility flow smoke checks passed'
