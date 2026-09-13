#!/usr/bin/env bash
set -euo pipefail

targets=()
for d in docs src app; do
  [ -d "$d" ] && targets+=("$d")
done

[ "${#targets[@]}" -eq 0 ] && exit 0

pattern="from\(['\"](properties|rooms|tenancies|property_staff_assignments|property_staff_access_v2)['\"]\)|\.from\(['\"](properties|rooms|tenancies|property_staff_assignments|property_staff_access_v2)['\"]\)"

if grep -RInE "$pattern" "${targets[@]}" --include='*.js' --include='*.ts' --include='*.tsx' --include='*.jsx'; then
  echo "Legacy Supabase table referenced by application code."
  exit 1
fi

echo "No legacy schema references found."
