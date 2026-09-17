#!/usr/bin/env bash
set -euo pipefail

test -s docs/WORKFLOW_ARCHITECTURE.md
test -s docs/WORKFLOW_IMPLEMENTATION_MAP.md
test -s docs/WORKFLOW_ENGINE_CONTRACT.md
test -s docs/WORKFLOW_STATUS.md
test -s docs/workflows.html
test -s docs/workflow-builder.html
test -s docs/workflow-builder.css
test -s docs/workflow-builder.js
test -s docs/workflow-definitions.html
test -s docs/workflow-definitions.css
test -s docs/workflow-definitions.js
node --check docs/workflow-builder.js
node --check docs/workflow-definitions.js

grep -Fq 'href="./workflows.html"' docs/index.html
grep -Fq '>🔄</span>Flujos de Trabajo' docs/index.html

grep -Fq 'data-workflow-module="builder"' docs/workflows.html
grep -Fq '>➕</span>Creador de Flujos' docs/workflows.html
grep -Fq 'href="./workflow-builder.html"' docs/workflows.html
grep -Fq 'data-workflow-module="definitions"' docs/workflows.html
grep -Fq '>🧩</span>Mis Flujos' docs/workflows.html
grep -Fq 'href="./workflow-definitions.html"' docs/workflows.html
grep -Fq 'data-workflow-module="photo-bank"' docs/workflows.html
grep -Fq '>📷</span>Banco Fotográfico' docs/workflows.html
grep -Fq 'href="./photo-patterns.html?from=workflows"' docs/workflows.html
grep -Fq 'data-workflow-module="tasks"' docs/workflows.html
grep -Fq '>📋</span>Tareas' docs/workflows.html
grep -Fq 'data-workflow-module="history"' docs/workflows.html
grep -Fq '>🕘</span>Historial' docs/workflows.html

grep -Fq './auth-guard.js' docs/workflows.html
grep -Fq './auth-guard.js' docs/workflow-builder.html
grep -Fq './auth-guard.js' docs/workflow-definitions.html
grep -Fq 'data-theme-toggle' docs/workflows.html
grep -Fq 'data-theme-toggle' docs/workflow-builder.html
grep -Fq 'data-theme-toggle' docs/workflow-definitions.html
grep -Fq 'class="ui-nav-icon"' docs/workflows.html

grep -Fq 'Borrador persistente' docs/workflow-builder.html
grep -Fq 'Paso 1 de 7' docs/workflow-builder.html
grep -Fq 'Paso 7 de 7' docs/workflow-builder.html
grep -Fq 'sessionStorage.setItem(DRAFT_KEY' docs/workflow-builder.js
grep -Fq 'save_workflow_definition_draft_v1' docs/workflow-builder.js
grep -Fq 'workflow_definitions_v2' docs/workflow-builder.js
grep -Fq 'Guardar borrador' docs/workflow-builder.html
grep -Fq 'Guardado no significa publicado.' docs/workflow-builder.html
grep -Fq 'photo-patterns.html?from=workflow-builder' docs/workflow-builder.html

grep -Fq 'workflow_definitions_v2' docs/workflow-definitions.js
grep -Fq 'Editar borrador' docs/workflow-definitions.js
grep -Fq 'Borrador guardado todavía no está publicado' docs/workflow-definitions.html || grep -Fq 'borrador guardado todavía no está publicado' docs/workflow-definitions.html

grep -Fq 'Definición → Versión publicada → Disparador → Ejecución' docs/WORKFLOW_ENGINE_CONTRACT.md
grep -Fq 'idempotency_key' docs/WORKFLOW_ENGINE_CONTRACT.md
grep -Fq 'tenant_tasks_v2' docs/WORKFLOW_ENGINE_CONTRACT.md
grep -Fq 'photo_patterns_v2' docs/WORKFLOW_ENGINE_CONTRACT.md
grep -Fq 'RLS obligatoria' docs/WORKFLOW_ENGINE_CONTRACT.md

# Transitional safety: the working legacy cleaning route remains reachable until
# the generic task runner has been implemented and validated end to end.
grep -Fq 'href="./cleaning.html"' docs/index.html
test -s docs/cleaning.html

# The implementation map must keep the no-parallel-engine decisions explicit.
grep -Fq 'tenant_tasks_v2' docs/WORKFLOW_IMPLEMENTATION_MAP.md
grep -Fq 'photo_patterns_v2' docs/WORKFLOW_IMPLEMENTATION_MAP.md
grep -Fq 'cleaning_plans_v2' docs/WORKFLOW_IMPLEMENTATION_MAP.md
grep -Fq 'workflow_definitions_v2' docs/WORKFLOW_IMPLEMENTATION_MAP.md

echo 'Workflow smoke checks passed'
