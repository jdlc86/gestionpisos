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

async function waitForOpenCv(timeoutMs = 20000) {
  const started = performance.now();
  while (performance.now() - started < timeoutMs) {
    let cv = window.cv;
    if (cv && typeof cv.then === "function") {
      try {
        cv = await cv;
        window.cv = cv;
      } catch {
        cv = null;
      }
    }
    if (cv?.Mat && cv?.Canny && cv?.findContours) return cv;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error("opencv_runtime_unavailable");
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

function buildSemanticBand(items, width, height) {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");

  ctx.strokeStyle = "#fff";
  ctx.lineWidth = Math.max(14, Math.round(Math.min(width, height) * 0.032));
  ctx.lineJoin = "round";
  ctx.lineCap = "round";

  items.forEach(item => {
    item.contours.forEach(contour => {
      if (!Array.isArray(contour) || contour.length < 3) return;
      ctx.beginPath();
      contour.forEach((point, index) => {
        const x = Number(point[0]) / 1000 * width;
        const y = Number(point[1]) / 1000 * height;
        if (index === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      });
      ctx.closePath();
      ctx.stroke();
    });
  });

  return canvas;
}

function renderOpenCvGuide(cv, items) {
  const { width, height } = processingSize();
  const sourceCanvas = buildSourceCanvas(width, height);
  const bandCanvas = buildSemanticBand(items, width, height);

  hybrid.width = width;
  hybrid.height = height;

  let src;
  let gray;
  let blurred;
  let edges;
  let bandRgba;
  let bandGray;
  let bandMask;
  let masked;
  let cleaned;
  let kernel;
  let contours;
  let hierarchy;
  let drawing;

  try {
    src = cv.matFromImageData(
      sourceCanvas.getContext("2d").getImageData(0, 0, width, height)
    );
    gray = new cv.Mat();
    blurred = new cv.Mat();
    edges = new cv.Mat();

    cv.cvtColor(src, gray, cv.COLOR_RGBA2GRAY);
    cv.GaussianBlur(gray, blurred, new cv.Size(5, 5), 0, 0, cv.BORDER_DEFAULT);
    cv.Canny(blurred, edges, 55, 145, 3, true);

    bandRgba = cv.matFromImageData(
      bandCanvas.getContext("2d").getImageData(0, 0, width, height)
    );
    bandGray = new cv.Mat();
    bandMask = new cv.Mat();
    cv.cvtColor(bandRgba, bandGray, cv.COLOR_RGBA2GRAY);
    cv.threshold(bandGray, bandMask, 1, 255, cv.THRESH_BINARY);

    masked = new cv.Mat();
    cv.bitwise_and(edges, bandMask, masked);

    kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, new cv.Size(3, 3));
    cleaned = new cv.Mat();
    cv.morphologyEx(
      masked,
      cleaned,
      cv.MORPH_CLOSE,
      kernel,
      new cv.Point(-1, -1),
      1
    );

    contours = new cv.MatVector();
    hierarchy = new cv.Mat();
    cv.findContours(
      cleaned,
      contours,
      hierarchy,
      cv.RETR_LIST,
      cv.CHAIN_APPROX_NONE
    );

    drawing = cv.Mat.zeros(height, width, cv.CV_8UC4);
    const minLength = Math.max(18, Math.min(width, height) * 0.025);
    let kept = 0;

    for (let i = 0; i < contours.size(); i++) {
      const contour = contours.get(i);
      const length = cv.arcLength(contour, false);

      if (length >= minLength) {
        const approx = new cv.Mat();
        const epsilon = Math.max(0.55, length * 0.0015);
        cv.approxPolyDP(contour, approx, epsilon, false);

        if (approx.rows >= 3) {
          const vector = new cv.MatVector();
          vector.push_back(approx);
          cv.drawContours(
            drawing,
            vector,
            0,
            new cv.Scalar(255, 255, 255, 235),
            2,
            cv.LINE_AA
          );
          vector.delete();
          kept++;
        }

        approx.delete();
      }

      contour.delete();
    }

    cv.imshow(hybrid, drawing);
    return kept;
  } finally {
    [
      src, gray, blurred, edges, bandRgba, bandGray, bandMask,
      masked, cleaned, kernel, hierarchy, drawing
    ].forEach(mat => mat?.delete?.());
    contours?.delete?.();
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
  status.textContent = "OpenCV está extrayendo los bordes reales…";

  const contourCount = renderOpenCvGuide(cv, items);
  renderLegend(items);
  legend.hidden = false;

  if (!contourCount) {
    throw new Error("opencv_no_useful_contours");
  }

  status.textContent =
    "Guía OpenCV lista · " + items.length +
    " estructuras · " + contourCount + " trazos.";
}

load().catch(error => {
  console.error("OpenCV hybrid guide failed", error);
  status.textContent =
    "No se pudo generar la guía OpenCV: " + (error?.message || "error desconocido");
});
