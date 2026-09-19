#!/usr/bin/env bash
set -euo pipefail

test -s docs/portfolio.html
test -s docs/portfolio.css
test -s docs/portfolio.js

grep -Eq 'href="\./portfolio\.html"' docs/index.html
grep -q '>Propietarios<' docs/portfolio.html
grep -q '>Pisos<' docs/portfolio.html
grep -q '>Habitaciones<' docs/portfolio.html
grep -Eq 'href="\./portfolio\.css\?v=[0-9]+"' docs/portfolio.html
grep -Eq 'src="\./portfolio\.js\?v=[0-9]+"' docs/portfolio.html
grep -Eq 'type="module" src="\./portfolio\.js\?v=[0-9]+"' docs/portfolio.html
grep -q 'supabase-client.js' docs/portfolio.js
grep -q 'from("owners")' docs/portfolio.js
grep -q 'from("properties_v2")' docs/portfolio.js
grep -q 'from("rooms_v2")' docs/portfolio.js
grep -q 'from("audit_log_v2")' docs/portfolio.js
grep -Fq '.from("tenant_tasks_v2")' docs/portfolio.js
grep -Fq '.is("removed_at",null)' docs/portfolio.js
grep -Fq './portfolio.js?v=2026091921' docs/portfolio.html
grep -q 'owner_has_active_properties' docs/portfolio.js
grep -q 'property_has_active_rooms' docs/portfolio.js
grep -q 'showHistory' docs/portfolio.js
if grep -q 'demostración local\|Sin escritura remota\|no envía datos a Supabase' docs/portfolio.html; then
  echo 'Cartera still advertises local-only behavior.'
  exit 1
fi

legacy_pattern="(properties|rooms|tenancies|property_staff_assignments|property_staff_access_v2)"
if grep -EIn "from\(['\"]${legacy_pattern}['\"]\)|\.from\(['\"]${legacy_pattern}['\"]\)" \
  docs/portfolio.html docs/portfolio.css docs/portfolio.js; then
  echo 'Legacy Supabase table referenced by Cartera.'
  exit 1
fi

echo 'Portfolio smoke checks passed'


# Tenant onboarding regression: creation must use the atomic property-scoped RPC.
python3 - <<'PY'
from pathlib import Path
s=Path("docs/portfolio.js").read_text()
save=s[s.index("async function saveItem"):s.index("async function archiveItem")]
assert 'supabase.rpc("create_tenant_occupancy_v3"' in save, "atomic tenant onboarding RPC missing"
assert 'p_property_id: data.propertyId' in save and 'p_room_id: data.roomId' in save, "property/room scope missing"
tenant_branch=save[save.index('else if (current === "occupancies")'):save.index('    } else {\n      const payload = {\n        property_id:', save.index('else if (current === "occupancies")'))]
assert 'createdTenantId' not in tenant_branch, "manual tenant rollback should be removed from tenant flow"
assert 'tenant rollback failed' not in tenant_branch, "legacy rollback path remains in tenant flow"
print("PASS atomic tenant onboarding regression")
PY

grep -Fq 'id="saveErrorDialog"' docs/portfolio.html
grep -Fq 'saveErrorDialog.showModal()' docs/portfolio.js
grep -Fq 'saveErrorAcceptBtn' docs/portfolio.js
grep -Fq 'saveErrorCancelBtn' docs/portfolio.js
grep -Fq 'error?.code === "23505"' docs/portfolio.js
grep -Fq 'error?.code === "23503"' docs/portfolio.js
grep -Fq 'error?.code === "23514"' docs/portfolio.js
grep -Fq 'No se pudo guardar el inquilino.' docs/portfolio.js
grep -Fq 'error?.code === "23P01"' docs/portfolio.js
grep -Fq 'Esta habitación ya tiene un inquilino durante las fechas seleccionadas' docs/portfolio.js

# Operator portfolio regression: operational staff must not load owner data or structural views.
python3 - <<'PY'
from pathlib import Path
s=Path("docs/portfolio.js").read_text()
assert 'operationalPortfolio = !["root","admin"].includes(role)' in s
assert 'current = "occupancies"' in s
assert 'button.hidden = !allowed' in s
load_start=s.index("async function loadPortfolio")
load_end=s.index("\nfunction ", load_start)
load=s[load_start:load_end]
marker='if (operationalPortfolio) {\n    state.owners = [];\n  } else {'
assert marker in load, "owner split missing"
operator_prefix=load[:load.index(marker)+len('if (operationalPortfolio) {\n    state.owners = [];')]
admin_suffix=load[load.index(marker)+len(marker):]
assert 'from("owners")' not in operator_prefix, "operator path must not query owners"
assert 'from("owners")' in admin_suffix, "admin path must retain owners query"
print("PASS scoped operator portfolio regression")
PY

# Operator write-state regression.
grep -Fq '.from("property_staff_access_v3")' docs/portfolio.js
grep -Fq 'operationalCanWrite = activeAssignments.some(item => item.can_write === true)' docs/portfolio.js
grep -Fq 'action.disabled = !operationalCanWrite' docs/portfolio.js
grep -Fq 'No tienes viviendas asignadas actualmente.' docs/portfolio.js
grep -Fq 'Acceso de solo lectura.' docs/portfolio.js
