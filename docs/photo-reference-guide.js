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


const PIDINET_MODEL_URL = "https://huggingface.co/bdck/PiDiNet_ONNX/resolve/main/table5_pidinet_tiny.onnx";
const PIDINET_DATA_URL = "https://huggingface.co/bdck/PiDiNet_ONNX/resolve/main/table5_pidinet_tiny.onnx.data";
const ORT_MODULE_URL = "https://cdn.jsdelivr.net/npm/onnxruntime-web@1.29.0/+esm";

function roundedModelSize(width, height) {
  const maxSide = 512;
  const scale = Math.min(1, maxSide / Math.max(width, height));
  const round32 = value => Math.max(128, Math.round(value * scale / 32) * 32);
  return { width: round32(width), height: round32(height) };
}

function edgeThreshold(values) {
  const histogram = new Uint32Array(256);
  for (let i = 0; i < values.length; i++) {
    const v = Math.max(0, Math.min(1, values[i]));
    histogram[Math.min(255, Math.round(v * 255))]++;
  }

  const target = Math.max(1, Math.round(values.length * 0.10));
  let seen = 0;
  for (let i = 255; i >= 0; i--) {
    seen += histogram[i];
    if (seen >= target) return Math.max(0.16, Math.min(0.52, i / 255));
  }
  return 0.28;
}

async function makeNeuralEdgeMask(image) {
  const ort = await import(ORT_MODULE_URL);
  ort.env.wasm.wasmPaths = "https://cdn.jsdelivr.net/npm/onnxruntime-web@1.29.0/dist/";

  const size = roundedModelSize(image.naturalWidth, image.naturalHeight);
  const source = document.createElement("canvas");
  source.width = size.width;
  source.height = size.height;
  const ctx = source.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(image, 0, 0, size.width, size.height);

  const pixels = ctx.getImageData(0, 0, size.width, size.height).data;
  const plane = size.width * size.height;
  const input = new Float32Array(plane * 3);
  const mean = [0.485, 0.456, 0.406];
  const std = [0.229, 0.224, 0.225];

  for (let p = 0, i = 0; p < plane; p++, i += 4) {
    input[p] = (pixels[i] / 255 - mean[0]) / std[0];
    input[plane + p] = (pixels[i + 1] / 255 - mean[1]) / std[1];
    input[plane * 2 + p] = (pixels[i + 2] / 255 - mean[2]) / std[2];
  }

  const session = await ort.InferenceSession.create(PIDINET_MODEL_URL, {
    executionProviders: ["wasm"],
    externalData: [{
      path: "table5_pidinet_tiny.onnx.data",
      data: PIDINET_DATA_URL
    }]
  });

  const results = await session.run({
    image: new ort.Tensor("float32", input, [1, 3, size.height, size.width])
  });

  const fused = results.fused || results[session.outputNames[session.outputNames.length - 1]];
  if (!fused?.data?.length) throw new Error("pidinet_missing_output");

  const values = fused.data;
  const threshold = edgeThreshold(values);
  const out = document.createElement("canvas");
  out.width = size.width;
  out.height = size.height;
  const octx = out.getContext("2d");
  const result = octx.createImageData(size.width, size.height);

  for (let p = 0; p < plane; p++) {
    const value = Math.max(0, Math.min(1, Number(values[p]) || 0));
    const alpha = value >= threshold
      ? Math.min(255, Math.round(185 + ((value - threshold) / Math.max(0.001, 1 - threshold)) * 70))
      : 0;
    const i = p * 4;
    result.data[i] = 255;
    result.data[i + 1] = 255;
    result.data[i + 2] = 255;
    result.data[i + 3] = alpha;
  }

  octx.putImageData(result, 0, 0);
  return out;
}

function makeEdgeMask(image) {
  const maxSide = 360;
  const scale = Math.min(1, maxSide / Math.max(image.naturalWidth, image.naturalHeight));
  const w = Math.max(96, Math.round(image.naturalWidth * scale));
  const h = Math.max(96, Math.round(image.naturalHeight * scale));

  const source = document.createElement("canvas");
  source.width = w;
  source.height = h;
  const sctx = source.getContext("2d", { willReadFrequently: true });
  sctx.drawImage(image, 0, 0, w, h);

  const pixels = sctx.getImageData(0, 0, w, h);
  const gray = new Uint8Array(w * h);
  for (let i = 0, p = 0; i < pixels.data.length; i += 4, p++) {
    gray[p] = (pixels.data[i] * 77 + pixels.data[i + 1] * 150 + pixels.data[i + 2] * 29) >> 8;
  }

  const out = document.createElement("canvas");
  out.width = w;
  out.height = h;
  const octx = out.getContext("2d");
  const result = octx.createImageData(w, h);

  for (let y = 1; y < h - 1; y++) {
    for (let x = 1; x < w - 1; x++) {
      const p = y * w + x;
      const gx =
        -gray[p - w - 1] + gray[p - w + 1]
        - 2 * gray[p - 1] + 2 * gray[p + 1]
        - gray[p + w - 1] + gray[p + w + 1];
      const gy =
        -gray[p - w - 1] - 2 * gray[p - w] - gray[p - w + 1]
        + gray[p + w - 1] + 2 * gray[p + w] + gray[p + w + 1];
      const mag = Math.hypot(gx, gy);
      const alpha = mag > 70 ? Math.min(255, Math.round((mag - 70) * 2.1)) : 0;
      const i = p * 4;
      result.data[i] = 255;
      result.data[i + 1] = 255;
      result.data[i + 2] = 255;
      result.data[i + 3] = alpha;
    }
  }

  octx.putImageData(result, 0, 0);
  return out;
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

  let mask;
  let engine = "pidinet";
  try {
    if (hint) hint.textContent = "Generando patrón neuronal…";
    mask = await makeNeuralEdgeMask(image);
  } catch (neuralError) {
    console.warn("PiDiNet unavailable, using Sobel fallback", neuralError);
    engine = "sobel";
    mask = makeEdgeMask(image);
  }
  URL.revokeObjectURL(url);
  document.documentElement.dataset.referenceEngine = engine;

  window.__allaisoReferenceMaskCanvas = mask;
  window.__allaisoReferencePattern = {
    id: pattern.id,
    name: pattern.name,
    zone: pattern.target_key
  };

  if (guide) {
    const preview = mask.cloneNode(true);
    preview.width = mask.width;
    preview.height = mask.height;
    preview.className = "photo-camera__reference-mask";
    preview.getContext("2d").drawImage(mask, 0, 0);
    guide.append(preview);
  }

  document.documentElement.dataset.referenceGuide = "ready";
  if (openCamera) openCamera.disabled = false;
  if (hint) hint.textContent = "Busca el mismo encuadre que " + pattern.target_key;
  if (cameraMessage) cameraMessage.textContent = engine === "pidinet" ? "Patrón neuronal listo." : "Patrón Sobel de respaldo listo.";
}

loadReference().catch(error => {
  console.error("reference guide failed", error);
  document.documentElement.dataset.referenceGuide = "error";
  if (openCamera) openCamera.disabled = true;
  if (hint) hint.textContent = "No se pudo cargar el patrón de referencia";
  if (cameraMessage) cameraMessage.textContent = "No se pudo cargar el patrón de referencia. La verificación no puede continuar.";
});
