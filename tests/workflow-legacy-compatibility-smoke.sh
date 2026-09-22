#!/usr/bin/env bash
set -euo pipefail
trap 'echo "workflow-legacy-compatibility-smoke failed at line $LINENO: $BASH_COMMAND" >&2' ERR

test -s docs/WORKFLOW_LEGACY_CLOSURE_CONTRACT.md
test -s tests/workflow-legacy-closure-regression.sql

create_refs="$(grep -Rl --include='*.js' 'create_tenant_task_v2' docs | sort || true)"
action_refs="$(grep -Rl --include='*.js' 'apply_tenant_task_action_v2' docs | sort || true)"

test "$create_refs" = "docs/portfolio.js"
test "$action_refs" = "docs/portfolio.js"

grep -Fq 'workflow_task_id' docs/cleaning.js
grep -Fq 'legacyTaskId=params.get("task_id")' docs/cleaning.js
grep -Fq "./cleaning.html?task_id=" docs/photo-camera.js
grep -Fq 'workflow_task_id' supabase/functions/my-cleaning-checklist/index.ts
grep -Fq 'workflow_task_reference_required' supabase/functions/my-cleaning-checklist/index.ts

grep -Fq 'v_task.task_type='''workflow'''' supabase/migrations/20260920014500_workflow_tenant_access_revocation.sql || grep -R -Fq 'workflow_task_requires_atomic_action' supabase/migrations

echo 'WF09 legacy compatibility smoke checks passed'
