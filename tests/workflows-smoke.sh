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
test -s docs/WORKFLOW_DOCUMENT_EVIDENCE_CONTRACT.md
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
grep -Fq 'href="./workflow-history.html"' docs/workflows.html
test -s docs/WORKFLOW_HISTORY_CONTRACT.md
test -s docs/workflow-history.html
test -s docs/workflow-history.css
test -s docs/workflow-history.js
node --check docs/workflow-history.js
grep -Fq './auth-guard.js' docs/workflow-history.html
grep -Fq 'id="historySearchToggle"' docs/workflow-history.html
grep -Fq 'data-history-filter="open"' docs/workflow-history.html
grep -Fq 'data-history-filter="completed"' docs/workflow-history.html
grep -Fq 'data-history-filter="rejected"' docs/workflow-history.html
grep -Fq 'workflow_execution_events_v2' docs/workflow-history.js
grep -Fq 'tenant_task_history_v2' docs/workflow-history.js
grep -Fq 'workflow_execution_photo_resources_v2' docs/workflow-history.js
grep -Fq 'workflow_execution_documents_v2' docs/workflow-history.js
grep -Fq 'photo_verification_runs_v2' docs/workflow-history.js
grep -Fq 'createSignedUrl(documentRow.storage_path,300)' docs/workflow-history.js
grep -Fq 'function renderTimeline(execution,container)' docs/workflow-history.js
grep -Fq 'function renderEvidence(execution,container)' docs/workflow-history.js
grep -Fq '.history-timeline{' docs/workflow-history.css
grep -Fq '.history-search-mode{' docs/workflow-history.css
grep -Fq 'WORKFLOW_HISTORY_CONTRACT.md' docs/WORKFLOW_DOCUMENTATION_INDEX.md
grep -Fq 'workflow-history.html' docs/sw.js
grep -Fq '"workflow-history.html"' docs/bottom-nav.js

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
! grep -Fq '>En preparación</span>' docs/workflows.html
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
! grep -Fq 'sessionStorage.setItem(DRAFT_KEY' docs/workflow-builder.js
grep -Fq 'save_workflow_definition_draft_v2' docs/workflow-builder.js
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
grep -Fq 'Se restauró la edición guardada.' docs/workflow-builder.js
grep -Fq '.builder-view[hidden]{display:none!important}' docs/workflow-builder.css
grep -Fq '.builder-drafts-list{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr))' docs/workflow-builder.css
grep -Fq '.builder-exit-dialog' docs/workflow-builder.css
grep -Fq 'class="builder-back-link"' docs/workflow-builder.html
grep -Fq 'class="builder-back-icon"' docs/workflow-builder.html
! grep -Fq '← Volver' docs/workflow-builder.html
grep -Fq 'aria-label="Salir del Creador"' docs/workflow-builder.html
grep -Fq 'id="builderClear" type="button" class="builder-action builder-action--danger" hidden>Descartar todo</button>' docs/workflow-builder.html
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
grep -Fq 'id="builderSave" type="button" class="builder-action" hidden>Guardar</button>' docs/workflow-builder.html
grep -Fq '<strong>Todavía no se ha guardado nada.</strong>' docs/workflow-builder.html
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
grep -Fq 'function saveLocalDraft(){' docs/workflow-builder.js
grep -Fq 'Requerir decisión del asignado: Aceptar / Rechazar' docs/workflow-builder.html
grep -Fq 'Decisión Aceptar / Rechazar' docs/workflow-builder.js
grep -Fq 'id="scheduledAt"' docs/workflow-builder.html
grep -Fq 'id="customRecurrenceRow"' docs/workflow-builder.html
grep -Fq '.builder-panel [hidden]{display:none!important}' docs/workflow-builder.css
grep -Fq './workflow-builder.css?v=2026091914' docs/workflow-builder.html
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
grep -Fq './workflow-builder.js?v=2026091921' docs/workflow-builder.html

grep -Fq 'workflow_definitions_v2' docs/workflow-definitions.js
grep -Fq '.eq("status","published")' docs/workflow-definitions.js
grep -Fq 'workflow_definition_revision_drafts_v2' docs/workflow-definitions.js
grep -Fq 'start_workflow_definition_revision_v1' docs/workflow-definitions.js
! grep -Fq 'Crear nueva versión' docs/workflow-definitions.js
! grep -Fq 'Continuar nueva versión' docs/workflow-definitions.js
grep -Fq 'workflow-applications.html?definition=' docs/workflow-definitions.js
grep -Fq './workflow-definitions.js?v=2026091923' docs/workflow-definitions.html
grep -Fq './workflow-definitions.css?v=2026091912' docs/workflow-definitions.html
grep -Fq 'Tus flujos terminados. Ejecuta, edita y elimina o archiva según exista historial.' docs/workflow-definitions.html
! grep -Fq 'Completar borrador' docs/workflow-definitions.js
! grep -Fq 'Publicar versión' docs/workflow-definitions.js
! grep -Fq 'publish_workflow_definition_v1' docs/workflow-definitions.js
grep -Fq 'create_workflow_application_v2' docs/workflow-applications.js
grep -Fq 'archive_workflow_application_v1' docs/workflow-applications.js
grep -Fq 'properties_v2' docs/workflow-applications.js
grep -Fq 'rooms_v2' docs/workflow-applications.js
grep -Fq 'occupancies_v2' docs/workflow-applications.js
grep -Fq '.application-card [hidden]{display:none!important}' docs/workflow-applications.css
grep -Fq './workflow-applications.css?v=2026091915' docs/workflow-applications.html
grep -Fq './workflow-applications.js?v=2026091922' docs/workflow-applications.html
grep -Fq '¿Dónde quieres utilizarlo?' docs/workflow-applications.html
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
grep -Fq './workflow-tasks.css?v=2026091923' docs/workflow-tasks.html
grep -Fq './workflow-tasks.js?v=2026091923' docs/workflow-tasks.html
grep -Fq 'cambian tarea y ejecución juntas' docs/workflow-tasks.html
grep -Fq 'id="taskSelectionToggle"' docs/workflow-tasks.html
grep -Fq 'id="tasksSelectionHeader"' docs/workflow-tasks.html
grep -Fq 'id="taskSelectVisible"' docs/workflow-tasks.html
grep -Fq 'id="taskDeselectVisible"' docs/workflow-tasks.html
grep -Fq 'id="taskBulkDock"' docs/workflow-tasks.html
grep -Fq 'id="taskBulkAction"' docs/workflow-tasks.html
grep -Fq 'const selectedTaskIds=new Set()' docs/workflow-tasks.js
grep -Fq 'function bindTaskLongPress(article,task)' docs/workflow-tasks.js
grep -Fq 'function selectedActionableTasks()' docs/workflow-tasks.js
grep -Fq '"delete_task_card_v1"' docs/workflow-tasks.js
grep -Fq '.is("removed_at",null)' docs/workflow-tasks.js
grep -Fq 'id="taskHiddenFilterOption"' docs/workflow-tasks.html
grep -Fq '>Ocultas</option>' docs/workflow-tasks.html
grep -Fq 'id="taskBulkActionLabel"' docs/workflow-tasks.html
grep -Fq 'let hiddenTaskIds=new Set()' docs/workflow-tasks.js
grep -Fq 'list_my_hidden_task_cards_v1' docs/workflow-tasks.js
grep -Fq '.range(from,from+pageSize-1)' docs/workflow-tasks.js
grep -Fq 'async function loadHiddenTaskRows()' docs/workflow-tasks.js
grep -Fq 'const missing=[...hiddenTaskIds].filter(id=>!loadedIds.has(id))' docs/workflow-tasks.js
grep -Fq 'if(!currentUser?.id||isManager())return;' docs/workflow-tasks.js
grep -Fq 'if(isManager()){' docs/workflow-tasks.js
grep -Fq 'hide_my_task_card_v1' docs/workflow-tasks.js
grep -Fq 'unhide_my_task_card_v1' docs/workflow-tasks.js
grep -Fq 'function selectionOperation()' docs/workflow-tasks.js
grep -Fq 'filter.value==="hidden"' docs/workflow-tasks.js
grep -Fq 'Puedes recuperarlas desde Mostrar → Ocultas.' docs/workflow-tasks.js
grep -Fq '.task-badge--personal-hidden{' docs/workflow-tasks.css
grep -Fq '.tasks-bulk-action--personal{' docs/workflow-tasks.css
grep -Fq 'aal2_required' docs/workflow-tasks.js
grep -Fq '.is("removed_at",null)' docs/portfolio.js
grep -Fq 'El historial, la ejecución y sus evidencias se conservarán.' docs/workflow-tasks.js
grep -Fq '.task-select-indicator{' docs/workflow-tasks.css
grep -Fq '.tasks-bulk-dock{' docs/workflow-tasks.css
grep -Fq '.task-card.is-selected{' docs/workflow-tasks.css

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

grep -Fq 'Destinos cargados. Puedes preparar uno nuevo o ejecutar el flujo desde un destino disponible.' docs/workflow-applications.js

grep -Fq 'class="builder-editor-state"' docs/workflow-builder.html
grep -Fq '.builder-editor-state::before' docs/workflow-builder.css
grep -Fq 'builderBadge.textContent=state.complete?"Listo":"En edición"' docs/workflow-builder.js
grep -Fq 'builderBadge.title=state.complete?completeLabel:"Configuración en curso"' docs/workflow-builder.js

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

grep -Fq 'id="builderDraftStatus"' docs/workflow-builder.html
grep -Fq 'function discardDraft(item,button)' docs/workflow-builder.js
grep -Fq 'discard_workflow_definition_draft_v1' docs/workflow-builder.js
grep -Fq 'discard_workflow_definition_revision_draft_v1' docs/workflow-builder.js
grep -Fq 'Eliminar borrador' docs/workflow-builder.js
grep -Fq '.builder-action--danger{' docs/workflow-builder.css
grep -Fq '20260919141500_workflow_draft_discard.sql' tests/database-regression-v2.sh

# Guided handoff: authoring architecture remains unchanged, navigation is simplified.
grep -Fq 'Continuar para usarlo' docs/workflow-builder.html
grep -Fq 'class="workflow-journey"' docs/workflow-builder.html
grep -Fq '<strong>Diseño</strong>' docs/workflow-builder.html
grep -Fq '<strong>Destino</strong>' docs/workflow-builder.html
grep -Fq '<strong>Listo</strong>' docs/workflow-builder.html
grep -Fq 'next.searchParams.set("setup","1")' docs/workflow-builder.js
grep -Fq 'workflow-applications.html' docs/workflow-builder.js
grep -Fq 'execute.textContent="Ejecutar"' docs/workflow-definitions.js
grep -Fq 'id="workflowSetupJourney"' docs/workflow-applications.html
grep -Fq 'id="applicationVersionRow"' docs/workflow-applications.html
grep -Fq 'id="applicationsSection"' docs/workflow-applications.html
grep -Fq 'Destinos configurados' docs/workflow-applications.html
grep -Fq 'const guidedSetup=params.get("setup")==="1"' docs/workflow-applications.js
grep -Fq 'let guidedApplicationId=params.get("application")||null' docs/workflow-applications.js
grep -Fq 'function setSetupStage(stage)' docs/workflow-applications.js
grep -Fq 'function renderGuidedReady(app)' docs/workflow-applications.js
grep -Fq 'function buildExecutionControls(app,{guided=false}={})' docs/workflow-applications.js
grep -Fq 'url.searchParams.set("application",guidedApplicationId)' docs/workflow-applications.js
grep -Fq 'Destino preparado. Revisa quién realizará la tarea y pulsa Ejecutar ahora.' docs/workflow-applications.js
grep -Fq 'Tarea creada' docs/workflow-applications.js
grep -Fq '.application-ready-card{' docs/workflow-applications.css
grep -Fq '.workflow-journey{' docs/workflow-builder.css
grep -Fq '.workflow-journey{' docs/workflow-applications.css

grep -Fq 'let guidedExecutionId=params.get("execution")||null' docs/workflow-applications.js
grep -Fq 'url.searchParams.set("execution",result.execution_id)' docs/workflow-applications.js
grep -Fq 'item.id===guidedExecutionId&&item.application_id===guidedApplicationId' docs/workflow-applications.js
grep -Fq 'url.searchParams.delete("execution")' docs/workflow-applications.js
grep -Fq 'Tarea creada. Puedes abrir Tareas o volver a Mis Flujos.' docs/workflow-applications.js


# Nuevo ciclo de vida: las creaciones nuevas no se persisten hasta Listo.
grep -Fq 'const editorRequested=true' docs/workflow-builder.js
grep -Fq 'const editPublishedMode=initialParams.get("edit")==="1"' docs/workflow-builder.js
grep -Fq 'gestionpisos.workflow-builder.handoff.' docs/workflow-builder.js
grep -Fq 'mode:revisionMode?"revision":editPublishedMode?"edit_unexecuted":"create"' docs/workflow-builder.js
grep -Fq 'Nada se guarda hasta completar Listo.' docs/workflow-builder.js
grep -Fq 'id="builderDraftsView" class="builder-view" aria-labelledby="builderDraftsTitle" hidden' docs/workflow-builder.html
grep -Fq 'id="builderEditorView" class="builder-view" aria-labelledby="builderEditorTitle"' docs/workflow-builder.html
grep -Fq 'title="Configuración en curso">En edición</span>' docs/workflow-builder.html
grep -Fq 'id="builderSaveExitInline" type="button" class="builder-action" hidden' docs/workflow-builder.html

# Destino/Listo se mantienen integrados y Listo decide Publicar/Ejecutar/Descartar.
grep -Fq 'const transientSetup=guidedSetup&&Boolean(handoffToken)' docs/workflow-applications.js
grep -Fq 'function consumeTransientHandoff()' docs/workflow-applications.js
grep -Fq 'sessionStorage.removeItem(HANDOFF_KEY_PREFIX+handoffToken)' docs/workflow-applications.js
grep -Fq 'renderTransientReady' docs/workflow-applications.js
grep -Fq 'publish.textContent=automatic?"Programar":"Publicar"' docs/workflow-applications.js
grep -Fq 'execute.textContent="Ejecutar"' docs/workflow-applications.js
grep -Fq 'discard.textContent="Descartar todo"' docs/workflow-applications.js
grep -Fq 'changeTarget.textContent="Cambiar destino"' docs/workflow-applications.js
grep -Fq '"publish_workflow_ready_v1"' docs/workflow-applications.js
grep -Fq '"update_unexecuted_workflow_v1"' docs/workflow-applications.js
grep -Fq '"publish_workflow_revision_ready_v1"' docs/workflow-applications.js
grep -Fq '"publish_workflow_ready_v2"' docs/workflow-applications.js
grep -Fq '"update_unexecuted_workflow_v2"' docs/workflow-applications.js
grep -Fq '"publish_workflow_revision_ready_v2"' docs/workflow-applications.js
grep -Fq 'Flujo publicado sin tareas.' docs/workflow-applications.js

# Mis Flujos oculta la mecanica de versiones y deriva acciones del historial.
grep -Fq 'function hasHistory(row)' docs/workflow-definitions.js
grep -Fq 'execute.textContent="Ejecutar"' docs/workflow-definitions.js
grep -Fq 'edit.textContent=needsSchedule?"Editar programación":"Editar"' docs/workflow-definitions.js
grep -Fq 'remove.textContent="Eliminar"' docs/workflow-definitions.js
grep -Fq 'archive.textContent="Archivar"' docs/workflow-definitions.js
grep -Fq 'delete_unexecuted_workflow_v1' docs/workflow-definitions.js
grep -Fq 'archive_workflow_definition_v1' docs/workflow-definitions.js
grep -Fq 'start_workflow_definition_revision_v1' docs/workflow-definitions.js
! grep -Fq 'Duplicar' docs/workflow-definitions.js


# Jerarquía de acciones del Creador: navegar no compite con finalizar.
grep -Fq 'id="builderNext" type="button" class="builder-action builder-action--primary">Siguiente</button>' docs/workflow-builder.html
grep -Fq 'id="builderPublish" type="button" class="builder-action builder-action--primary" disabled hidden>Continuar para usarlo</button>' docs/workflow-builder.html
grep -Fq 'backButton.hidden=finalStep' docs/workflow-builder.js
grep -Fq 'nextButton.hidden=finalStep' docs/workflow-builder.js
grep -Fq 'publishButton.hidden=!finalStep' docs/workflow-builder.js
grep -Fq 'clearButton.hidden=!finalStep' docs/workflow-builder.js
grep -Fq 'nextButton.textContent="Siguiente"' docs/workflow-builder.js
grep -Fq ':"Descartar todo";' docs/workflow-builder.js
grep -Fq 'justify-content:space-between' docs/workflow-builder.css


# Ejecutar desde Mis Flujos entra en modo asistido y muestra solo requisitos pendientes.
grep -Fq '&setup=1&intent=execute&from=mis-flujos' docs/workflow-definitions.js
grep -Fq 'const executionIntent=guidedSetup&&params.get("intent")==="execute"' docs/workflow-applications.js
grep -Fq 'const executionFromFlows=executionIntent&&params.get("from")==="mis-flujos"' docs/workflow-applications.js
grep -Fq 'function renderExecutionAssist(app)' docs/workflow-applications.js
grep -Fq 'function executionReviewCard' docs/workflow-applications.js
grep -Fq 'Falta información para ejecutar' docs/workflow-applications.js
grep -Fq 'Completa únicamente los apartados abiertos para continuar.' docs/workflow-applications.js
grep -Fq 'cancel.textContent=batchQueue?"Cancelar ejecución masiva":"Cancelar ejecución"' docs/workflow-applications.js
grep -Fq 'firstPending.scrollIntoView' docs/workflow-applications.js
grep -Fq 'execution-field-missing' docs/workflow-applications.js
grep -Fq '.execution-review-card.is-pending' docs/workflow-applications.css
grep -Fq '.execution-field-missing' docs/workflow-applications.css
! grep -Fq 'Gestionar destinos' docs/workflow-applications.js


# Mis Flujos: búsqueda, selección múltiple y última ejecución visible.
grep -Fq 'id="workflowSearch"' docs/workflow-definitions.html
grep -Fq 'id="workflowSelectionToggle"' docs/workflow-definitions.html
grep -Fq 'id="workflowSelectVisible"' docs/workflow-definitions.html
grep -Fq 'id="workflowBulkExecute"' docs/workflow-definitions.html
grep -Fq 'id="workflowBulkDelete"' docs/workflow-definitions.html
grep -Fq 'id="workflowBulkArchive"' docs/workflow-definitions.html
grep -Fq 'function rowMatchesSearch(row)' docs/workflow-definitions.js
grep -Fq 'function executionMeta(row)' docs/workflow-definitions.js
grep -Fq 'value.textContent=String(count)+" · "+(latest?"última "' docs/workflow-definitions.js
grep -Fq 'function bulkDeleteSelected()' docs/workflow-definitions.js
grep -Fq 'function bulkArchiveSelected()' docs/workflow-definitions.js
grep -Fq 'function startBulkExecution()' docs/workflow-definitions.js
grep -Fq 'workflow-batch-execution:' docs/workflow-definitions.js
grep -Fq '.definitions-bulk-dock' docs/workflow-definitions.css
grep -Fq '.definitions-list.is-selecting .definition-actions{display:none}' docs/workflow-definitions.css

# Mis Flujos moderno: búsqueda contextual y selección touch-first.
grep -Fq 'id="workflowSearchToggle"' docs/workflow-definitions.html
grep -Fq 'id="definitionsSearchHeader"' docs/workflow-definitions.html
grep -Fq 'id="workflowSearchClear"' docs/workflow-definitions.html
grep -Fq 'id="definitionsSelectionHeader"' docs/workflow-definitions.html
grep -Fq 'id="workflowSelectionMenuToggle"' docs/workflow-definitions.html
grep -Fq 'id="workflowDeselectVisible"' docs/workflow-definitions.html
grep -Fq 'id="workflowActiveFilter"' docs/workflow-definitions.html
grep -Fq 'id="workflowBulkDock"' docs/workflow-definitions.html
! grep -Fq 'class="definitions-controls"' docs/workflow-definitions.html
! grep -Fq 'class="definitions-bulk-bar"' docs/workflow-definitions.html
! grep -Fq 'workflowSelectVisible" type="checkbox"' docs/workflow-definitions.html
grep -Fq 'function openSearch()' docs/workflow-definitions.js
grep -Fq 'function closeSearch({clear=false}={})' docs/workflow-definitions.js
grep -Fq 'function setSelectionMode(enabled,{selectId=null}={})' docs/workflow-definitions.js
grep -Fq 'function bindLongPress(article,row)' docs/workflow-definitions.js
grep -Fq '},520);' docs/workflow-definitions.js
grep -Fq 'definition-select-indicator' docs/workflow-definitions.js
grep -Fq 'definitions-selection-active' docs/workflow-definitions.js
grep -Fq 'selectionMenuToggle.setAttribute("aria-expanded"' docs/workflow-definitions.js
grep -Fq '.definitions-search-mode{' docs/workflow-definitions.css
grep -Fq '.definitions-selection-mode{' docs/workflow-definitions.css
grep -Fq '.definition-select-indicator{' docs/workflow-definitions.css
grep -Fq '.definitions-bulk-dock{' docs/workflow-definitions.css
grep -Fq 'bottom:calc(76px + env(safe-area-inset-bottom))' docs/workflow-definitions.css
grep -Fq '@keyframes definitions-dock-in' docs/workflow-definitions.css

# Ejecución múltiple: cola asistida y navegación secuencial.
grep -Fq 'const batchToken=params.get("batch")||""' docs/workflow-applications.js
grep -Fq 'function loadBatchQueue()' docs/workflow-applications.js
grep -Fq 'function batchNextUrl()' docs/workflow-applications.js
grep -Fq 'Siguiente flujo · ' docs/workflow-applications.js
grep -Fq 'Cancelar ejecución masiva' docs/workflow-applications.js
grep -Fq '.execution-batch-progress' docs/workflow-applications.css


# Documento operativo dentro de Tareas y sin gestor paralelo.
grep -Fq 'const DOCUMENT_BUCKET="workflow-documents-v2"' docs/workflow-tasks.js
grep -Fq 'function renderDocuments(task,article)' docs/workflow-tasks.js
grep -Fq 'prepare_workflow_document_upload_v1' docs/workflow-tasks.js
grep -Fq 'submit_workflow_document_v1' docs/workflow-tasks.js
grep -Fq '.from(DOCUMENT_BUCKET)' docs/workflow-tasks.js
grep -Fq '.upload(preparation.storage_path,file' docs/workflow-tasks.js
grep -Fq '.createSignedUrl(documentRow.storage_path,300)' docs/workflow-tasks.js
grep -Fq 'Adjuntar documento' docs/workflow-tasks.js
grep -Fq 'Acepta la tarea antes de adjuntar el documento.' docs/workflow-tasks.js
grep -Fq 'workflow_execution_documents_v2' docs/workflow-tasks.js
grep -Fq 'loadDocuments()' docs/workflow-tasks.js
grep -Fq 'renderDocuments(task,article)' docs/workflow-tasks.js
grep -Fq '.task-documents{' docs/workflow-tasks.css
grep -Fq '.task-document-row{' docs/workflow-tasks.css
grep -Fq './workflow-tasks.css?v=2026091923' docs/workflow-tasks.html
grep -Fq './workflow-tasks.js?v=2026091923' docs/workflow-tasks.html


# Contrato Documento: evidencia privada, tarea común y cierre coordinado.
grep -Fq 'workflow_execution_documents_v2' docs/WORKFLOW_DOCUMENT_EVIDENCE_CONTRACT.md
grep -Fq 'workflow-documents-v2' docs/WORKFLOW_DOCUMENT_EVIDENCE_CONTRACT.md
grep -Fq 'prepare_workflow_document_upload_v1' docs/WORKFLOW_DOCUMENT_EVIDENCE_CONTRACT.md
grep -Fq 'submit_workflow_document_v1' docs/WORKFLOW_DOCUMENT_EVIDENCE_CONTRACT.md
grep -Fq 'Foto completada + Checklist completado + Documento pendiente' docs/WORKFLOW_DOCUMENT_EVIDENCE_CONTRACT.md
grep -Fq 'tenant_documents_v2' docs/WORKFLOW_DOCUMENT_EVIDENCE_CONTRACT.md
grep -Fq 'WORKFLOW_DOCUMENT_EVIDENCE_CONTRACT.md' docs/WORKFLOW_DOCUMENTATION_INDEX.md


# Historial: Rechazadas significa solo rejected y la revisión usa el motivo agregado del histórico de tarea.
grep -Fq 'if(activeFilter==="rejected"&&execution.status!=="rejected")return false;' docs/workflow-history.js
! grep -Fq 'REJECTED_STATUSES' docs/workflow-history.js
grep -Fq 'const historyNote=taskHistoryNote(' docs/workflow-history.js
grep -Fq 'rejected?"review_reject":"review_approve"' docs/workflow-history.js
grep -Fq 'if(historyNote)return historyNote;' docs/workflow-history.js
grep -Fq './workflow-history.js?v=2026091911' docs/workflow-history.html


# Fecha concreta: instante exacto + Programar + sin ejecución manual.
grep -Fq 'name="scheduledTimezone"' docs/workflow-builder.html
grep -Fq 'name="scheduledAtUtc"' docs/workflow-builder.html
grep -Fq 'id="scheduledTimezoneHint"' docs/workflow-builder.html
grep -Fq 'function syncScheduledInstant({force=false}={})' docs/workflow-builder.js
grep -Fq 'scheduledTimezone:value("scheduledTimezone")' docs/workflow-builder.js
grep -Fq 'scheduledAtUtc:value("scheduledAtUtc")' docs/workflow-builder.js
grep -Fq 'runAt>Date.now()' docs/workflow-builder.js
grep -Fq 'Zona horaria · ' docs/workflow-builder.js
grep -Fq 'function scheduledDisplay(spec)' docs/workflow-applications.js
grep -Fq 'title.textContent=automatic?"Programación":"Decisión final"' docs/workflow-applications.js
grep -Fq 'publish.textContent=automatic?"Programar":"Publicar"' docs/workflow-applications.js
grep -Fq 'execute.hidden=automatic' docs/workflow-applications.js
grep -Fq 'common.p_schedule_timezone=spec.scheduledTimezone||null' docs/workflow-applications.js
grep -Fq 'common.p_schedule_assigned_user_id=' docs/workflow-applications.js
grep -Fq 'Flujo programado.' docs/workflow-applications.js
grep -Fq 'function isScheduledAutomatic(row)' docs/workflow-definitions.js
grep -Fq 'if(!isScheduledAutomatic(row))' docs/workflow-definitions.js
grep -Fq 'Los flujos seleccionados de Fecha concreta se ejecutarán automáticamente' docs/workflow-definitions.js
grep -Fq 'Ejecución automática' docs/workflow-definitions.js
grep -Fq 'scheduledDateTime(spec)' docs/workflow-definitions.js
grep -Fq 'workflow_schedule_blocked:"./workflow-definitions.html"' docs/notification-center.js


# Fecha concreta: el Creador rechaza horas locales repetidas por cambio DST.
grep -Fq 'function zonedMinuteString(date,timezone)' docs/workflow-builder.js
grep -Fq 'function scheduledMinuteIsAmbiguous(date,local,timezone)' docs/workflow-builder.js
grep -Fq 'Esta hora se repite por el cambio horario. Elige otra hora.' docs/workflow-builder.js
grep -Fq 'workflow_schedule_local_time_ambiguous' docs/workflow-applications.js


# Recurrente: primera ejecución explícita, Programar y sin ejecución manual.
grep -Fq 'id="scheduledAtLabel"' docs/workflow-builder.html
grep -Fq 'scheduledAtLabel.textContent=recurring?"Primera ejecución":"Fecha y hora"' docs/workflow-builder.js
grep -Fq 'const automatic=scheduled||recurring' docs/workflow-builder.js
grep -Fq 'if(data.triggerType==="recurring")' docs/workflow-builder.js
grep -Fq 'function isAutomaticTrigger(spec)' docs/workflow-applications.js
grep -Fq 'function recurrenceDisplay(spec)' docs/workflow-applications.js
grep -Fq '¿Quién realizará las tareas de este flujo recurrente?' docs/workflow-applications.js
grep -Fq 'El responsable operativo se resolverá de nuevo en cada ejecución recurrente.' docs/workflow-applications.js
grep -Fq 'execute.hidden=automatic' docs/workflow-applications.js
grep -Fq 'Programar guarda el flujo sin crear una tarea ahora.' docs/workflow-applications.js
grep -Fq '["scheduled_once","recurring"].includes' docs/workflow-definitions.js
grep -Fq 'schedule.schedule_kind==="recurring"' docs/workflow-definitions.js
grep -Fq 'next_occurrence_index,execution_count,last_scheduled_for' docs/workflow-definitions.js
grep -Fq '"Próxima · "+next' docs/workflow-definitions.js


# Recurrente legacy: un flujo automático publicado antes del scheduler debe pedir programación explícita.
grep -Fq 'function needsScheduleConfiguration(row)' docs/workflow-definitions.js
grep -Fq '"Necesita programación"' docs/workflow-definitions.js
grep -Fq 'edit.textContent=needsSchedule?"Editar programación":"Editar"' docs/workflow-definitions.js
grep -Fq 'edit.textContent=needsSchedule?"Continuar programación":"Editar"' docs/workflow-definitions.js
grep -Fq 'else if(!needsSchedule)' docs/workflow-definitions.js
