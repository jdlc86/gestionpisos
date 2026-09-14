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
test -s docs/photo-pattern-persistence.js
grep -q 'photo-patterns.html' docs/portfolio.html
grep -q 'photo_patterns_v2' docs/photo-patterns.js
grep -q 'mode", "pattern"' docs/photo-patterns.js
grep -q 'zone_label' docs/photo-patterns.js
grep -q 'target_key: zoneLabel' docs/photo-pattern-persistence.js
test -s docs/photo-reference-guide.js
test -s docs/photo-pattern-editor.html
test -s docs/photo-pattern-editor.css
test -s docs/photo-pattern-editor.js
grep -q 'photo-pattern-editor.html' docs/photo-patterns.js
grep -q 'Editar silueta' docs/photo-patterns.js
grep -q 'Dibujar silueta' docs/photo-patterns.js
grep -q 'contour_data' docs/photo-pattern-editor.js
grep -q 'raw_points' docs/photo-pattern-editor.js
grep -q 'Suavizado suave' docs/photo-pattern-editor.js
grep -q 'Suavizado medio' docs/photo-pattern-editor.js
grep -q 'Cerrar trazo' docs/photo-pattern-editor.js
grep -q 'property_staff_access_v3' docs/photo-pattern-editor.js
grep -q 'can_write' docs/photo-pattern-editor.js
grep -q 'save-photo-pattern-contours' docs/photo-pattern-editor.js
test -s supabase/functions/save-photo-pattern-contours/index.ts
grep -q 'insufficient_write_permission' supabase/functions/save-photo-pattern-contours/index.ts
grep -q 'pattern_version_conflict' supabase/functions/save-photo-pattern-contours/index.ts
grep -q 'contour_data' supabase/functions/save-photo-pattern-contours/index.ts
if grep -q 'photo-gemini-guide.html' docs/photo-patterns.js; then
  echo 'Active photo pattern flow must not depend on Gemini.'
  exit 1
fi
grep -q 'pattern_id' docs/photo-patterns.js
grep -q 'reference_storage_path' docs/photo-reference-guide.js
grep -q 'photo-verification' docs/photo-reference-guide.js
grep -q '__allaisoReferenceMaskCanvas' docs/photo-reference-guide.js
grep -q 'mobilesam.encoder.onnx' docs/photo-reference-guide.js
grep -q 'mobilesam.decoder.quant.onnx' docs/photo-reference-guide.js
grep -q '__allaisoStructuralRegions' docs/photo-reference-guide.js
grep -q 'Guía estructural lista' docs/photo-reference-guide.js
grep -q 'onnxruntime-web@1.14.0' docs/photo-camera.html
grep -q 'openCamera.disabled = true' docs/photo-reference-guide.js
grep -q 'openCamera.disabled = false' docs/photo-reference-guide.js
grep -q 'La verificación no puede continuar' docs/photo-reference-guide.js
grep -q '__allaisoReferenceMaskCanvas' docs/photo-alignment.js
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
grep -q 'photo-camera.html' docs/cleaning.html
grep -q 'photo-camera.css' docs/photo-camera.html
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

echo 'PWA smoke checks passed'
