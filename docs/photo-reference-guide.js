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

function chaikin(points, iterations) {
  let out = points.map(p => [Number(p[0]), Number(p[1])]);
  for (let k = 0; k < iterations; k++) {
    if (out.length < 3) break;
    const next = [];
    const closed = Math.hypot(
      out[0][0] - out[out.length - 1][0],
      out[0][1] - out[out.length - 1][1]
    ) < 0.03;
    const limit = closed ? out.length : out.length - 1;
    if (!closed) next.push(out[0]);
    for (let i = 0; i < limit; i++) {
      const a = out[i];
      const b = out[(i + 1) % out.length];
      next.push([0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]]);
      next.push([0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]]);
    }
    if (!closed) next.push(out[out.length - 1]);
    out = next;
  }
  return out;
}

function renderedPoints(stroke) {
  const points = Array.isArray(stroke.raw_points) ? stroke.raw_points : [];
  if (stroke.kind !== "freehand") return points;
  if (stroke.smoothing === "soft") return chaikin(points, 1);
  if (stroke.smoothing === "medium") return chaikin(points, 2);
  return points;
}

function boundsOf(stroke) {
  const pts = stroke.raw_points || [];
  if (pts.length < 2) return null;
  return {
    minX: Math.min(Number(pts[0][0]), Number(pts[1][0])),
    minY: Math.min(Number(pts[0][1]), Number(pts[1][1])),
    maxX: Math.max(Number(pts[0][0]), Number(pts[1][0])),
    maxY: Math.max(Number(pts[0][1]), Number(pts[1][1]))
  };
}

function drawStroke(ctx, stroke, w, h) {
  if (stroke.hidden) return;
  const kind = stroke.kind || "freehand";
  const pts = renderedPoints(stroke);
  if (pts.length < 2) return;

  if (kind === "line") {
    ctx.beginPath();
    ctx.moveTo(Number(pts[0][0]) * w, Number(pts[0][1]) * h);
    ctx.lineTo(Number(pts[1][0]) * w, Number(pts[1][1]) * h);
    ctx.stroke();
    return;
  }

  if (kind === "rect") {
    const b = boundsOf(stroke);
    if (!b) return;
    ctx.strokeRect(b.minX * w, b.minY * h, (b.maxX - b.minX) * w, (b.maxY - b.minY) * h);
    return;
  }

  if (kind === "ellipse") {
    const b = boundsOf(stroke);
    if (!b) return;
    ctx.beginPath();
    ctx.ellipse(
      ((b.minX + b.maxX) / 2) * w,
      ((b.minY + b.maxY) / 2) * h,
      Math.abs(b.maxX - b.minX) * w / 2,
      Math.abs(b.maxY - b.minY) * h / 2,
      0, 0, Math.PI * 2
    );
    ctx.stroke();
    return;
  }

  ctx.beginPath();
  ctx.moveTo(Number(pts[0][0]) * w, Number(pts[0][1]) * h);
  for (let i = 1; i < pts.length; i++) {
    ctx.lineTo(Number(pts[i][0]) * w, Number(pts[i][1]) * h);
  }
  if (stroke.closed) ctx.closePath();
  ctx.stroke();
}

function makeManualMask(contourData) {
  const width = Math.max(320, Number(contourData?.image?.width) || 1200);
  const height = Math.max(240, Number(contourData?.image?.height) || 900);
  const strokes = Array.isArray(contourData?.strokes) ? contourData.strokes : [];
  const visible = strokes.filter(stroke =>
    stroke &&
    !stroke.hidden &&
    Array.isArray(stroke.raw_points) &&
    stroke.raw_points.length >= 2
  );
  if (!visible.length) throw new Error("manual_silhouette_missing");

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, width, height);
  ctx.strokeStyle = "rgba(255,255,255,.95)";
  ctx.lineWidth = Math.max(5, Math.min(width, height) * 0.008);
  ctx.lineJoin = "round";
  ctx.lineCap = "round";
  visible.forEach(stroke => drawStroke(ctx, stroke, width, height));
  return { canvas, count: visible.length };
}

async function loadReference() {
  if (mode !== "verify") return;
  if (!uuidLike(patternId)) throw new Error("pattern_id_required");

  document.documentElement.dataset.referenceGuide = "loading";
  document.documentElement.dataset.referenceEngine = "manual";
  if (openCamera) openCamera.disabled = true;
  if (hint) hint.textContent = "Cargando silueta manual…";
  if (cameraMessage) cameraMessage.textContent = "Preparando guía de referencia…";

  const { data: pattern, error: patternError } = await supabase
    .from("photo_patterns_v2")
    .select("id,name,target_key,contour_data,active")
    .eq("id", patternId)
    .maybeSingle();

  if (patternError) throw patternError;
  if (!pattern?.active) throw new Error("pattern_not_available");

  const { canvas: mask, count } = makeManualMask(pattern.contour_data);

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
  if (hint) hint.textContent = "Alinea la cámara con la silueta de " + pattern.target_key;
  if (cameraMessage) {
    cameraMessage.textContent = "Guía manual lista · " + count + (count === 1 ? " trazo." : " trazos.");
  }
}

loadReference().catch(error => {
  console.error("manual reference guide failed", error);
  document.documentElement.dataset.referenceGuide = "error";
  if (openCamera) openCamera.disabled = true;
  const code = String(error?.message || "");

  if (code.includes("manual_silhouette_missing")) {
    if (hint) hint.textContent = "Este patrón todavía no tiene silueta";
    if (cameraMessage) cameraMessage.textContent = "Dibuja y guarda una silueta manual antes de usar este patrón para verificar.";
  } else if (code.includes("pattern_id_required")) {
    if (hint) hint.textContent = "Falta seleccionar un patrón";
    if (cameraMessage) cameraMessage.textContent = "La verificación necesita un patrón válido.";
  } else {
    if (hint) hint.textContent = "No se pudo cargar la guía manual";
    if (cameraMessage) cameraMessage.textContent = "No se pudo preparar la silueta de referencia.";
  }
});
