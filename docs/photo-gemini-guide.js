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

async function waitForOpenCv(timeoutMs = 120000) {
  const started = performance.now();
  let nextStatusAt = 0;

  while (performance.now() - started < timeoutMs) {
    if (window.__opencvScriptFailed) {
      throw new Error("opencv_script_load_failed");
    }

    let cv = window.cv;
    if (cv && typeof cv.then === "function") {
      try {
        cv = await Promise.race([
          cv,
          new Promise((_, reject) =>
            setTimeout(() => reject(new Error("opencv_runtime_still_loading")), 5000)
          )
        ]);
        window.cv = cv;
      } catch (error) {
        if (error?.message !== "opencv_runtime_still_loading") throw error;
      }
    }

    if (cv?.Mat && cv?.Canny) return cv;

    const elapsed = performance.now() - started;
    if (elapsed >= nextStatusAt) {
      const seconds = Math.max(1, Math.round(elapsed / 1000));
      status.textContent = window.__opencvScriptLoaded
        ? "OpenCV descargado; inicializando motor… " + seconds + " s"
        : "Cargando OpenCV… " + seconds + " s";
      nextStatusAt = elapsed + 5000;
    }

    await new Promise(resolve => setTimeout(resolve, 150));
  }

  throw new Error(
    window.__opencvScriptLoaded
      ? "opencv_runtime_timeout"
      : "opencv_script_timeout"
  );
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

function renderLegend(items) {
  itemsList.replaceChildren();
  items.forEach(item => {
    const li = document.createElement("li");
    li.textContent = item.label;
    itemsList.append(li);
  });
}

function processingSize() {
  const maxSide = 900;
  const naturalWidth = Math.max(1, image.naturalWidth);
  const naturalHeight = Math.max(1, image.naturalHeight);
  const scale = Math.min(1, maxSide / Math.max(naturalWidth, naturalHeight));
  return {
    width: Math.max(320, Math.round(naturalWidth * scale)),
    height: Math.max(320, Math.round(naturalHeight * scale))
  };
}

function buildSourceCanvas(width, height) {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(image, 0, 0, width, height);
  return canvas;
}

function densifyClosedContour(contour, width, height) {
  const base = contour.map(point => ({
    x: Number(point[0]) / 1000 * width,
    y: Number(point[1]) / 1000 * height
  }));
  if (base.length < 3) return [];

  const dense = [];
  const step = Math.max(3, Math.min(width, height) * 0.006);

  for (let i = 0; i < base.length; i++) {
    const a = base[i];
    const b = base[(i + 1) % base.length];
    const distance = Math.hypot(b.x - a.x, b.y - a.y);
    const segments = Math.max(1, Math.ceil(distance / step));

    for (let s = 0; s < segments; s++) {
      const t = s / segments;
      dense.push({
        x: a.x + (b.x - a.x) * t,
        y: a.y + (b.y - a.y) * t
      });
    }
  }

  return dense;
}

function nearestEdgePoint(edges, width, height, point, radius) {
  const cx = Math.round(point.x);
  const cy = Math.round(point.y);
  let best = null;
  let bestDistance = Infinity;

  for (let dy = -radius; dy <= radius; dy++) {
    const y = cy + dy;
    if (y < 1 || y >= height - 1) continue;

    for (let dx = -radius; dx <= radius; dx++) {
      const x = cx + dx;
      if (x < 1 || x >= width - 1) continue;

      const distance2 = dx * dx + dy * dy;
      if (distance2 >= bestDistance) continue;
      if (edges[y * width + x] === 0) continue;

      bestDistance = distance2;
      best = { x, y };
    }
  }

  return best || point;
}

function smoothClosed(points, radius = 3) {
  if (points.length < radius * 2 + 1) return points;

  return points.map((_, index) => {
    let x = 0;
    let y = 0;
    let weight = 0;

    for (let offset = -radius; offset <= radius; offset++) {
      const p = points[(index + offset + points.length) % points.length];
      const w = radius + 1 - Math.abs(offset);
      x += p.x * w;
      y += p.y * w;
      weight += w;
    }

    return { x: x / weight, y: y / weight };
  });
}

function contourDisplacement(original, snapped) {
  if (!original.length || original.length !== snapped.length) return Infinity;
  let total = 0;
  for (let i = 0; i < original.length; i++) {
    total += Math.hypot(snapped[i].x - original[i].x, snapped[i].y - original[i].y);
  }
  return total / original.length;
}

function drawSmoothClosedPath(ctx, points) {
  if (points.length < 3) return;

  const last = points[points.length - 1];
  const first = points[0];
  ctx.beginPath();
  ctx.moveTo((last.x + first.x) / 2, (last.y + first.y) / 2);

  for (let i = 0; i < points.length; i++) {
    const current = points[i];
    const next = points[(i + 1) % points.length];
    const midX = (current.x + next.x) / 2;
    const midY = (current.y + next.y) / 2;
    ctx.quadraticCurveTo(current.x, current.y, midX, midY);
  }

  ctx.closePath();
  ctx.stroke();
}

function renderSnappedGuide(cv, items) {
  const { width, height } = processingSize();
  const sourceCanvas = buildSourceCanvas(width, height);

  hybrid.width = width;
  hybrid.height = height;

  let src;
  let gray;
  let blurred;
  let edges;

  try {
    src = cv.matFromImageData(
      sourceCanvas.getContext("2d").getImageData(0, 0, width, height)
    );
    gray = new cv.Mat();
    blurred = new cv.Mat();
    edges = new cv.Mat();

    cv.cvtColor(src, gray, cv.COLOR_RGBA2GRAY);
    cv.GaussianBlur(gray, blurred, new cv.Size(5, 5), 0, 0, cv.BORDER_DEFAULT);
    cv.Canny(blurred, edges, 45, 130, 3, true);

    const edgeData = edges.data;
    const ctx = hybrid.getContext("2d");
    ctx.clearRect(0, 0, width, height);
    ctx.strokeStyle = "rgba(255,255,255,.94)";
    ctx.lineWidth = Math.max(2, Math.min(width, height) * 0.0035);
    ctx.lineJoin = "round";
    ctx.lineCap = "round";
    ctx.shadowColor = "rgba(0,0,0,.55)";
    ctx.shadowBlur = 1.5;

    const searchRadius = Math.max(8, Math.round(Math.min(width, height) * 0.018));
    let drawn = 0;

    items.forEach(item => {
      item.contours.forEach(contour => {
        const dense = densifyClosedContour(contour, width, height);
        if (dense.length < 8) return;

        const snapped = dense.map(point =>
          nearestEdgePoint(edgeData, width, height, point, searchRadius)
        );

        const avgShift = contourDisplacement(dense, snapped);
        if (!Number.isFinite(avgShift) || avgShift > searchRadius * 0.9) return;

        const once = smoothClosed(snapped, 2);
        const twice = smoothClosed(once, 2);
        drawSmoothClosedPath(ctx, twice);
        drawn++;
      });
    });

    return drawn;
  } finally {
    [src, gray, blurred, edges].forEach(mat => mat?.delete?.());
  }
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
  if (!pattern?.active || !pattern.reference_storage_path) {
    throw new Error("pattern_not_available");
  }

  title.textContent = "Patrón: " + (pattern.target_key || pattern.name || "sin etiqueta");

  const download = await supabase.storage
    .from("photo-verification")
    .download(pattern.reference_storage_path);

  if (download.error || !download.data) {
    throw download.error || new Error("reference_download_failed");
  }

  const objectUrl = URL.createObjectURL(download.data);
  image.src = objectUrl;
  await image.decode();

  stage.hidden = false;
  status.textContent = "Gemini está seleccionando estructuras…";

  const [result, cv] = await Promise.all([
    supabase.functions.invoke("generate-photo-pattern-guide", {
      body: { pattern_id: pattern.id }
    }),
    waitForOpenCv()
  ]);

  if (result.error) throw result.error;
  if (!result.data?.ok || !Array.isArray(result.data.landmarks)) {
    throw new Error(result.data?.error || "gemini_guide_failed");
  }

  const items = result.data.landmarks;
  drawDiagnosticBoxes(items);
  status.textContent = "OpenCV está ajustando los contornos al borde real…";

  const contourCount = renderSnappedGuide(cv, items);
  renderLegend(items);
  legend.hidden = false;

  if (!contourCount) {
    throw new Error("opencv_no_snapped_contours");
  }

  status.textContent =
    "Guía ajustada a borde real · " + items.length +
    " estructuras · " + contourCount + " contornos.";
}

load().catch(error => {
  console.error("OpenCV snap guide failed", error);
  status.textContent =
    "No se pudo generar la guía ajustada: " + (error?.message || "error desconocido");
});
