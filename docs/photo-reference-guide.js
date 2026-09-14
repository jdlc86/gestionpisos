import { supabase } from "./supabase-client.js";

const params = new URLSearchParams(window.location.search);
const patternId = params.get("pattern_id");
const mode = params.get("mode");
const hint = document.getElementById("alignmentHint");
const guide = document.getElementById("cameraGuide");
const openCamera = document.getElementById("openCamera");
const cameraMessage = document.getElementById("cameraMessage");

function uuidLike(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value || "");
}

function makeEdgeMasks(image) {
  const maxSide = 720;
  const scale = Math.min(1, maxSide / Math.max(image.naturalWidth, image.naturalHeight));
  const w = Math.max(192, Math.round(image.naturalWidth * scale));
  const h = Math.max(192, Math.round(image.naturalHeight * scale));

  const source = document.createElement("canvas");
  source.width = w;
  source.height = h;
  const sctx = source.getContext("2d", { willReadFrequently: true });
  sctx.imageSmoothingEnabled = true;
  sctx.imageSmoothingQuality = "high";
  sctx.drawImage(image, 0, 0, w, h);

  const pixels = sctx.getImageData(0, 0, w, h);
  const gray = new Float32Array(w * h);
  for (let i = 0, p = 0; i < pixels.data.length; i += 4, p++) {
    gray[p] = (pixels.data[i] * 77 + pixels.data[i + 1] * 150 + pixels.data[i + 2] * 29) / 256;
  }

  const smooth = new Float32Array(w * h);
  for (let y = 1; y < h - 1; y++) {
    for (let x = 1; x < w - 1; x++) {
      const p = y * w + x;
      smooth[p] = (
        gray[p - w - 1] + 2 * gray[p - w] + gray[p - w + 1] +
        2 * gray[p - 1] + 4 * gray[p] + 2 * gray[p + 1] +
        gray[p + w - 1] + 2 * gray[p + w] + gray[p + w + 1]
      ) / 16;
    }
  }

  const magnitude = new Float32Array(w * h);
  const direction = new Uint8Array(w * h);

  for (let y = 2; y < h - 2; y++) {
    for (let x = 2; x < w - 2; x++) {
      const p = y * w + x;
      const gx =
        -smooth[p - w - 1] + smooth[p - w + 1]
        - 2 * smooth[p - 1] + 2 * smooth[p + 1]
        - smooth[p + w - 1] + smooth[p + w + 1];
      const gy =
        -smooth[p - w - 1] - 2 * smooth[p - w] - smooth[p - w + 1]
        + smooth[p + w - 1] + 2 * smooth[p + w] + smooth[p + w + 1];

      const mag = Math.hypot(gx, gy);
      magnitude[p] = mag;

      let angle = Math.atan2(gy, gx) * 180 / Math.PI;
      if (angle < 0) angle += 180;
      direction[p] =
        angle < 22.5 || angle >= 157.5 ? 0 :
        angle < 67.5 ? 1 :
        angle < 112.5 ? 2 : 3;
    }
  }

  const thin = new Uint8Array(w * h);
  const threshold = 58;

  for (let y = 2; y < h - 2; y++) {
    for (let x = 2; x < w - 2; x++) {
      const p = y * w + x;
      const mag = magnitude[p];
      if (mag < threshold) continue;

      let a;
      let b;
      switch (direction[p]) {
        case 0:
          a = magnitude[p - 1];
          b = magnitude[p + 1];
          break;
        case 1:
          a = magnitude[p - w + 1];
          b = magnitude[p + w - 1];
          break;
        case 2:
          a = magnitude[p - w];
          b = magnitude[p + w];
          break;
        default:
          a = magnitude[p - w - 1];
          b = magnitude[p + w + 1];
      }

      if (mag >= a && mag >= b) {
        thin[p] = Math.min(255, Math.round((mag - threshold) * 3.2 + 96));
      }
    }
  }

  const cleaned = new Uint8Array(w * h);
  for (let y = 2; y < h - 2; y++) {
    for (let x = 2; x < w - 2; x++) {
      const p = y * w + x;
      if (!thin[p]) continue;

      let neighbors = 0;
      for (let oy = -1; oy <= 1; oy++) {
        for (let ox = -1; ox <= 1; ox++) {
          if ((ox || oy) && thin[p + oy * w + ox]) neighbors++;
        }
      }

      if (neighbors >= 1) cleaned[p] = thin[p];
    }
  }

  const preview = document.createElement("canvas");
  preview.width = w;
  preview.height = h;
  const pctx = preview.getContext("2d");
  const previewPixels = pctx.createImageData(w, h);

  for (let p = 0; p < cleaned.length; p++) {
    const i = p * 4;
    previewPixels.data[i] = 255;
    previewPixels.data[i + 1] = 255;
    previewPixels.data[i + 2] = 255;
    previewPixels.data[i + 3] = cleaned[p];
  }
  pctx.putImageData(previewPixels, 0, 0);

  const analysis = document.createElement("canvas");
  analysis.width = w;
  analysis.height = h;
  const actx = analysis.getContext("2d");
  actx.drawImage(preview, 0, 0);

  actx.globalAlpha = 0.72;
  for (const [dx, dy] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
    actx.drawImage(preview, dx, dy);
  }
  actx.globalAlpha = 1;

  return { preview, analysis };
}

async function loadReference() {
  if (mode !== "verify" || !uuidLike(patternId)) return;

  document.documentElement.dataset.referenceGuide = "loading";
  if (openCamera) openCamera.disabled = true;
  if (hint) hint.textContent = "Cargando patrón de referencia…";
  if (cameraMessage) cameraMessage.textContent = "Cargando patrón de referencia…";

  const { data: pattern, error: patternError } = await supabase
    .from("photo_patterns_v2")
    .select("id,name,target_key,reference_storage_path,active")
    .eq("id", patternId)
    .maybeSingle();

  if (patternError) throw patternError;
  if (!pattern?.active || !pattern.reference_storage_path) throw new Error("pattern_not_available");

  const { data: blob, error: downloadError } = await supabase.storage
    .from("photo-verification")
    .download(pattern.reference_storage_path);

  if (downloadError) throw downloadError;

  const url = URL.createObjectURL(blob);
  const image = new Image();
  image.decoding = "async";

  await new Promise((resolve, reject) => {
    image.onload = resolve;
    image.onerror = reject;
    image.src = url;
  });

  const masks = makeEdgeMasks(image);
  URL.revokeObjectURL(url);

  window.__allaisoReferenceMaskCanvas = masks.analysis;
  window.__allaisoReferenceDisplayMaskCanvas = masks.preview;
  window.__allaisoReferencePattern = {
    id: pattern.id,
    name: pattern.name,
    zone: pattern.target_key
  };

  if (guide) {
    const preview = masks.preview.cloneNode(true);
    preview.width = masks.preview.width;
    preview.height = masks.preview.height;
    preview.className = "photo-camera__reference-mask";
    preview.getContext("2d").drawImage(masks.preview, 0, 0);
    guide.append(preview);
  }

  document.documentElement.dataset.referenceGuide = "ready";
  if (openCamera) openCamera.disabled = false;
  if (hint) hint.textContent = "Busca el mismo encuadre que " + pattern.target_key;
  if (cameraMessage) cameraMessage.textContent = "";
}

loadReference().catch(error => {
  console.error("reference guide failed", error);
  document.documentElement.dataset.referenceGuide = "error";
  if (openCamera) openCamera.disabled = true;
  if (hint) hint.textContent = "No se pudo cargar el patrón de referencia";
  if (cameraMessage) cameraMessage.textContent = "No se pudo cargar el patrón de referencia. La verificación no puede continuar.";
});
