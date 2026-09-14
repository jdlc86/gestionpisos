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
grep -q 'Sin escritura remota' docs/portfolio.html
grep -q 'ownerId' docs/portfolio.js
grep -q 'propertyId' docs/portfolio.js
grep -q 'archivedAt' docs/portfolio.js
grep -q 'showHistory' docs/portfolio.js

legacy_pattern="(properties|rooms|tenancies|property_staff_assignments|property_staff_access_v2)"
if grep -EIn "from\(['\"]${legacy_pattern}['\"]\)|\.from\(['\"]${legacy_pattern}['\"]\)" \
  docs/portfolio.html docs/portfolio.css docs/portfolio.js; then
  echo 'Legacy Supabase table referenced by Cartera.'
  exit 1
fi

echo 'Portfolio smoke checks passed'
