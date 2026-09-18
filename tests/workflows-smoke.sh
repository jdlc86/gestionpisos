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
test -s docs/workflow-applications.html
test -s docs/workflow-applications.css
test -s docs/workflow-applications.js
test -s docs/WORKFLOW_APPLICATIONS_CONTRACT.md
test -s docs/WORKFLOW_EXECUTION_CONTRACT.md
test -s docs/WORKFLOW_TASKS_CONTRACT.md
test -s docs/workflow-tasks.html
test -s docs/workflow-tasks.css
test -s docs/workflow-tasks.js
node --check docs/workflow-builder.js
node --check docs/workflow-definitions.js
node --check docs/workflow-applications.js
node --check docs/workflow-tasks.js

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
grep -Fq 'href="./workflow-tasks.html"' docs/workflows.html
grep -Fq 'data-workflow-module="history"' docs/workflows.html
grep -Fq '>🕘</span>Historial' docs/workflows.html

grep -Fq './auth-guard.js' docs/workflows.html
grep -Fq './auth-guard.js' docs/workflow-builder.html
grep -Fq './auth-guard.js' docs/workflow-definitions.html
grep -Fq './auth-guard.js' docs/workflow-applications.html
grep -Fq './auth-guard.js' docs/workflow-tasks.html
grep -Fq 'data-theme-toggle' docs/workflows.html
grep -Fq 'data-theme-toggle' docs/workflow-builder.html
grep -Fq 'data-theme-toggle' docs/workflow-definitions.html
grep -Fq 'data-theme-toggle' docs/workflow-applications.html
grep -Fq 'data-theme-toggle' docs/workflow-tasks.html
grep -Fq 'class="ui-nav-icon"' docs/workflows.html

grep -Fq 'Borrador incompleto' docs/workflow-builder.html
grep -Fq 'Paso 1 de 7' docs/workflow-builder.html
grep -Fq 'Paso 7 de 7' docs/workflow-builder.html
grep -Fq 'sessionStorage.setItem(DRAFT_KEY' docs/workflow-builder.js
grep -Fq 'save_workflow_definition_draft_v1' docs/workflow-builder.js
grep -Fq 'workflow_definitions_v2' docs/workflow-builder.js
grep -Fq 'Guardar borrador' docs/workflow-builder.html
grep -Fq 'Guardar no significa publicar.' docs/workflow-builder.html
grep -Fq 'Pendiente · selecciona un tipo' docs/workflow-builder.html
grep -Fq 'Pendiente · selecciona un ámbito' docs/workflow-builder.html
grep -Fq 'Pendiente · selecciona una activación' docs/workflow-builder.html
grep -Fq 'Pendiente · selecciona una asignación' docs/workflow-builder.html
grep -Fq 'Pendiente · selecciona cómo termina' docs/workflow-builder.html
! grep -Fq 'name="stepAccept" checked' docs/workflow-builder.html
! grep -Fq 'name="notifyOnCreate" checked' docs/workflow-builder.html
grep -Fq 'const AUTHORING_VERSION=2' docs/workflow-builder.js
grep -Fq 'id="scheduledAt"' docs/workflow-builder.html
grep -Fq 'id="customRecurrenceRow"' docs/workflow-builder.html
grep -Fq '.builder-panel [hidden]{display:none!important}' docs/workflow-builder.css
grep -Fq './workflow-builder.css?v=2026091805' docs/workflow-builder.html
grep -Fq 'name="customEvery"' docs/workflow-builder.html
grep -Fq 'name="customUnit"' docs/workflow-builder.html
grep -Fq 'toggleDependentRow' docs/workflow-builder.js
grep -Fq 'data.triggerType==="scheduled_once"' docs/workflow-builder.js
grep -Fq 'data.recurrence==="custom"' docs/workflow-builder.js
grep -Fq 'authoringVersion:AUTHORING_VERSION' docs/workflow-builder.js
grep -Fq 'legacyDraftNeedsReview' docs/workflow-builder.js
grep -Fq 'authoring_complete' docs/workflow-builder.js
grep -Fq 'No se creó una revisión nueva.' docs/workflow-builder.js
grep -Fq 'photo-patterns.html?from=workflow-builder' docs/workflow-builder.html
grep -Fq 'id="photoBankLink"' docs/workflow-builder.html
grep -Fq 'href="./photo-patterns.html?from=workflow-builder" hidden' docs/workflow-builder.html
grep -Fq 'function updatePhotoResource()' docs/workflow-builder.js
grep -Fq 'photoBankLink.hidden=!checked("stepPhoto")' docs/workflow-builder.js
grep -Fq './workflow-builder.js?v=2026091806' docs/workflow-builder.html

grep -Fq 'workflow_definitions_v2' docs/workflow-definitions.js
grep -Fq 'Borrador incompleto' docs/workflow-definitions.js
grep -Fq 'authoring_complete' docs/workflow-definitions.js
grep -Fq 'Completar borrador' docs/workflow-definitions.js
grep -Fq 'function activationText(row)' docs/workflow-definitions.js
grep -Fq 'meta("Activación",activationText(row))' docs/workflow-definitions.js
grep -Fq 'updated_at,draft_spec' docs/workflow-definitions.js
grep -Fq './workflow-definitions.js?v=2026091804' docs/workflow-definitions.html
grep -Fq 'puede publicarse como versión inmutable' docs/workflow-definitions.html
grep -Fq 'publish_workflow_definition_v1' docs/workflow-definitions.js
grep -Fq 'workflow-applications.html?definition=' docs/workflow-definitions.js
grep -Fq 'Publicar versión' docs/workflow-definitions.js
grep -Fq 'create_workflow_application_v1' docs/workflow-applications.js
grep -Fq 'archive_workflow_application_v1' docs/workflow-applications.js
grep -Fq 'properties_v2' docs/workflow-applications.js
grep -Fq 'rooms_v2' docs/workflow-applications.js
grep -Fq 'occupancies_v2' docs/workflow-applications.js
grep -Fq '.application-card [hidden]{display:none!important}' docs/workflow-applications.css
grep -Fq './workflow-applications.css?v=2026091803' docs/workflow-applications.html
grep -Fq './workflow-applications.js?v=2026091803' docs/workflow-applications.html
grep -Fq 'podrás crear una ejecución manual pendiente' docs/workflow-applications.html
grep -Fq 'Definición → Versión publicada → Aplicación concreta' docs/WORKFLOW_APPLICATIONS_CONTRACT.md
grep -Fq 'workflow_applications_v2' docs/WORKFLOW_APPLICATIONS_CONTRACT.md
grep -Fq 'execute_workflow_application_now_v1' docs/workflow-applications.js
grep -Fq 'workflow_executions_v2' docs/workflow-applications.js
grep -Fq 'EXECUTION_KEY_PREFIX' docs/workflow-applications.js
grep -Fq 'Ejecutar ahora' docs/workflow-applications.js
grep -Fq 'Ejecución creada en estado Pendiente y tarea materializada sin duplicados.' docs/workflow-applications.js
grep -Fq 'Definición → Versión publicada → Aplicación concreta → Ejecutar ahora → Ejecución' docs/WORKFLOW_EXECUTION_CONTRACT.md
grep -Fq 'tenant_id NOT NULL' docs/WORKFLOW_EXECUTION_CONTRACT.md
grep -Fq 'workflow_executions_v2' docs/WORKFLOW_EXECUTION_CONTRACT.md
grep -Fq 'workflow_execution_events_v2' docs/WORKFLOW_EXECUTION_CONTRACT.md
grep -Fq 'tenant_tasks_v2' docs/WORKFLOW_TASKS_CONTRACT.md
grep -Fq "source_kind='workflow_execution'" docs/WORKFLOW_TASKS_CONTRACT.md
grep -Fq 'materialize_workflow_execution_task_v1' docs/WORKFLOW_TASKS_CONTRACT.md
grep -Fq 'workflow_tasks' docs/WORKFLOW_TASKS_CONTRACT.md
grep -Fq 'tenant_tasks_v2' docs/workflow-tasks.js
grep -Fq 'source_kind' docs/workflow-tasks.js
grep -Fq 'Asignadas a mí' docs/workflow-tasks.html
grep -Fq 'workflow-tasks.html' docs/sw.js
grep -Fq 'workflow-applications.html' docs/sw.js

grep -Fq 'Definición → Versión publicada → Aplicación concreta → Disparador → Ejecución' docs/WORKFLOW_ENGINE_CONTRACT.md
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
