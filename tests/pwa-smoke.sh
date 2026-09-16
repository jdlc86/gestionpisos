#!/usr/bin/env bash
set -euo pipefail

test -s docs/index.html
test -s docs/app.css
test -s docs/app.js
test -s docs/manifest.webmanifest
test -s docs/sw.js
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
grep -q 'photo-verifications.js?v=2026091507' docs/photo-verifications.html
grep -q 'photo-verifications.css?v=2026091505' docs/photo-verifications.html
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
test -s supabase/migrations/20260915005000_photo_verification_manual_review.sql
grep -q 'grant execute on function public.apply_photo_verification_review_v2' supabase/migrations/20260915005000_photo_verification_manual_review.sql

grep -q 'manifest.webmanifest' docs/index.html
grep -q 'app.css' docs/index.html
grep -q 'app.js' docs/index.html
grep -q 'serviceWorker' docs/app.js
grep -q 'GestionPisos' docs/manifest.webmanifest
grep -q 'gestionpisos-shell-v2' docs/sw.js
grep -q 'operations.html' docs/index.html
grep -q 'Notificaciones' docs/operations.html
grep -q 'Pagos' docs/operations.html
grep -q 'Estadísticas' docs/operations.html
grep -q 'operations.css' docs/operations.html
grep -q 'operations.js' docs/operations.html

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
grep -q 'photo-patterns.css?v=2026091502' docs/photo-patterns.html
grep -q 'photo_patterns_v2' docs/photo-patterns.js
grep -q 'mode", "pattern"' docs/photo-patterns.js
grep -q 'zone_label' docs/photo-patterns.js
grep -q 'target_key: zoneLabel' docs/photo-pattern-persistence.js
test -s docs/photo-reference-guide.js
node --check docs/photo-reference-guide.js
node --check docs/photo-alignment.js
test -s docs/photo-pattern-editor.html
test -s docs/photo-pattern-editor.css
test -s docs/photo-pattern-editor.js
node --check docs/photo-pattern-editor.js
grep -q 'photo-pattern-editor.html' docs/photo-patterns.js
grep -q 'url.searchParams.set("v", "2026091406")' docs/photo-patterns.js
grep -q 'photo-pattern-editor.html?v=2026091406' docs/photo-pattern-persistence.js
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
grep -q 'pattern_version_conflict' supabase/functions/save-photo-pattern-contours/index.ts
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
grep -q 'photo-camera.css?v=2026091501' docs/photo-camera.html
grep -q 'photo-reference-guide.js?v=2026091502' docs/photo-camera.html
grep -q 'photo-alignment.js?v=2026091503' docs/photo-camera.js
grep -q 'photo-camera.js' docs/photo-camera.html
grep -q 'id="closeCamera"' docs/photo-camera.html
grep -q 'id="flashCamera"' docs/photo-camera.html
grep -q 'id="captureCamera"' docs/photo-camera.html
grep -q '<svg' docs/photo-camera.html

test -s docs/login.html
test -s docs/login.js
test -s docs/reset-password.html
test -s docs/reset-password.js
test -s docs/auth.css
test -s docs/auth-guard.js
test -s docs/supabase-client.js
grep -q 'signInWithPassword' docs/login.js
grep -q 'resetPasswordForEmail' docs/reset-password.js
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
