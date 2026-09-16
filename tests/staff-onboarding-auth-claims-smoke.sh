#!/usr/bin/env bash
set -euo pipefail

FILE='supabase/functions/complete-staff-onboarding/index.ts'
test -s "$FILE"

# The authoritative DB activation must occur before privileged Auth claims are written.
db_line=$(grep -n 'complete_internal_staff_onboarding' "$FILE" | head -1 | cut -d: -f1)
claims_line=$(grep -n 'app_metadata: nextMetadata' "$FILE" | head -1 | cut -d: -f1)
if [ -z "$db_line" ] || [ -z "$claims_line" ] || [ "$db_line" -ge "$claims_line" ]; then
  echo 'Auth claims must only be synchronized after authoritative DB activation.' >&2
  exit 1
fi

grep -Fq 'if (onboarding.status === "revoked")' "$FILE"
grep -Fq 'invalid_onboarding_role' "$FILE"
grep -Fq 'auth_metadata_sync_failed' "$FILE"
grep -Fq 'retryable: true' "$FILE"

echo 'Staff onboarding auth claims smoke checks passed'
