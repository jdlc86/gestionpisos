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
grep -q 'Probar guía Gemini' docs/photo-patterns.js
test -s docs/photo-gemini-guide.html
test -s docs/photo-gemini-guide.css
test -s docs/photo-gemini-guide.js
grep -q 'generate-photo-pattern-guide' docs/photo-gemini-guide.js
grep -q 'waitForOpenCv' docs/photo-gemini-guide.js
grep -q 'cv.Canny' docs/photo-gemini-guide.js
grep -q 'nearestEdgePoint' docs/photo-gemini-guide.js
grep -q 'smoothClosed' docs/photo-gemini-guide.js
grep -q 'drawSmoothClosedPath' docs/photo-gemini-guide.js
grep -q 'Guía ajustada a borde real' docs/photo-gemini-guide.js
grep -q '@techstark/opencv-js@4.10.0-release.1/dist/opencv.js' docs/photo-gemini-guide.html
grep -q '__opencvReady' docs/photo-gemini-guide.html
grep -q 'onRuntimeInitialized' docs/photo-gemini-guide.html
grep -q 'landmarks' supabase/functions/generate-photo-pattern-guide/index.ts
grep -q 'Contour coordinates are ABSOLUTE' supabase/functions/generate-photo-pattern-guide/index.ts
grep -q 'same physical furniture unit' supabase/functions/generate-photo-pattern-guide/index.ts
grep -q 'gemini-box' docs/photo-gemini-guide.css
grep -q 'photo-gemini-guide.html' docs/photo-patterns.js
test -s supabase/functions/generate-photo-pattern-guide/index.ts
grep -q 'CONTORNO_GEMINI_API_KEY' supabase/functions/generate-photo-pattern-guide/index.ts
grep -q 'gemini-3.6-flash' supabase/functions/generate-photo-pattern-guide/index.ts
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
