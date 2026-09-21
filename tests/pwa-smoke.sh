#!/usr/bin/env bash
set -euo pipefail
trap 'echo "pwa-smoke failed at line $LINENO: $BASH_COMMAND" >&2' ERR

test -s docs/index.html
test -s docs/app.css
test -s docs/app.js
test -s docs/manifest.webmanifest
test -s docs/sw.js
test -s docs/bottom-nav.js
test -s docs/bottom-nav.css
node --check docs/bottom-nav.js
node --check docs/app.js
test -s docs/mfa-code-input.js
node --check docs/mfa-code-input.js
node --check docs/portfolio.js
node --check docs/portfolio-onboarding.js
grep -Fq './portfolio.js?v=2026092002' docs/portfolio.html
grep -Fq './portfolio-onboarding.js?v=2026092002' docs/portfolio.html
grep -Fq 'supabase.rpc("reactivate_tenant_occupancy_v1"' docs/portfolio.js
! grep -Fq 'closePrevious = await supabase.from("occupancies_v2").update({ starts_on:null,ends_on:null,status:"archived" })' docs/portfolio.js
grep -Fq 'Acceso suspendido' docs/portfolio-onboarding.js
grep -Fq 'Acceso pendiente de vincular' docs/portfolio-onboarding.js
grep -Fq 'user_id,starts_on,ends_on' docs/portfolio-onboarding.js
test -s docs/operations.html
test -s docs/operations.css
test -s docs/operations.js
test -s docs/photo-verifications.html
test -s docs/photo-verifications.css
test -s docs/photo-verifications.js
node --check docs/photo-verifications.js
grep -q 'photo-verifications.html?v=2026091501' docs/operations.html
grep -q 'review-photo-verification' docs/photo-verifications.js
grep -q 'Fotoverificación aprobada correctamente' docs/photo-verifications.js
grep -q 'photo-verifications.js?v=2026091801' docs/photo-verifications.html
grep -q 'photo-verifications.css?v=2026091902' docs/photo-verifications.html
grep -q 'id="reviewToast"' docs/photo-verifications.html
grep -q 'id="propertyFilter"' docs/photo-verifications.html
grep -q 'reviewed_by' docs/photo-verifications.js
grep -q 'rejection_reason' docs/photo-verifications.js
grep -q 'from("profiles")' docs/photo-verifications.js
grep -q 'propertyFilter.addEventListener' docs/photo-verifications.js
grep -q 'photo-history' docs/portfolio.js
grep -q 'property_id' docs/portfolio.js
grep -q 'URLSearchParams(window.location.search)' docs/photo-verifications.js
grep -q 'showToast("✓ " + successMessage)' docs/photo-verifications.js
grep -q 'review-toast.is-visible' docs/photo-verifications.css
grep -q 'createSignedUrl' docs/photo-verifications.js
test -s supabase/functions/review-photo-verification/index.ts
grep -q 'apply_photo_verification_review_v2' supabase/functions/review-photo-verification/index.ts
grep -q 'apply_workflow_photo_review_v1' supabase/functions/review-photo-verification/index.ts
grep -q 'apply_workflow_cleaning_photo_review_v1' supabase/functions/review-photo-verification/index.ts
grep -q 'getAuthenticatorAssuranceLevel(token)' supabase/functions/review-photo-verification/index.ts
grep -q 'aal2_required' supabase/functions/review-photo-verification/index.ts
grep -q 'workflow_execution_id' supabase/functions/review-photo-verification/index.ts
grep -q '.from("user_roles")' supabase/functions/review-photo-verification/index.ts
grep -q 'isAdminForRun' supabase/functions/review-photo-verification/index.ts
! grep -q 'user.app_metadata?.role' supabase/functions/review-photo-verification/index.ts
grep -q 'workflow_execution_id' docs/photo-verifications.js
grep -q 'Workflow completado' docs/photo-verifications.js
grep -q 'Volver a Tareas' docs/photo-verifications.js
test -s supabase/migrations/20260914225214_photo_verification_manual_review.sql
grep -q 'grant execute on function public.apply_photo_verification_review_v2' supabase/migrations/20260914225214_photo_verification_manual_review.sql

grep -q 'manifest.webmanifest' docs/index.html
grep -q 'app.css' docs/index.html
grep -q 'app.js' docs/index.html
grep -q 'serviceWorker' docs/app.js
grep -q 'GestionPisos' docs/manifest.webmanifest
grep -Fq "'./legal.html'" docs/sw.js
grep -Fq "'./privacy.html'" docs/sw.js
grep -q 'gestionpisos-shell-v50' docs/sw.js
grep -Fq "'./workflow-history.html'" docs/sw.js
grep -Fq "'./workflow-history.css'" docs/sw.js
grep -Fq "'./workflow-history.js'" docs/sw.js
grep -Fq "'./cleaning.html'" docs/sw.js
grep -Fq "'./cleaning.js'" docs/sw.js
grep -Fq "'./bottom-nav.js'" docs/sw.js
grep -Fq "'./bottom-nav.css'" docs/sw.js
grep -Fq 'mountBottomNavigation' docs/auth-guard.js
grep -Fq './bottom-nav.js?v=2026091901' docs/auth-guard.js
grep -Fq 'Inicio' docs/bottom-nav.js
grep -Fq 'Cartera' docs/bottom-nav.js
grep -Fq 'Flujos' docs/bottom-nav.js
grep -Fq 'Tareas' docs/bottom-nav.js
grep -Fq 'Más' docs/bottom-nav.js
grep -Fq '"photo-camera.html"' docs/bottom-nav.js
grep -Fq '"photo-pattern-editor.html"' docs/bottom-nav.js
grep -Fq 'env(safe-area-inset-bottom)' docs/bottom-nav.css
grep -Fq 'position:fixed' docs/bottom-nav.css
grep -Fq 'grid-template-columns:repeat(5,minmax(0,1fr))' docs/bottom-nav.css
grep -Fq 'font-size:12px' docs/bottom-nav.css
grep -Fq '.app-bottom-nav-item.is-active' docs/bottom-nav.css
grep -Fq 'color:var(--ui-info)' docs/bottom-nav.css
grep -Fq 'background:var(--ui-info-soft)' docs/bottom-nav.css
grep -Fq 'const isHomePage = currentPage === "index.html"' docs/auth-guard.js
grep -Fq 'setupHomeAccountMenu(session)' docs/auth-guard.js
grep -Fq 'mfaAction.hidden = !requiresPrivilegedMfa(session)' docs/auth-guard.js
grep -Fq 'id="homeAccountAction"' docs/index.html
grep -Fq 'id="homeThemeAction"' docs/index.html
grep -Fq 'data-theme-toggle' docs/index.html
grep -Fq 'id="homeAccountMenu" class="account-menu"' docs/index.html
grep -Fq 'id="mfaSetupAction"' docs/index.html
grep -Fq 'id="logoutBtn"' docs/index.html
for non_home_screen in docs/portfolio.html docs/operations.html docs/workflows.html docs/workflow-builder.html docs/workflow-definitions.html docs/workflow-applications.html docs/workflow-tasks.html docs/workflow-history.html docs/cleaning.html docs/incidents.html docs/permissions.html docs/configuration-resources.html docs/photo-verifications.html docs/photo-patterns.html; do
  ! grep -Fq 'data-theme-toggle' "$non_home_screen"
done
! grep -Fq 'id="themeToggle"' docs/portfolio.html
! grep -Fq 'mfa-setup.html?next=configuration-resources.html' docs/configuration-resources.html
grep -Fq '.desktop-home-link{display:none!important}' docs/app.css
grep -Fq '.context-back{' docs/app.css
grep -Fq -- '--ui-action:#0969da' docs/app.css
grep -Fq '.primary{border:1px solid var(--ui-action)' docs/app.css
grep -Fq 'visualViewport' docs/bottom-nav.js
grep -Fq 'Gestion de Permisos' docs/bottom-nav.js || grep -Fq 'Gestión de Permisos' docs/bottom-nav.js
grep -Fq 'Configuración y Recursos' docs/bottom-nav.js
grep -q 'operations.html' docs/index.html
grep -q 'Notificaciones' docs/operations.html
grep -q 'Pagos' docs/operations.html
grep -q 'Estadísticas' docs/operations.html
grep -q 'operations.css' docs/operations.html
grep -q 'operations.js' docs/operations.html
grep -Fq 'hero hero--brand' docs/index.html
grep -Fq 'data-premium-icon="portfolio"' docs/index.html
grep -Fq 'data-premium-icon="workflows"' docs/index.html
grep -Fq 'data-premium-icon="builder"' docs/workflows.html
grep -Fq 'data-premium-icon="permissions"' docs/configuration-resources.html
grep -Fq 'data-premium-icon="users"' docs/permissions.html
grep -Fq 'AllaisoPremiumIcons' docs/app.js
grep -Fq -- '--ui-accent:#a9854f' docs/app.css
grep -Fq '.premium-nav-card{' docs/app.css
grep -Fq '.premium-icon{' docs/app.css
grep -Fq 'window.AllaisoPremiumIcons?.render(records)' docs/portfolio.js

bash tests/portfolio-smoke.sh

test -s docs/photo-patterns.html
test -s docs/photo-patterns.css
test -s docs/photo-patterns.js
node --check docs/photo-patterns.js
test -s docs/photo-pattern-persistence.js
if grep -q 'photo-patterns.html' docs/portfolio.html; then
  echo 'Cartera must not expose photo pattern configuration in its global header.'
  exit 1
fi
grep -q 'photo-patterns.js?v=2026091502' docs/photo-patterns.html
grep -q 'photo-patterns.css?v=2026091902' docs/photo-patterns.html
grep -q 'photo_patterns_v2' docs/photo-patterns.js
grep -q 'mode", "pattern"' docs/photo-patterns.js
grep -q 'zone_label' docs/photo-patterns.js
grep -q 'target_key: zoneLabel' docs/photo-pattern-persistence.js
test -s docs/photo-reference-guide.js
node --check docs/photo-reference-guide.js
node --check docs/photo-persistence.js
node --check docs/photo-alignment.js
test -s docs/photo-pattern-editor.html
test -s docs/photo-pattern-editor.css
test -s docs/photo-pattern-editor.js
node --check docs/photo-pattern-editor.js
grep -q 'photo-pattern-editor.html' docs/photo-patterns.js
grep -q 'url.searchParams.set("v", "2026091406")' docs/photo-patterns.js
grep -q 'photo-pattern-editor.html?v=2026091406' docs/photo-pattern-persistence.js
grep -q 'photo-pattern-editor.css?v=2026091901' docs/photo-pattern-editor.html
grep -q 'Editar silueta' docs/photo-patterns.js
grep -q 'Dibujar silueta' docs/photo-patterns.js
grep -q 'contour_data' docs/photo-pattern-editor.js
grep -q 'raw_points' docs/photo-pattern-editor.js
grep -q '\["soft", "Suave"\]' docs/photo-pattern-editor.js
grep -q '\["medium", "Medio"\]' docs/photo-pattern-editor.js
grep -q 'stroke.closed ? "Abrir" : "Cerrar"' docs/photo-pattern-editor.js
grep -q 'property_staff_access_v3' docs/photo-pattern-editor.js
grep -q 'can_write' docs/photo-pattern-editor.js
grep -q 'save-photo-pattern-contours' docs/photo-pattern-editor.js
grep -q 'id="moveTool"' docs/photo-pattern-editor.html
grep -q 'id="drawTool"' docs/photo-pattern-editor.html
grep -q 'id="eraseTool"' docs/photo-pattern-editor.html
grep -q 'shapeHandles' docs/photo-pattern-editor.js
grep -q 'dirty = true' docs/photo-pattern-editor.js
grep -q 'labelInput.addEventListener("input"' docs/photo-pattern-editor.js
grep -q 'Etiqueta seleccionada' docs/photo-pattern-editor.js
grep -q 'syncLabelEditor' docs/photo-pattern-editor.js
grep -q 'resizePrimitive' docs/photo-pattern-editor.js
grep -q 'beginSelection' docs/photo-pattern-editor.js
grep -q 'kind === "ellipse"' docs/photo-pattern-editor.js
grep -q 'kind === "rect"' docs/photo-pattern-editor.js
grep -q 'id="ellipseTool"' docs/photo-pattern-editor.html
grep -q 'id="rectTool"' docs/photo-pattern-editor.html
grep -q 'id="lineTool"' docs/photo-pattern-editor.html
grep -q 'id="selectTool"' docs/photo-pattern-editor.html
grep -q 'editorViewport' docs/photo-pattern-editor.html
grep -q 'setTool("move")' docs/photo-pattern-editor.js
grep -q 'beginCreate(event, "line")' docs/photo-pattern-editor.js
grep -q 'beginCreate(event, "rect")' docs/photo-pattern-editor.js
grep -q 'beginCreate(event, "ellipse")' docs/photo-pattern-editor.js
grep -q 'else if (tool === "select") beginSelection(event)' docs/photo-pattern-editor.js
grep -q 'pointToSegmentDistance' docs/photo-pattern-editor.js
grep -q 'zoomLevels' docs/photo-pattern-editor.js
test -s supabase/functions/save-photo-pattern-contours/index.ts
grep -q 'insufficient_write_permission' supabase/functions/save-photo-pattern-contours/index.ts
grep -q 'pattern_version_conflict' docs/photo-pattern-editor.js
grep -q 'contour_data' supabase/functions/save-photo-pattern-contours/index.ts
grep -q 'invalid_contour_data' docs/photo-pattern-editor.js
grep -q 'edge_function_failed' docs/photo-pattern-editor.js
grep -q 'admin.auth.getUser(token)' supabase/functions/save-photo-pattern-contours/index.ts
if grep -q 'photo-gemini-guide.html' docs/photo-patterns.js; then
  echo 'Active photo pattern flow must not depend on Gemini.'
  exit 1
fi
grep -q 'pattern_id' docs/photo-patterns.js
grep -q 'if (count > 0)' docs/photo-patterns.js
grep -q 'url.searchParams.set("pattern_id", pattern.id)' docs/photo-patterns.js
grep -q 'url.searchParams.set("mode", "verify")' docs/photo-patterns.js
grep -q 'Probar verificación' docs/photo-patterns.js
grep -q 'contour_data' docs/photo-reference-guide.js
grep -q 'makeManualMask' docs/photo-reference-guide.js
grep -q 'manual_silhouette_missing' docs/photo-reference-guide.js
grep -q 'dataset.referenceEngine = "manual"' docs/photo-reference-guide.js
grep -q '__allaisoReferenceMaskCanvas' docs/photo-alignment.js
grep -q "__allaisoSetGuideState?.('pending')" docs/photo-alignment.js
grep -q 'if (!activeScores.length)' docs/photo-alignment.js
grep -q 'yellowRequired' docs/photo-alignment.js
grep -q 'greenRequired' docs/photo-alignment.js
grep -q 'activeScores' docs/photo-alignment.js
grep -q 'activeZones' docs/photo-alignment.js
grep -q "__allaisoSetGuideState?.('warn')" docs/photo-alignment.js
grep -q "__allaisoSetGuideState?.('ok')" docs/photo-alignment.js
grep -q 'paintVisibleGuide' docs/photo-reference-guide.js
grep -q 'GUIDE_COLORS' docs/photo-reference-guide.js
grep -q '__allaisoSetGuideState' docs/photo-reference-guide.js
grep -q 'photo-reference-guide.js' docs/photo-camera.html
grep -q 'cameraMode !== "pattern"' docs/photo-camera.js
if grep -q 'roomSelect' docs/photo-patterns.js; then
  echo 'Photo patterns must not depend on rooms.'
  exit 1
fi
grep -q 'photo-pattern-persistence.js' docs/photo-camera.html
grep -q 'reference_storage_path' docs/photo-pattern-persistence.js
grep -q 'active: false' docs/photo-pattern-persistence.js
grep -q 'active: true' docs/photo-pattern-persistence.js

test -s docs/photo-camera.html
test -s docs/photo-camera.css
test -s docs/photo-camera.js
grep -q 'photo-camera.css?v=2026091802' docs/photo-camera.html
grep -q 'photo-reference-guide.js?v=2026091801' docs/photo-camera.html
grep -q 'photo-alignment.js?v=2026091503' docs/photo-camera.js
grep -Fq 'photo-camera.js?v=2026091912' docs/photo-camera.html
grep -q 'id="closeCamera"' docs/photo-camera.html
grep -q 'id="flashCamera"' docs/photo-camera.html
grep -q 'id="captureCamera"' docs/photo-camera.html
grep -Fq '.capture-preview[hidden]{display:none!important}' docs/photo-camera.css
grep -q '<svg' docs/photo-camera.html

test -s docs/login.html
test -s docs/login.js
test -s docs/reset-password.html
test -s docs/reset-password.js
test -s docs/auth.css
test -s docs/auth-guard.js
test -s docs/supabase-client.js
grep -q 'signInWithPassword' docs/login.js
grep -q 'resetPasswordForEmail' docs/login.js
grep -q 'updateUser' docs/reset-password.js
grep -q 'getSession' docs/supabase-client.js
grep -q 'sb_publishable_' docs/supabase-client.js
grep -q 'auth-guard.js' docs/index.html
grep -q 'auth-guard.js' docs/photo-camera.html
grep -q 'login.html' docs/auth-guard.js
grep -q 'login.html' docs/sw.js

test -s docs/photo-persistence.js
grep -q 'photo-persistence.js' docs/photo-camera.html
grep -q 'photo_verification_runs_v2' docs/photo-persistence.js
grep -q 'photo_verification_items_v2' docs/photo-persistence.js
grep -q 'submit-photo-verification' docs/photo-persistence.js
grep -q 'alignment_meta' docs/photo-persistence.js
grep -q 'start_workflow_photo_verification_v1' docs/photo-persistence.js
grep -q 'submit_workflow_photo_verification_v1' docs/photo-persistence.js
grep -q 'workflow_resource_id' docs/photo-persistence.js
grep -q 'workflow_execution_photo_resources_v2' docs/photo-reference-guide.js
grep -q 'pattern_snapshot' docs/photo-reference-guide.js
grep -Fq 'photo-persistence.js?v=2026091912' docs/photo-camera.html

test -s docs/permissions.html
test -s docs/permissions.js
node --check docs/permissions.js
grep -Fq 'id="createUserForm"' docs/permissions.html
grep -Fq 'create-organization-user' docs/permissions.js
grep -Fq 'display_name:name,email,role' docs/permissions.js
grep -Fq 'MODULE_NOT_STARTED' docs/permissions.html
grep -Fq 'MODULE_IMPORT_FAILED' docs/permissions.html
grep -Fq 'import("./permissions.js?v=202609170")' docs/permissions.html
grep -Fq 'split("\n").join(" ")' docs/permissions.html
grep -Fq 'window.__permissionsBooted=true' docs/permissions.js
grep -Fq 'supabase.rpc("get_effective_organization_id")' docs/permissions.js
grep -Fq 'p_organization_id:organizationId' docs/permissions.js
! grep -Fq '\\n    if(profileError)' docs/permissions.js
grep -Fq 'withTimeout(getCurrentSession(),8000,"session_timeout")' docs/permissions.js
grep -Fq '"permissions_timeout"' docs/permissions.js
grep -Fq '<strong>Carga detenida.</strong>' docs/permissions.js
grep -Fq 'Diagnóstico: ' docs/permissions.js
grep -Fq 'replace(/[^A-Za-z0-9_.-]/g,"")' docs/permissions.js
node --check docs/permissions.js
! grep -Fq 'replace(/[\r' docs/permissions.js

echo 'PWA smoke checks passed'

# Legacy automatic photo guide code must stay removed.
test ! -e docs/photo-gemini-guide.html
test ! -e docs/photo-gemini-guide.js
test ! -e docs/photo-gemini-guide.css
test ! -e docs/bench-guide-approved.svg
test ! -e supabase/functions/generate-photo-pattern-guide/index.ts
if grep -R -E -i 'mobilesam|onnxruntime|CONTORNO_GEMINI_API_KEY|generate-photo-pattern-guide|photo-gemini-guide|buildSobel|Gemini exterior' docs supabase/functions --exclude='PHOTO_VERIFICATION_CONTRACT.md'; then
  echo 'Legacy automatic photo guide code must stay removed.'
  exit 1
fi

grep -q 'id="evolutionBtn"' docs/photo-verifications.html
grep -q 'showEvolution' docs/photo-verifications.js
grep -q 'evolution-grid' docs/photo-verifications.css

grep -q 'id="evolutionPattern"' docs/photo-verifications.js
grep -q 'id="evolutionFrom"' docs/photo-verifications.js
grep -q 'id="evolutionTo"' docs/photo-verifications.js
grep -q 'evolution-picker' docs/photo-verifications.css

grep -q 'Evolución de fotoverificaciones' docs/photo-verifications.js
grep -q 'disabledIndex' docs/photo-verifications.js
grep -q 'evolutionOption(entry,index,rightIndex)' docs/photo-verifications.js
grep -q 'evolutionOption(entry,index,leftIndex)' docs/photo-verifications.js

# Permission Management is internal agency staff only.
grep -Fq '<option value="employee">Empleado</option>' docs/permissions.html
grep -Fq '<option value="admin">Administrador</option>' docs/permissions.html
! grep -Fq '<option value="owner">Propietario</option>' docs/permissions.html
! grep -Fq '<option value="tenant">Inquilino</option>' docs/permissions.html

grep -Fq 'Enviando al servidor…' docs/permissions.js
grep -Fq 'Cambio no guardado.' docs/permissions.js
grep -Fq 'grant_property_staff_access_v3' docs/permissions.js

grep -Fq 'confirm.textContent="Guardando…"' docs/permissions.js
grep -Fq 'await onConfirm();closeModal();' docs/permissions.js

grep -Fq 'Confirmación recibida.' docs/permissions.js
grep -Fq 'Enviando acceso al servidor…' docs/permissions.js
grep -Fq 'Acceso guardado.' docs/permissions.js

grep -Fq 'grant_returned_empty' docs/permissions.js
grep -Fq 'reloadAfter=true' docs/permissions.js

grep -Fq 'class="ghost remove-staff"' docs/permissions.js
grep -Fq 'deactivate_internal_staff_user' docs/permissions.js
grep -Fq 'disable-internal-staff-auth' docs/permissions.js
test -s supabase/functions/disable-internal-staff-auth/index.ts
grep -Fq 'ban_duration: "876000h"' supabase/functions/disable-internal-staff-auth/index.ts

grep -Fq '[hidden]{display:none!important}' docs/app.css
grep -Fq 'input[type="checkbox"],input[type="radio"]' docs/app.css
grep -Fq '<span>Puede recuperar ROOT</span>' docs/permissions.html
grep -Fq 'class="builder-editor-state"' docs/workflow-builder.html

# WF-03 authoring: Limpieza uses only the specialized domain adapter path.
node --check docs/workflow-builder.js
grep -Fq './workflow-builder.js?v=2026092101' docs/workflow-builder.html
grep -Fq 'id="cleaningStepNote"' docs/workflow-builder.html
grep -Fq 'id="cleaningCloseNote"' docs/workflow-builder.html
grep -Fq 'function updateCleaningContract()' docs/workflow-builder.js
grep -Fq 'const genericSteps=[field("stepPhoto"),field("stepChecklist"),field("stepDocument")]' docs/workflow-builder.js
grep -Fq 'if(specialized)accept.checked=true' docs/workflow-builder.js
grep -Fq 'if(specialized)close.value="domain_adapter"' docs/workflow-builder.js
grep -Fq 'organizationOption.disabled=specialized' docs/workflow-builder.js
test -s supabase/migrations/20260920143000_wf03_cleaning_authoring_contract.sql
grep -Fq "workflow_authoring_complete_core_v1" supabase/migrations/20260920143000_wf03_cleaning_authoring_contract.sql
grep -Fq "coalesce(p_spec->>'flowType','')='cleaning'" supabase/migrations/20260920143000_wf03_cleaning_authoring_contract.sql
grep -Fq "coalesce(p_spec#>>'{steps,accept}','false')<>'true'" supabase/migrations/20260920143000_wf03_cleaning_authoring_contract.sql
grep -Fq "coalesce(p_spec#>>'{steps,photo}','false')='true'" supabase/migrations/20260920143000_wf03_cleaning_authoring_contract.sql
test -s supabase/migrations/20260920143100_wf03_cleaning_adapter_opt_in.sql
grep -Fq "workflow_ensure_cleaning_domain_task_core_v1" supabase/migrations/20260920143100_wf03_cleaning_adapter_opt_in.sql
grep -Fq "coalesce(v_execution.spec_snapshot->>'closeType','')<>'domain_adapter'" supabase/migrations/20260920143100_wf03_cleaning_adapter_opt_in.sql

grep -Fq './app.css?v=2026091910' docs/index.html
grep -Fq 'linear-gradient(145deg,#2d2a26 0%,#26231f 54%,#1f1d1a 100%)' docs/app.css

grep -Fq '.account-menu{' docs/app.css
grep -Fq 'data-theme-menu-label' docs/app.js

! grep -Fq 'menu.addEventListener("click", event => event.stopPropagation())' docs/auth-guard.js
grep -Fq 'button.addEventListener("click", event =>' docs/app.js
grep -Fq 'button.dataset.themeBound = "1"' docs/app.js
grep -Fq 'window.AllaisoTheme = { apply, toggle, bind }' docs/app.js
! grep -Fq 'document.addEventListener("click", event =>' docs/app.js
grep -Fq 'id="homeThemeAction"' docs/index.html

grep -Fq "const backLink = \$('cameraBackLink');" docs/photo-camera.js
grep -Fq "return './workflow-tasks.html';" docs/photo-camera.js
grep -Fq "'./cleaning.html?task_id='" docs/photo-camera.js
grep -Fq "return './photo-patterns.html';" docs/photo-camera.js

# WF-03 cleaning UI must enter through the transversal tenant task.
test -s docs/cleaning.html
test -s docs/cleaning.js
node --check docs/cleaning.js
node --check docs/workflow-tasks.js
grep -Fq './workflow-tasks.js?v=2026092025' docs/workflow-tasks.html
grep -Fq 'function cleaningExecutionForTask(task)' docs/workflow-tasks.js
grep -Fq 'url.searchParams.set("workflow_task_id",task.id)' docs/workflow-tasks.js
grep -Fq 'renderCleaningAdapter(task,article)' docs/workflow-tasks.js
! grep -Fq 'id="taskForm"' docs/cleaning.html
! grep -Fq 'Introduce el identificador' docs/cleaning.html
grep -Fq 'params.get("workflow_task_id")' docs/cleaning.js
grep -Fq 'workflow_task_id:workflowTaskId' docs/cleaning.js
grep -Fq 'supabase.functions.invoke("my-cleaning-checklist"' docs/cleaning.js
test -s supabase/functions/my-cleaning-checklist/index.ts
grep -Fq '.from("tenant_tasks_v2")' supabase/functions/my-cleaning-checklist/index.ts
grep -Fq '.from("workflow_executions_v2")' supabase/functions/my-cleaning-checklist/index.ts
grep -Fq '.eq("workflow_execution_id",execution.id)' supabase/functions/my-cleaning-checklist/index.ts
grep -Fq 'workflow_task_not_assigned_to_user' supabase/functions/my-cleaning-checklist/index.ts
grep -Fq 'workflow_task_reference_required' supabase/functions/my-cleaning-checklist/index.ts
grep -Fq 'workflow_accept_required' supabase/functions/my-cleaning-checklist/index.ts
grep -Fq 'capture_url:readOnly?null:captureUrl' supabase/functions/my-cleaning-checklist/index.ts
grep -Fq 'return_to=' supabase/functions/my-cleaning-checklist/index.ts
grep -Fq "const back = document.getElementById(\"cameraBackLink\");" docs/photo-persistence.js
! grep -Fq 'document.querySelector(".topbar a.ghost")' docs/photo-persistence.js


# Campanita global + Web Push Android.
test -s docs/notification-center.js
test -s docs/notification-center.css
node --check docs/notification-center.js
grep -Fq './notification-center.css?v=2026092001' docs/index.html
grep -Fq './notification-center.js?v=2026092002' docs/auth-guard.js
grep -Fq 'mountNotificationCenter({ supabase, session })' docs/auth-guard.js
grep -Fq 'id="notificationBell"' docs/notification-center.js
grep -Fq 'actions.querySelector(":scope > #homeAccount")' docs/notification-center.js
grep -Fq 'actions.insertBefore(root,homeAccount)' docs/notification-center.js
grep -Fq '.from("notifications_v2")' docs/notification-center.js
grep -Fq 'supabase.rpc("mark_notification_read"' docs/notification-center.js
grep -Fq 'Marcar todo como leído' docs/notification-center.js
grep -Fq 'workflow_task_created:"./workflow-tasks.html"' docs/notification-center.js
grep -Fq 'workflow_completed:"./workflow-history.html"' docs/notification-center.js
grep -Fq 'workflow_rejected:"./workflow-history.html"' docs/notification-center.js
! grep -Fq 'url.searchParams.set("execution"' docs/notification-center.js
grep -Fq "'./notification-center.js'" docs/sw.js
grep -Fq "'./notification-center.css'" docs/sw.js
grep -Fq '.notification-bell-count{' docs/notification-center.css
grep -Fq '.notification-sheet{' docs/notification-center.css
grep -Fq '.notification-actions-host{' docs/notification-center.css
grep -Fq '.notification-item-visual{' docs/notification-center.css
grep -Fq 'Activar Android' docs/notification-center.js
grep -Fq 'register_web_push_subscription_v1' docs/notification-center.js
grep -Fq 'unregister_web_push_subscription_v1' docs/notification-center.js
grep -Fq 'supabase.functions.invoke("web-push"' docs/notification-center.js
grep -Fq "self.addEventListener('push'" docs/sw.js
grep -Fq "self.addEventListener('notificationclick'" docs/sw.js
grep -Fq "showNotification" docs/sw.js
grep -Fq "push_notification" docs/sw.js
grep -Fq '.notification-push-action{' docs/notification-center.css
! grep -Fq '\\n.notification-' docs/notification-center.css

# WF-05: superficie PWA de incidencias y su conexión al workflow común.
bash tests/incidents-smoke.sh
