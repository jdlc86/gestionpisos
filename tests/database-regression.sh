#!/usr/bin/env bash
set -euo pipefail

repo_path="$PWD"
if command -v cygpath >/dev/null 2>&1; then
  repo_path="$(cygpath -w "$PWD")"
  export MSYS_NO_PATHCONV=1
fi

docker run --rm \
  -e POSTGRES_PASSWORD=local-regression-only \
  -v "$repo_path:/work:ro" \
  postgres:17-alpine \
  sh -ceu '
    docker-entrypoint.sh postgres -c listen_addresses="" &
    postgres_pid=$!

    cleanup() {
      kill "$postgres_pid" 2>/dev/null || true
      wait "$postgres_pid" 2>/dev/null || true
    }
    trap cleanup EXIT

    ready=0
    for attempt in $(seq 1 30); do
      if pg_isready -U postgres >/dev/null 2>&1; then
        sleep 1
        if kill -0 "$postgres_pid" 2>/dev/null \
          && pg_isready -U postgres >/dev/null 2>&1; then
          ready=1
          break
        fi
      fi
      sleep 1
    done

    if [ "$ready" -ne 1 ]; then
      echo "PostgreSQL did not become ready" >&2
      exit 1
    fi

    psql -v ON_ERROR_STOP=1 -U postgres \
      -f /work/tests/local-auth-bootstrap.sql
    psql -v ON_ERROR_STOP=1 -U postgres \
      -f /work/supabase/migrations/20260913000000_remote_baseline.sql
    psql -v ON_ERROR_STOP=1 -U postgres \
      -f /work/supabase/migrations/20260913205141_close_owners_and_occupancy_blockers.sql
    psql -v ON_ERROR_STOP=1 -U postgres \
      -f /work/supabase/migrations/20260914064353_beta0_photo_verification_tables.sql
    psql -v ON_ERROR_STOP=1 -U postgres \
      -f /work/supabase/migrations/20260914064402_beta0_photo_verification_rls.sql
    psql -v ON_ERROR_STOP=1 -U postgres \
      -f /work/supabase/migrations/20260914074246_beta0_photo_verification_write_policies.sql
    psql -v ON_ERROR_STOP=1 -U postgres \
      -f /work/tests/database-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres \
      -f /work/tests/photo-verification-regression.sql

    trap - EXIT
    cleanup
  '
