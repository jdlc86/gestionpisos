import { supabase } from "./supabase-client.js";

const params = new URLSearchParams(window.location.search);
const patternId = params.get("pattern_id");
const title = document.getElementById("guideTitle");
const status = document.getElementById("guideStatus");
const stage = document.getElementById("guideStage");
const image = document.getElementById("referenceImage");
const overlay = document.getElementById("guideOverlay");
const legend = document.getElementById("guideLegend");
const itemsList = document.getElementById("guideItems");

function uuidLike(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value || "");
}

function pointsBounds(points) {
  const xs = points.map(point => point[0]);
  const ys = points.map(point => point[1]);
  return {
    xmin: Math.min(...xs),
    ymin: Math.min(...ys),
    xmax: Math.max(...xs),
    ymax: Math.max(...ys)
  };
}

function boxFitError(points, box) {
  const [ymin, xmin, ymax, xmax] = box;
  const bounds = pointsBounds(points);
  const scale = Math.max(1, (xmax - xmin) + (ymax - ymin));
  const edgeError =
    Math.abs(bounds.xmin - xmin) +
    Math.abs(bounds.xmax - xmax) +
    Math.abs(bounds.ymin - ymin) +
    Math.abs(bounds.ymax - ymax);
  const outside =
    Math.max(0, xmin - bounds.xmin) +
    Math.max(0, bounds.xmax - xmax) +
    Math.max(0, ymin - bounds.ymin) +
    Math.max(0, bounds.ymax - ymax);
  return (edgeError + outside * 4) / scale;
}

function polygonPoints(item) {
  const box = item.box_2d.map(Number);
  const [ymin, xmin, ymax, xmax] = box;
  const width = Math.max(1, xmax - xmin);
  const height = Math.max(1, ymax - ymin);
  const raw = item.mask.map(point => [Number(point[0]), Number(point[1])]);

  const candidates = [
    {
      mode: "relative_xy",
      points: raw.map(([x, y]) => [
        xmin + (x / 1000) * width,
        ymin + (y / 1000) * height
      ])
    },
    {
      mode: "relative_yx",
      points: raw.map(([y, x]) => [
        xmin + (x / 1000) * width,
        ymin + (y / 1000) * height
      ])
    },
    {
      mode: "absolute_xy",
      points: raw.map(([x, y]) => [x, y])
    },
    {
      mode: "absolute_yx",
      points: raw.map(([y, x]) => [x, y])
    }
  ];

  candidates.forEach(candidate => {
    candidate.error = boxFitError(candidate.points, box);
  });
  candidates.sort((a, b) => a.error - b.error);

  item.__renderMode = candidates[0].mode;
  return candidates[0].points;
}

function polygonCentroid(points) {
  if (!points.length) return [500, 500];
  let x = 0;
  let y = 0;
  for (const point of points) {
    x += point[0];
    y += point[1];
  }
  return [x / points.length, y / points.length];
}

function renderOverlay(items) {
  overlay.replaceChildren();
  itemsList.replaceChildren();

  items.forEach((item, index) => {
    const points = polygonPoints(item);
    const [ymin, xmin, ymax, xmax] = item.box_2d.map(Number);
    const rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    rect.setAttribute("x", String(xmin));
    rect.setAttribute("y", String(ymin));
    rect.setAttribute("width", String(Math.max(0, xmax - xmin)));
    rect.setAttribute("height", String(Math.max(0, ymax - ymin)));
    rect.setAttribute("class", "gemini-box");
    overlay.append(rect);

    const polygon = document.createElementNS("http://www.w3.org/2000/svg", "polygon");
    polygon.setAttribute("points", points.map(point => point.join(",")).join(" "));
    overlay.append(polygon);

    const [cx, cy] = polygonCentroid(points);
    const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
    label.setAttribute("x", String(cx));
    label.setAttribute("y", String(cy));
    label.setAttribute("text-anchor", "middle");
    label.textContent = String(index + 1);
    overlay.append(label);

    const li = document.createElement("li");
    li.textContent = item.label + " · " + (item.__renderMode || "mask");
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
  status.textContent = "Gemini está interpretando la escena…";

  const result = await supabase.functions.invoke("generate-photo-pattern-guide", {
    body: { pattern_id: pattern.id }
  });

  if (result.error) throw result.error;
  if (!result.data?.ok || !Array.isArray(result.data.boxes)) {
    throw new Error(result.data?.error || "gemini_guide_failed");
  }

  renderOverlay(result.data.boxes);
  legend.hidden = false;
  status.textContent = "Gemini seleccionó " + result.data.boxes.length + " estructuras/objetos.";
}

load().catch(error => {
  console.error("Gemini guide test failed", error);
  status.textContent = "No se pudo generar la guía Gemini: " + (error?.message || "error desconocido");
});
