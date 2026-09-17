#!/usr/bin/env bash
set -euo pipefail

test -s docs/WORKFLOW_ARCHITECTURE.md
test -s docs/WORKFLOW_IMPLEMENTATION_MAP.md
test -s docs/workflows.html

grep -Fq 'href="./workflows.html"' docs/index.html
grep -Fq '>🔄</span>Flujos de Trabajo' docs/index.html

grep -Fq 'data-workflow-module="builder"' docs/workflows.html
grep -Fq '>➕</span>Creador de Flujos' docs/workflows.html
grep -Fq 'data-workflow-module="definitions"' docs/workflows.html
grep -Fq '>🧩</span>Mis Flujos' docs/workflows.html
grep -Fq 'data-workflow-module="photo-bank"' docs/workflows.html
grep -Fq '>📷</span>Banco Fotográfico' docs/workflows.html
grep -Fq 'href="./photo-patterns.html?from=workflows"' docs/workflows.html
grep -Fq 'data-workflow-module="tasks"' docs/workflows.html
grep -Fq '>📋</span>Tareas' docs/workflows.html
grep -Fq 'data-workflow-module="history"' docs/workflows.html
grep -Fq '>🕘</span>Historial' docs/workflows.html

grep -Fq './auth-guard.js' docs/workflows.html
grep -Fq 'data-theme-toggle' docs/workflows.html
grep -Fq 'class="ui-nav-icon"' docs/workflows.html

# Transitional safety: the working legacy cleaning route remains reachable until
# the generic task runner has been implemented and validated end to end.
grep -Fq 'href="./cleaning.html"' docs/index.html
test -s docs/cleaning.html

# The implementation map must keep the no-parallel-engine decisions explicit.
grep -Fq 'tenant_tasks_v2' docs/WORKFLOW_IMPLEMENTATION_MAP.md
grep -Fq 'photo_patterns_v2' docs/WORKFLOW_IMPLEMENTATION_MAP.md
grep -Fq 'cleaning_plans_v2' docs/WORKFLOW_IMPLEMENTATION_MAP.md
grep -Fq 'no se crean tablas nuevas de workflow' docs/WORKFLOW_IMPLEMENTATION_MAP.md

echo 'Workflow smoke checks passed'