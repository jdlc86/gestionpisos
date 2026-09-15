#!/usr/bin/env bash
set -euo pipefail

test -s docs/portfolio.html
test -s docs/portfolio.css
test -s docs/portfolio.js

grep -Eq 'href="\./portfolio\.html"' docs/index.html
grep -q '>Propietarios<' docs/portfolio.html
grep -q '>Pisos<' docs/portfolio.html
grep -q '>Habitaciones<' docs/portfolio.html
grep -Eq 'href="\./portfolio\.css"' docs/portfolio.html
grep -Eq 'src="\./portfolio\.js"' docs/portfolio.html
grep -q 'type="module" src="./portfolio.js"' docs/portfolio.html
grep -q 'supabase-client.js' docs/portfolio.js
grep -q 'from("owners")' docs/portfolio.js
grep -q 'from("properties_v2")' docs/portfolio.js
grep -q 'from("rooms_v2")' docs/portfolio.js
grep -q 'from("audit_log_v2")' docs/portfolio.js
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


# Tenant save regression: inspect saveItem up to archiveItem and assert branch ordering.
python3 - <<'PY'
from pathlib import Path
s=Path("docs/portfolio.js").read_text()
save=s[s.index("async function saveItem"):s.index("async function archiveItem")]
owners_start=save.index('if (current === "owners") {')
properties_start=save.index('} else if (current === "properties") {', owners_start)
occupancies_start=save.index('} else if (current === "occupancies") {', properties_start)
rooms_start=save.index('} else {', occupancies_start)
owners=save[owners_start:properties_start]
occupancies=save[occupancies_start:rooms_start]
assert 'supabase.from("tenants_v2")' not in owners, "tenant save leaked into owners branch"
assert 'supabase.from("tenants_v2")' in occupancies, "tenant identity save missing from occupancies branch"
assert 'tenant_id: tenantId' in occupancies, "occupancy is not linked to tenant identity"
assert 'supabase.from("occupancies_v2")' in occupancies, "occupancy persistence missing"
print("PASS tenant save regression")
PY
