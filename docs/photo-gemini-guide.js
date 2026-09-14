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

function contourCentroid(contours) {
  let x = 0;
  let y = 0;
  let count = 0;

  contours.forEach(contour => {
    contour.forEach(point => {
      x += Number(point[0]);
      y += Number(point[1]);
      count++;
    });
  });

  return count ? [x / count, y / count] : [500, 500];
}

function renderOverlay(items) {
  overlay.replaceChildren();
  itemsList.replaceChildren();

  items.forEach((item, index) => {
    const [ymin, xmin, ymax, xmax] = item.box_2d.map(Number);

    const rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    rect.setAttribute("x", String(xmin));
    rect.setAttribute("y", String(ymin));
    rect.setAttribute("width", String(Math.max(0, xmax - xmin)));
    rect.setAttribute("height", String(Math.max(0, ymax - ymin)));
    rect.setAttribute("class", "gemini-box");
    overlay.append(rect);

    item.contours.forEach(contour => {
      const polygon = document.createElementNS("http://www.w3.org/2000/svg", "polygon");
      polygon.setAttribute(
        "points",
        contour.map(point => Number(point[0]) + "," + Number(point[1])).join(" ")
      );
      polygon.setAttribute("class", "gemini-contour");
      overlay.append(polygon);
    });

    const [cx, cy] = contourCentroid(item.contours);
    const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
    label.setAttribute("x", String(cx));
    label.setAttribute("y", String(cy));
    label.setAttribute("text-anchor", "middle");
    label.textContent = String(index + 1);
    overlay.append(label);

    const li = document.createElement("li");
    li.textContent = item.label + " · " + item.contours.length + " contorno" +
      (item.contours.length === 1 ? "" : "s");
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
  status.textContent = "Gemini está generando siluetas estructurales…";

  const result = await supabase.functions.invoke("generate-photo-pattern-guide", {
    body: { pattern_id: pattern.id }
  });

  if (result.error) throw result.error;
  if (!result.data?.ok || !Array.isArray(result.data.landmarks)) {
    throw new Error(result.data?.error || "gemini_guide_failed");
  }

  renderOverlay(result.data.landmarks);
  legend.hidden = false;
  status.textContent =
    "Gemini seleccionó " + result.data.landmarks.length + " estructuras/objetos.";
}

load().catch(error => {
  console.error("Gemini guide test failed", error);
  status.textContent =
    "No se pudo generar la guía Gemini: " + (error?.message || "error desconocido");
});
