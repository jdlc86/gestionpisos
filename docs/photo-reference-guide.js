import { supabase } from "./supabase-client.js";

const params = new URLSearchParams(window.location.search);
const patternId = params.get("pattern_id");
const mode = params.get("mode");
const hint = document.getElementById("alignmentHint");
const guide = document.getElementById("cameraGuide");
const openCamera = document.getElementById("openCamera");
const cameraMessage = document.getElementById("cameraMessage");

const ENCODER_URL = "https://huggingface.co/spaces/Akbartus/projects/resolve/main/mobilesam.encoder.onnx";
const DECODER_URL = "https://cdn.jsdelivr.net/gh/akbartus/MobileSAM-in-the-Browser@main/models/mobilesam.decoder.quant.onnx";
const MODEL_W = 1024;
const MODEL_H = 684;

function uuidLike(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value || "");
}

function makeInputTensor(image, ort) {
  const canvas = document.createElement("canvas");
  canvas.width = MODEL_W;
  canvas.height = MODEL_H;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(image, 0, 0, MODEL_W, MODEL_H);
  const rgba = ctx.getImageData(0, 0, MODEL_W, MODEL_H).data;
  const rgb = new Float32Array(MODEL_W * MODEL_H * 3);

  for (let p = 0, i = 0, o = 0; p < MODEL_W * MODEL_H; p++, i += 4, o += 3) {
    rgb[o] = rgba[i];
    rgb[o + 1] = rgba[i + 1];
    rgb[o + 2] = rgba[i + 2];
  }
  return new ort.Tensor("float32", rgb, [MODEL_H, MODEL_W, 3]);
}

function maskFromTensor(tensor) {
  const values = tensor.data;
  const size = MODEL_W * MODEL_H;
  const offset = Math.max(0, values.length - size);
  const mask = new Uint8Array(size);
  let area = 0;

  for (let i = 0; i < size; i++) {
    if (Number(values[offset + i]) > 0) {
      mask[i] = 1;
      area++;
    }
  }
  return { mask, area };
}

function iou(a, b) {
  let intersection = 0;
  let union = 0;
  for (let i = 0; i < a.length; i++) {
    const av = a[i] !== 0;
    const bv = b[i] !== 0;
    if (av && bv) intersection++;
    if (av || bv) union++;
  }
  return union ? intersection / union : 0;
}

function structuralMask(regions) {
  const canvas = document.createElement("canvas");
  canvas.width = MODEL_W;
  canvas.height = MODEL_H;
  const ctx = canvas.getContext("2d");
  const imageData = ctx.createImageData(MODEL_W, MODEL_H);
  const out = imageData.data;

  for (const region of regions) {
    const mask = region.mask;
    for (let y = 1; y < MODEL_H - 1; y++) {
      for (let x = 1; x < MODEL_W - 1; x++) {
        const p = y * MODEL_W + x;
        if (!mask[p]) continue;
        const boundary =
          !mask[p - 1] || !mask[p + 1] ||
          !mask[p - MODEL_W] || !mask[p + MODEL_W];
        if (!boundary) continue;

        const i = p * 4;
        out[i] = 255;
        out[i + 1] = 255;
        out[i + 2] = 255;
        out[i + 3] = 235;
      }
    }
  }

  ctx.putImageData(imageData, 0, 0);
  return canvas;
}

async function makeStructuralMask(image) {
  const ort = window.ort;
  if (!ort?.InferenceSession) throw new Error("mobilesam_runtime_missing");

  ort.env.wasm.numThreads = 1;
  ort.env.wasm.wasmPaths = "https://cdn.jsdelivr.net/npm/onnxruntime-web@1.14.0/dist/";

  if (hint) hint.textContent = "Analizando estructura de la escena…";

  const encoder = await ort.InferenceSession.create(ENCODER_URL);
  const encoderResult = await encoder.run({
    input_image: makeInputTensor(image, ort)
  });
  const embeddings = encoderResult.image_embeddings;
  if (!embeddings) throw new Error("mobilesam_embedding_missing");

  const decoder = await ort.InferenceSession.create(DECODER_URL);
  const maskInput = new ort.Tensor("float32", new Float32Array(256 * 256), [1, 1, 256, 256]);
  const hasMask = new ort.Tensor("float32", new Float32Array([0]), [1]);
  const originalSize = new ort.Tensor("float32", new Float32Array([MODEL_H, MODEL_W]), [2]);

  const points = [];
  for (const fy of [0.20, 0.40, 0.60, 0.80]) {
    for (const fx of [0.20, 0.40, 0.60, 0.80]) {
      points.push([Math.round(MODEL_W * fx), Math.round(MODEL_H * fy)]);
    }
  }

  const candidates = [];
  const total = MODEL_W * MODEL_H;

  for (const [x, y] of points) {
    const pointCoords = new ort.Tensor("float32", new Float32Array([x, y, 0, 0]), [1, 2, 2]);
    const pointLabels = new ort.Tensor("float32", new Float32Array([1, -1]), [1, 2]);

    const result = await decoder.run({
      image_embeddings: embeddings,
      point_coords: pointCoords,
      point_labels: pointLabels,
      mask_input: maskInput,
      has_mask_input: hasMask,
      orig_im_size: originalSize
    });

    const tensor = result.masks || result[decoder.outputNames.find(name => name.includes("mask"))];
    if (!tensor) continue;

    const region = maskFromTensor(tensor);
    const ratio = region.area / total;
    if (ratio < 0.025 || ratio > 0.72) continue;

    if (candidates.some(existing => iou(existing.mask, region.mask) > 0.82)) continue;
    candidates.push(region);
  }

  candidates.sort((a, b) => b.area - a.area);
  const selected = candidates.slice(0, 10);
  if (selected.length < 2) throw new Error("mobilesam_not_enough_regions");

  window.__allaisoStructuralRegions = selected.length;
  return structuralMask(selected);
}

async function loadReference() {
  if (mode !== "verify" || !uuidLike(patternId)) return;

  document.documentElement.dataset.referenceGuide = "loading";
  document.documentElement.dataset.referenceEngine = "mobilesam";
  if (openCamera) openCamera.disabled = true;
  if (hint) hint.textContent = "Cargando patrón de referencia…";
  if (cameraMessage) cameraMessage.textContent = "Cargando modelo de estructura de escena…";

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

  const mask = await makeStructuralMask(image);
  URL.revokeObjectURL(url);

  window.__allaisoReferenceMaskCanvas = mask;
  window.__allaisoReferencePattern = {
    id: pattern.id,
    name: pattern.name,
    zone: pattern.target_key
  };

  if (guide) {
    guide.querySelectorAll(".photo-camera__reference-mask").forEach(node => node.remove());
    const preview = mask.cloneNode(true);
    preview.width = mask.width;
    preview.height = mask.height;
    preview.className = "photo-camera__reference-mask";
    preview.getContext("2d").drawImage(mask, 0, 0);
    guide.append(preview);
  }

  document.documentElement.dataset.referenceGuide = "ready";
  if (openCamera) openCamera.disabled = false;
  if (hint) hint.textContent = "Alinea las estructuras principales de " + pattern.target_key;
  if (cameraMessage) {
    cameraMessage.textContent = "Guía estructural lista · " +
      (window.__allaisoStructuralRegions || 0) + " regiones.";
  }
}

loadReference().catch(error => {
  console.error("structural reference guide failed", error);
  document.documentElement.dataset.referenceGuide = "error";
  if (openCamera) openCamera.disabled = true;
  if (hint) hint.textContent = "No se pudo generar la guía estructural";
  if (cameraMessage) {
    cameraMessage.textContent = "No se pudo analizar la estructura de la escena. La verificación no puede continuar.";
  }
});
