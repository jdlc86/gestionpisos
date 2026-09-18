#!/usr/bin/env bash
set -euo pipefail

mapfile -t files < <(find supabase/migrations -maxdepth 1 -type f -name '*.sql' -printf '%f\n' | sort)

if [ "${#files[@]}" -eq 0 ]; then
  echo "No migration files found" >&2
  exit 1
fi

bad=0
declare -A seen=()
for file in "${files[@]}"; do
  if [[ ! "$file" =~ ^([0-9]{14})_.+\.sql$ ]]; then
    echo "Invalid migration filename: $file" >&2
    bad=1
    continue
  fi
  version="${BASH_REMATCH[1]}"
  if [[ -n "${seen[$version]:-}" ]]; then
    echo "Duplicate migration version: $version (${seen[$version]} and $file)" >&2
    bad=1
  fi
  seen[$version]="$file"
done

if [ "$bad" -ne 0 ]; then
  exit 1
fi

test ! -e supabase/migrations/20260913000000_remote_baseline.sql
test -s tests/fixtures/20260913_remote_baseline.sql

echo "Migration history smoke checks passed: ${#files[@]} unique versions"
