#!/usr/bin/env bash
set -euo pipefail

test -s docs/factory-reset.html
test -s docs/factory-reset.js
test -s docs/FACTORY_RESET_RUNBOOK.md
test -s supabase/functions/factory-reset-test-data/index.ts
test -s supabase/migrations/20260917170000_factory_reset_test_data_helper.sql

node --check docs/factory-reset.js

grep -Fq 'noindex,nofollow,noarchive' docs/factory-reset.html
grep -Fq 'RESTABLECER' docs/factory-reset.html
grep -Fq 'factory-reset-test-data' docs/factory-reset.js
grep -Fq 'action: "preview"' docs/factory-reset.js
grep -Fq 'action: "execute"' docs/factory-reset.js
grep -Fq 'RESET_FACTORY_TEST_DATA' docs/factory-reset.js

grep -Fq 'role !== "root"' supabase/functions/factory-reset-test-data/index.ts
grep -Fq 'aal2_required' supabase/functions/factory-reset-test-data/index.ts
grep -Fq 'factory_reset_requires_one_root_recovery_operator' supabase/functions/factory-reset-test-data/index.ts
grep -Fq 'factory_reset_operator_mfa_required' supabase/functions/factory-reset-test-data/index.ts
grep -Fq 'PREVIEW_TTL_MS = 5 * 60 * 1000' supabase/functions/factory-reset-test-data/index.ts
grep -Fq 'admin.storage.emptyBucket' supabase/functions/factory-reset-test-data/index.ts
grep -Fq 'admin.auth.admin.deleteUser' supabase/functions/factory-reset-test-data/index.ts
grep -Fq 'remainingUsers.length === 2' supabase/functions/factory-reset-test-data/index.ts
grep -Fq 'factory_reset_test_data_service' supabase/functions/factory-reset-test-data/index.ts

grep -Fq 'security definer' supabase/migrations/20260917170000_factory_reset_test_data_helper.sql
grep -Fq 'factory_reset_completed' supabase/migrations/20260917170000_factory_reset_test_data_helper.sql
grep -Fq 'tenant_task_workflow_templates_v2' docs/FACTORY_RESET_RUNBOOK.md
grep -Fq 'revoke all on function public.factory_reset_test_data_service' supabase/migrations/20260917170000_factory_reset_test_data_helper.sql
grep -Fq 'grant execute on function public.factory_reset_test_data_service' supabase/migrations/20260917170000_factory_reset_test_data_helper.sql

# Never expose privileged credentials or implement Storage cleanup through SQL metadata deletion.
! grep -Fq 'service_role' docs/factory-reset.html
! grep -Fq 'service_role' docs/factory-reset.js
! grep -Fq 'storage.objects' supabase/migrations/20260917170000_factory_reset_test_data_helper.sql

# The helper must remain explicitly test-only and contractually guarded.
grep -Fq 'Factory reset del entorno de pruebas' docs/SECURITY_CONTRACT.md
grep -Fq 'factory reset explícito del entorno de prueba' AGENTS.md

echo 'Factory reset helper smoke checks passed'
