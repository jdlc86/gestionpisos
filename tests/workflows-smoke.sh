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
test -s docs/WORKFLOW_ACTIONS_CONTRACT.md
test -s docs/WORKFLOW_PHOTO_EVIDENCE_CONTRACT.md
test -s docs/workflow-tasks.html
test -s docs/workflow-tasks.css
test -s docs/workflow-tasks.js
node --check docs/workflow-builder.js
node --check docs/workflow-definitions.js
node --check docs/workflow-applications.js
node --check docs/workflow-tasks.js

grep -Fq 'href="./workflows.html"' docs/index.html
grep -Fq 'Flujos de Trabajo' docs/index.html

grep -Fq 'data-workflow-module="builder"' docs/workflows.html
grep -Fq 'Creador de Flujos' docs/workflows.html
grep -Fq 'href="./workflow-builder.html"' docs/workflows.html
grep -Fq 'data-workflow-module="definitions"' docs/workflows.html
grep -Fq 'Mis Flujos' docs/workflows.html
grep -Fq 'href="./workflow-definitions.html"' docs/workflows.html
grep -Fq 'data-workflow-module="photo-bank"' docs/workflows.html
grep -Fq 'Banco Fotográfico' docs/workflows.html
grep -Fq 'href="./photo-patterns.html?from=workflows"' docs/workflows.html
grep -Fq 'data-workflow-module="tasks"' docs/workflows.html
grep -Fq 'Tareas' docs/workflows.html
grep -Fq 'href="./workflow-tasks.html"' docs/workflows.html
grep -Fq 'data-workflow-module="history"' docs/workflows.html
grep -Fq 'Historial' docs/workflows.html

grep -Fq './auth-guard.js' docs/workflows.html
grep -Fq './auth-guard.js' docs/workflow-builder.html
grep -Fq './auth-guard.js' docs/workflow-definitions.html
grep -Fq './auth-guard.js' docs/workflow-applications.html
grep -Fq './auth-guard.js' docs/workflow-tasks.html
! grep -Fq 'data-theme-toggle' docs/workflows.html
! grep -Fq 'data-theme-toggle' docs/workflow-builder.html
! grep -Fq 'data-theme-toggle' docs/workflow-definitions.html
! grep -Fq 'data-theme-toggle' docs/workflow-applications.html
! grep -Fq 'data-theme-toggle' docs/workflow-tasks.html
grep -Fq 'data-theme-toggle' docs/index.html
grep -Fq 'class="premium-icon"' docs/workflows.html
grep -Fq 'class="card premium-nav-card"' docs/workflows.html
grep -Fq 'data-premium-icon="builder"' docs/workflows.html
grep -Fq 'data-premium-icon="camera"' docs/workflows.html
grep -Fq 'availability-badge' docs/workflows.html
! grep -Fq '<span class="ui-nav-icon"' docs/workflows.html
grep -Fq 'AllaisoPremiumIcons' docs/app.js
! grep -Fq '➕' docs/workflows.html
! grep -Fq '🧩' docs/workflows.html
! grep -Fq '📷' docs/workflows.html
! grep -Fq '📋' docs/workflows.html

grep -Fq 'id="builderDraftsView"' docs/workflow-builder.html
grep -Fq 'id="builderEditorView"' docs/workflow-builder.html
grep -Fq 'id="builderDrafts"' docs/workflow-builder.html
grep -Fq 'id="builderDraftSearch"' docs/workflow-builder.html
grep -Fq 'id="builderDraftFilter"' docs/workflow-builder.html
grep -Fq 'id="builderDraftLoadMore"' docs/workflow-builder.html
grep -Fq 'id="builderExitEditor"' docs/workflow-builder.html
grep -Fq 'id="builderExitDialog"' docs/workflow-builder.html
grep -Fq 'id="builderSaveExitInline"' docs/workflow-builder.html
grep -Fq 'id="builderPublish"' docs/workflow-builder.html
grep -Fq '>Nuevo flujo</a>' docs/workflow-builder.html
grep -Fq 'Paso 1 de 7' docs/workflow-builder.html
grep -Fq 'Paso 7 de 7' docs/workflow-builder.html
grep -Fq 'sessionStorage.setItem(DRAFT_KEY' docs/workflow-builder.js
grep -Fq 'save_workflow_definition_draft_v1' docs/workflow-builder.js
grep -Fq 'save_workflow_definition_revision_draft_v1' docs/workflow-builder.js
grep -Fq 'publish_workflow_definition_v1' docs/workflow-builder.js
grep -Fq 'publish_workflow_definition_revision_v1' docs/workflow-builder.js
grep -Fq 'workflow_definition_revision_drafts_v2' docs/workflow-builder.js
grep -Fq 'loadDraftWorkspace' docs/workflow-builder.js
grep -Fq 'renderDraftWorkspace' docs/workflow-builder.js
grep -Fq 'filteredDraftItems' docs/workflow-builder.js
grep -Fq 'draftVisibleLimit=12' docs/workflow-builder.js
grep -Fq 'requestExitEditor' docs/workflow-builder.js
grep -Fq 'hasUnsavedChanges' docs/workflow-builder.js
grep -Fq 'clearLocalDraftCache' docs/workflow-builder.js
grep -Fq 'sessionStorage.removeItem(DRAFT_KEY)' docs/workflow-builder.js
grep -Fq 'window.addEventListener("beforeunload"' docs/workflow-builder.js
grep -Fq 'Se restauró la última revisión guardada.' docs/workflow-builder.js
grep -Fq '.builder-view[hidden]{display:none!important}' docs/workflow-builder.css
grep -Fq '.builder-drafts-list{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr))' docs/workflow-builder.css
grep -Fq '.builder-exit-dialog' docs/workflow-builder.css
grep -Fq 'class="builder-back-link"' docs/workflow-builder.html
grep -Fq 'class="builder-back-icon"' docs/workflow-builder.html
! grep -Fq '← Volver' docs/workflow-builder.html
grep -Fq 'aria-label="Volver a borradores"' docs/workflow-builder.html
grep -Fq 'id="builderClear" type="button" class="builder-action builder-action--neutral">Descartar cambios</button>' docs/workflow-builder.html
! grep -Fq 'Descartar cambios locales' docs/workflow-builder.html
grep -Fq '.builder-action--neutral{' docs/workflow-builder.css
grep -Fq 'grid-template-columns:auto minmax(0,1fr) auto' docs/workflow-builder.css
grep -Fq 'builder-action builder-action--primary' docs/workflow-builder.html
grep -Fq 'body.builder-editor-active .topbar{display:none}' docs/workflow-builder.css
grep -Fq 'background:var(--ui-action)' docs/workflow-builder.css
grep -Fq 'document.body.classList.toggle("builder-editor-active",editorRequested)' docs/workflow-builder.js
grep -Fq 'desktop-home-link' docs/workflow-builder.html
! grep -Fq '<section class="hero">' docs/workflow-builder.html
! grep -Fq 'Autoría y operación están separadas' docs/workflow-builder.html
grep -Fq 'id="builderSave" type="button" class="builder-action">Guardar</button>' docs/workflow-builder.html
grep -Fq '<strong>Guardar no publica.</strong>' docs/workflow-builder.html
grep -Fq 'Pendiente · selecciona un tipo' docs/workflow-builder.html
grep -Fq 'Pendiente · selecciona un ámbito' docs/workflow-builder.html
grep -Fq 'Pendiente · selecciona una activación' docs/workflow-builder.html
grep -Fq 'Pendiente · selecciona una asignación' docs/workflow-builder.html
grep -Fq 'Pendiente · selecciona cómo termina' docs/workflow-builder.html
! grep -Fq 'name="stepAccept" checked' docs/workflow-builder.html
! grep -Fq 'name="notifyOnCreate" checked' docs/workflow-builder.html
grep -Fq 'const AUTHORING_VERSION=2' docs/workflow-builder.js
grep -Fq 'gestionpisos.workflow-builder.draft.v3' docs/workflow-builder.js
grep -Fq 'LEGACY_DRAFT_KEY' docs/workflow-builder.js
grep -Fq 'if(loadingServerDraft||currentDefinitionId)return' docs/workflow-builder.js
grep -Fq 'Requerir decisión del asignado: Aceptar / Rechazar' docs/workflow-builder.html
grep -Fq 'Decisión Aceptar / Rechazar' docs/workflow-builder.js
grep -Fq 'id="scheduledAt"' docs/workflow-builder.html
grep -Fq 'id="customRecurrenceRow"' docs/workflow-builder.html
grep -Fq '.builder-panel [hidden]{display:none!important}' docs/workflow-builder.css
grep -Fq './workflow-builder.css?v=2026091910' docs/workflow-builder.html
grep -Fq 'name="customEvery"' docs/workflow-builder.html
grep -Fq 'name="customUnit"' docs/workflow-builder.html
grep -Fq 'toggleDependentRow' docs/workflow-builder.js
grep -Fq 'data.triggerType==="scheduled_once"' docs/workflow-builder.js
grep -Fq 'data.recurrence==="custom"' docs/workflow-builder.js
grep -Fq 'authoringVersion:AUTHORING_VERSION' docs/workflow-builder.js
grep -Fq 'legacyDraftNeedsReview' docs/workflow-builder.js
grep -Fq 'authoring_complete' docs/workflow-builder.js
grep -Fq 'Sin cambios · revisión' docs/workflow-builder.js
grep -Fq 'photo-patterns.html?from=workflow-builder' docs/workflow-builder.html
grep -Fq 'id="photoBankLink"' docs/workflow-builder.html
grep -Fq 'href="./photo-patterns.html?from=workflow-builder" hidden' docs/workflow-builder.html
grep -Fq 'function updatePhotoResource()' docs/workflow-builder.js
grep -Fq 'photoBankLink.hidden=!checked("stepPhoto")' docs/workflow-builder.js
grep -Fq './workflow-builder.js?v=2026091910' docs/workflow-builder.html

grep -Fq 'workflow_definitions_v2' docs/workflow-definitions.js
grep -Fq '.eq("status","published")' docs/workflow-definitions.js
grep -Fq 'workflow_definition_revision_drafts_v2' docs/workflow-definitions.js
grep -Fq 'start_workflow_definition_revision_v1' docs/workflow-definitions.js
grep -Fq 'Crear nueva versión' docs/workflow-definitions.js
grep -Fq 'Continuar nueva versión' docs/workflow-definitions.js
grep -Fq 'workflow-applications.html?definition=' docs/workflow-definitions.js
grep -Fq './workflow-definitions.js?v=2026091901' docs/workflow-definitions.html
grep -Fq './workflow-definitions.css?v=2026091903' docs/workflow-definitions.html
grep -Fq 'Solo recetas publicadas; los borradores se gestionan en el Creador.' docs/workflow-definitions.html
! grep -Fq 'Completar borrador' docs/workflow-definitions.js
! grep -Fq 'Publicar versión' docs/workflow-definitions.js
! grep -Fq 'publish_workflow_definition_v1' docs/workflow-definitions.js
grep -Fq 'create_workflow_application_v2' docs/workflow-applications.js
grep -Fq 'archive_workflow_application_v1' docs/workflow-applications.js
grep -Fq 'properties_v2' docs/workflow-applications.js
grep -Fq 'rooms_v2' docs/workflow-applications.js
grep -Fq 'occupancies_v2' docs/workflow-applications.js
grep -Fq '.application-card [hidden]{display:none!important}' docs/workflow-applications.css
grep -Fq './workflow-applications.css?v=2026091903' docs/workflow-applications.html
grep -Fq './workflow-applications.js?v=2026091805' docs/workflow-applications.html
grep -Fq 'crear una ejecución manual y su tarea asociada' docs/workflow-applications.html
grep -Fq 'Definición → Versión publicada → Aplicación concreta' docs/WORKFLOW_APPLICATIONS_CONTRACT.md
grep -Fq 'workflow_applications_v2' docs/WORKFLOW_APPLICATIONS_CONTRACT.md
grep -Fq 'execute_workflow_application_now_v1' docs/workflow-applications.js
grep -Fq 'workflow_executions_v2' docs/workflow-applications.js
grep -Fq 'EXECUTION_KEY_PREFIX' docs/workflow-applications.js
grep -Fq 'Ejecutar ahora' docs/workflow-applications.js
grep -Fq 'Ejecución creada en estado Pendiente y tarea materializada sin duplicados.' docs/workflow-applications.js
grep -Fq 'Definición → Versión publicada → Aplicación concreta → Ejecutar ahora → Ejecución' docs/WORKFLOW_EXECUTION_CONTRACT.md
grep -Fq "source_kind='workflow_execution'" docs/WORKFLOW_EXECUTION_CONTRACT.md
grep -Fq 'workflow_executions_v2' docs/WORKFLOW_EXECUTION_CONTRACT.md
grep -Fq 'workflow_execution_events_v2' docs/WORKFLOW_EXECUTION_CONTRACT.md
grep -Fq 'Tarea visible → Acción autorizada → Transacción única' docs/WORKFLOW_ACTIONS_CONTRACT.md
grep -Fq 'apply_workflow_task_action_v1' docs/WORKFLOW_ACTIONS_CONTRACT.md
grep -Fq 'workflow_task_requires_atomic_action' docs/WORKFLOW_ACTIONS_CONTRACT.md
grep -Fq 'Aceptar y completar' docs/WORKFLOW_ACTIONS_CONTRACT.md
grep -Fq 'tenant_tasks_v2' docs/WORKFLOW_TASKS_CONTRACT.md
grep -Fq "source_kind='workflow_execution'" docs/WORKFLOW_TASKS_CONTRACT.md
grep -Fq 'materialize_workflow_execution_task_v1' docs/WORKFLOW_TASKS_CONTRACT.md
grep -Fq 'workflow_tasks' docs/WORKFLOW_TASKS_CONTRACT.md
node --check docs/workflow-tasks.js
grep -Fq 'tenant_tasks_v2' docs/workflow-tasks.js
grep -Fq 'source_kind' docs/workflow-tasks.js
grep -Fq 'apply_workflow_task_action_v1' docs/workflow-tasks.js
grep -Fq 'ACTION_KEY_PREFIX' docs/workflow-tasks.js
grep -Fq 'Aceptar y completar' docs/WORKFLOW_ACTIONS_CONTRACT.md
grep -Fq 'Tarea y ejecución actualizadas juntas' docs/workflow-tasks.js
grep -Fq 'Indica el motivo del rechazo:' docs/workflow-tasks.js
grep -Fq 'task-action--reject' docs/workflow-tasks.js
grep -Fq 'task-action--reject' docs/workflow-tasks.css
grep -Fq 'Rechazar' docs/WORKFLOW_ACTIONS_CONTRACT.md
grep -Fq 'motivo obligatorio' docs/WORKFLOW_ACTIONS_CONTRACT.md
grep -Fq 'Aprobar revisión' docs/WORKFLOW_ACTIONS_CONTRACT.md
grep -Fq 'review_approve' docs/WORKFLOW_ACTIONS_CONTRACT.md
grep -Fq 'workflowPhotoReviewUrl' docs/workflow-tasks.js
grep -Fq 'Revisar evidencias' docs/workflow-tasks.js
grep -Fq 'canRenderWorkflowAction' docs/workflow-tasks.js
grep -Fq 'loadManagerAccess' docs/workflow-tasks.js
grep -Fq '.from("user_roles")' docs/workflow-tasks.js
grep -Fq 'managerOrganizationIds' docs/workflow-tasks.js
! grep -Fq 'currentUser?.app_metadata?.role' docs/workflow-tasks.js
grep -Fq 'review_reject' docs/workflow-tasks.js
grep -Fq 'task-actions' docs/workflow-tasks.css
grep -Fq './workflow-tasks.css?v=2026091910' docs/workflow-tasks.html
grep -Fq './workflow-tasks.js?v=2026091910' docs/workflow-tasks.html
grep -Fq 'cambian tarea y ejecución juntas' docs/workflow-tasks.html

grep -Fq 'workflow_execution_photo_resources_v2' docs/workflow-tasks.js
grep -Fq 'Hacer foto' docs/workflow-tasks.js
grep -Fq 'Continuar foto' docs/workflow-tasks.js
grep -Fq 'workflow_resource_id' docs/workflow-tasks.js
grep -Fq 'applicationPhotoPatterns' docs/workflow-applications.html
grep -Fq 'workflow_application_photo_resources_v2' docs/workflow-applications.js
grep -Fq 'p_photo_pattern_ids' docs/workflow-applications.js
grep -Fq 'Selecciona uno o varios patrones' docs/workflow-applications.js
grep -Fq 'Aplicación concreta → Patrones vinculados → Ejecución' docs/WORKFLOW_PHOTO_EVIDENCE_CONTRACT.md
grep -Fq 'submit_workflow_photo_verification_v1' docs/WORKFLOW_PHOTO_EVIDENCE_CONTRACT.md
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

grep -Fq 'ejecución pendiente y su tarea asociada' docs/workflow-applications.js

grep -Fq 'class="builder-editor-state"' docs/workflow-builder.html
grep -Fq '.builder-editor-state::before' docs/workflow-builder.css
grep -Fq 'builderBadge.textContent=state.complete?"Listo":"Borrador"' docs/workflow-builder.js
grep -Fq 'builderBadge.title=state.complete?completeLabel:"Borrador incompleto"' docs/workflow-builder.js

grep -Fq 'width:max-content' docs/workflow-definitions.css
grep -Fq 'justify-self:start' docs/workflow-definitions.css
grep -Fq 'white-space:nowrap' docs/workflow-definitions.css
grep -Fq 'width:max-content' docs/workflow-applications.css

grep -Fq 'id="checklistEditor"' docs/workflow-builder.html
grep -Fq 'id="addChecklistItem"' docs/workflow-builder.html
grep -Fq 'checklistItems:checked("stepChecklist")?checklistItemsDraft():[]' docs/workflow-builder.js
grep -Fq 'checklistConfigurationComplete' docs/workflow-builder.js
grep -Fq '"save_workflow_definition_draft_v2"' docs/workflow-builder.js
grep -Fq 'function renderChecklist(task,article)' docs/workflow-tasks.js
grep -Fq 'set_workflow_checklist_item_v1' docs/workflow-tasks.js
grep -Fq 'workflow_executions_v2' docs/workflow-tasks.js
grep -Fq '.task-checklist{' docs/workflow-tasks.css
grep -Fq '20260919103000_workflow_checklist_step.sql' tests/database-regression-v2.sh
