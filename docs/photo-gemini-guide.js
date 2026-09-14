import { supabase } from "./supabase-client.js";

const params = new URLSearchParams(window.location.search);
const patternId = params.get("pattern_id");
const title = document.getElementById("guideTitle");
const status = document.getElementById("guideStatus");
const stage = document.getElementById("guideStage");
const image = document.getElementById("referenceImage");
const overlay = document.getElementById("guideOverlay");
const hybrid = document.getElementById("hybridOverlay");
const legend = document.getElementById("guideLegend");
const itemsList = document.getElementById("guideItems");

function uuidLike(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value || "");
}

function drawDiagnosticBoxes(items) {
  overlay.replaceChildren();
  items.forEach((item, index) => {
    const [ymin, xmin, ymax, xmax] = item.box_2d.map(Number);
    const rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    rect.setAttribute("x", String(xmin));
    rect.setAttribute("y", String(ymin));
    rect.setAttribute("width", String(Math.max(0, xmax - xmin)));
    rect.setAttribute("height", String(Math.max(0, ymax - ymin)));
    rect.setAttribute("class", "gemini-box");
    overlay.append(rect);

    const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
    label.setAttribute("x", String((xmin + xmax) / 2));
    label.setAttribute("y", String((ymin + ymax) / 2));
    label.setAttribute("text-anchor", "middle");
    label.textContent = String(index + 1);
    overlay.append(label);
  });
}

function buildContourBand(items, size) {
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  ctx.strokeStyle = "#fff";
  ctx.lineWidth = 32;
  ctx.lineJoin = "round";
  ctx.lineCap = "round";

  items.forEach(item => {
    item.contours.forEach(contour => {
      if (!contour.length) return;
      ctx.beginPath();
      contour.forEach((point, i) => {
        const x = Number(point[0]) / 1000 * size;
        const y = Number(point[1]) / 1000 * size;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      });
      ctx.closePath();
      ctx.stroke();
    });
  });

  return ctx.getImageData(0, 0, size, size).data;
}

function buildEdgeMap(size) {
  const source = document.createElement("canvas");
  source.width = size;
  source.height = size;
  const ctx = source.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(image, 0, 0, size, size);
  const rgba = ctx.getImageData(0, 0, size, size).data;
  const gray = new Float32Array(size * size);

  for (let p = 0, i = 0; p < gray.length; p++, i += 4) {
    gray[p] = rgba[i] * 0.299 + rgba[i + 1] * 0.587 + rgba[i + 2] * 0.114;
  }

  const mag = new Float32Array(size * size);
  const values = [];

  for (let y = 1; y < size - 1; y++) {
    for (let x = 1; x < size - 1; x++) {
      const p = y * size + x;
      const gx =
        -gray[p - size - 1] + gray[p - size + 1]
        - 2 * gray[p - 1] + 2 * gray[p + 1]
        - gray[p + size - 1] + gray[p + size + 1];
      const gy =
        -gray[p - size - 1] - 2 * gray[p - size] - gray[p - size + 1]
        + gray[p + size - 1] + 2 * gray[p + size] + gray[p + size + 1];
      const m = Math.hypot(gx, gy);
      mag[p] = m;
      values.push(m);
    }
  }

  values.sort((a, b) => a - b);
  const threshold = values[Math.floor(values.length * 0.88)] || 80;
  return { mag, threshold };
}

function renderHybrid(items) {
  const size = 720;
  hybrid.width = size;
  hybrid.height = size;
  const out = hybrid.getContext("2d");
  out.clearRect(0, 0, size, size);

  const band = buildContourBand(items, size);
  const { mag, threshold } = buildEdgeMap(size);
  const pixels = out.createImageData(size, size);

  for (let p = 0; p < mag.length; p++) {
    const bandAlpha = band[p * 4 + 3];
    if (!bandAlpha || mag[p] < threshold) continue;
    const i = p * 4;
    pixels.data[i] = 255;
    pixels.data[i + 1] = 255;
    pixels.data[i + 2] = 255;
    pixels.data[i + 3] = 235;
  }

  out.putImageData(pixels, 0, 0);
}

function renderLegend(items) {
  itemsList.replaceChildren();
  items.forEach(item => {
    const li = document.createElement("li");
    li.textContent = item.label;
    itemsList.append(li);
  });
}

async function load() {
  if (!uuidLike(patternId)) throw new Error("invalid_pattern_id");

  const patternResult = await supabase
    .from("photo_patterns_v2")
    .select("id,name,target_key,reference_storage_path,active")
    .eq("id", patternId)
    .maybeSingle();

  if (patternResult.error) throw patternResult.error;
  const pattern = patternResult.data;
  if (!pattern?.active || !pattern.reference_storage_path) throw new Error("pattern_not_available");

  title.textContent = "Patrón: " + (pattern.target_key || pattern.name || "sin etiqueta");

  const download = await supabase.storage
    .from("photo-verification")
    .download(pattern.reference_storage_path);

  if (download.error || !download.data) throw download.error || new Error("reference_download_failed");

  const objectUrl = URL.createObjectURL(download.data);
  image.src = objectUrl;
  await image.decode();

  stage.hidden = false;
  status.textContent = "Gemini está seleccionando estructuras…";

  const result = await supabase.functions.invoke("generate-photo-pattern-guide", {
    body: { pattern_id: pattern.id }
  });

  if (result.error) throw result.error;
  if (!result.data?.ok || !Array.isArray(result.data.landmarks)) {
    throw new Error(result.data?.error || "gemini_guide_failed");
  }

  const items = result.data.landmarks;
  drawDiagnosticBoxes(items);
  renderHybrid(items);
  renderLegend(items);
  legend.hidden = false;
  status.textContent = "Guía híbrida lista · " + items.length + " estructuras.";
}

load().catch(error => {
  console.error("Hybrid guide failed", error);
  status.textContent = "No se pudo generar la guía híbrida: " + (error?.message || "error desconocido");
});
