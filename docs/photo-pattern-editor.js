import { supabase, getCurrentUser } from "./supabase-client.js";

const params = new URLSearchParams(window.location.search);
const patternId = params.get("pattern_id");

const title = document.getElementById("editorTitle");
const message = document.getElementById("editorMessage");
const stage = document.getElementById("editorStage");
const viewport = document.getElementById("editorViewport");
const wrap = document.getElementById("imageWrap");
const image = document.getElementById("referenceImage");
const canvas = document.getElementById("drawingCanvas");
const labelWrap = document.getElementById("labelWrap");
const labelInput = document.getElementById("strokeLabel");
const toolHint = document.getElementById("toolHint");

const moveTool = document.getElementById("moveTool");
const drawTool = document.getElementById("drawTool");
const eraseTool = document.getElementById("eraseTool");
const undoBtn = document.getElementById("undoBtn");
const redoBtn = document.getElementById("redoBtn");
const zoomOutBtn = document.getElementById("zoomOutBtn");
const zoomInBtn = document.getElementById("zoomInBtn");
const clearBtn = document.getElementById("clearBtn");
const saveBtn = document.getElementById("saveBtn");
const strokeList = document.getElementById("strokeList");
const strokeCount = document.getElementById("strokeCount");

let pattern = null;
let strokes = [];
let undoStack = [];
let redoStack = [];
let drawing = false;
let activeStroke = null;
let pointerId = null;
let dirty = false;
let canWrite = false;
let resizeObserver = null;
let tool = "move";
let zoom = 1;

const smoothLevels = new Set(["none", "soft", "medium"]);
const zoomLevels = [1, 1.25, 1.5, 2, 2.5, 3];

function uuidLike(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value || "");
}

function cloneState(value = strokes) {
  return JSON.parse(JSON.stringify(value));
}

function pushHistory() {
  undoStack.push(cloneState());
  if (undoStack.length > 60) undoStack.shift();
  redoStack = [];
  updateButtons();
}

function restoreState(next) {
  strokes = cloneState(next);
  dirty = true;
  renderAll();
}

function updateButtons() {
  undoBtn.disabled = !undoStack.length || !canWrite;
  redoBtn.disabled = !redoStack.length || !canWrite;
  saveBtn.disabled = !canWrite || !dirty;
  drawTool.disabled = !canWrite;
  eraseTool.disabled = !canWrite;
  clearBtn.disabled = !canWrite || !strokes.length;

  const idx = zoomLevels.indexOf(zoom);
  zoomOutBtn.disabled = idx <= 0;
  zoomInBtn.disabled = idx >= zoomLevels.length - 1;
}

function setTool(next) {
  if (!["move", "draw", "erase"].includes(next)) return;
  if (!canWrite && next !== "move") next = "move";

  tool = next;
  wrap.dataset.tool = tool;

  [
    [moveTool, "move"],
    [drawTool, "draw"],
    [eraseTool, "erase"]
  ].forEach(([button, name]) => {
    const active = tool === name;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  });

  labelWrap.hidden = tool !== "draw";

  if (tool === "move") {
    toolHint.textContent = "Modo Mover · desplaza la foto sin dibujar.";
  } else if (tool === "draw") {
    toolHint.textContent = "Modo Dibujar · arrastra el dedo para crear un trazo.";
  } else {
    toolHint.textContent = "Modo Borrar · toca un trazo para eliminarlo.";
  }
}

function applyZoom(nextZoom) {
  zoom = nextZoom;
  wrap.style.width = Math.round(zoom * 100) + "%";
  requestAnimationFrame(() => {
    resizeCanvas();
    updateButtons();
  });
}

function normalizePoint(event) {
  const rect = canvas.getBoundingClientRect();
  return [
    Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width)),
    Math.min(1, Math.max(0, (event.clientY - rect.top) / rect.height))
  ];
}

function pointDistance(a, b) {
  return Math.hypot(a[0] - b[0], a[1] - b[1]);
}

function pointToSegmentDistance(point, a, b) {
  const vx = b[0] - a[0];
  const vy = b[1] - a[1];
  const wx = point[0] - a[0];
  const wy = point[1] - a[1];
  const len2 = vx * vx + vy * vy;
  if (!len2) return pointDistance(point, a);
  const t = Math.max(0, Math.min(1, (wx * vx + wy * vy) / len2));
  return Math.hypot(point[0] - (a[0] + t * vx), point[1] - (a[1] + t * vy));
}

function chaikin(points, iterations) {
  let out = points.map(p => [p[0], p[1]]);
  for (let k = 0; k < iterations; k++) {
    if (out.length < 3) break;
    const next = [];
    const closed = out.length > 2 && pointDistance(out[0], out[out.length - 1]) < 0.03;
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
  if (stroke.smoothing === "soft") return chaikin(stroke.raw_points, 1);
  if (stroke.smoothing === "medium") return chaikin(stroke.raw_points, 2);
  return stroke.raw_points;
}

function resizeCanvas() {
  const rect = wrap.getBoundingClientRect();
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const width = Math.max(1, Math.round(rect.width * dpr));
  const height = Math.max(1, Math.round(rect.height * dpr));
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
    renderCanvas();
  }
}

function renderCanvas() {
  const ctx = canvas.getContext("2d");
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);
  ctx.lineWidth = Math.max(3, Math.min(w, h) * 0.006);
  ctx.lineJoin = "round";
  ctx.lineCap = "round";
  ctx.strokeStyle = "rgba(255,255,255,.95)";
  ctx.shadowColor = "rgba(0,0,0,.55)";
  ctx.shadowBlur = Math.max(1, Math.min(w, h) * 0.002);

  strokes.forEach(stroke => {
    if (stroke.hidden) return;
    const pts = renderedPoints(stroke);
    if (pts.length < 2) return;

    ctx.beginPath();
    ctx.moveTo(pts[0][0] * w, pts[0][1] * h);
    for (let i = 1; i < pts.length; i++) {
      ctx.lineTo(pts[i][0] * w, pts[i][1] * h);
    }
    if (stroke.closed) ctx.closePath();
    ctx.stroke();
  });
}

function renderStrokeList() {
  strokeList.replaceChildren();
  strokeCount.textContent = String(strokes.length);

  if (!strokes.length) {
    const empty = document.createElement("p");
    empty.className = "stroke-empty";
    empty.textContent = "Todavía no hay trazos.";
    strokeList.append(empty);
    return;
  }

  strokes.forEach((stroke, index) => {
    const row = document.createElement("div");
    row.className = "stroke-row" + (stroke.hidden ? " stroke-hidden" : "");

    const label = document.createElement("input");
    label.type = "text";
    label.maxLength = 80;
    label.value = stroke.label;
    label.disabled = !canWrite;
    label.setAttribute("aria-label", "Etiqueta del trazo");
    label.addEventListener("change", () => {
      const value = label.value.trim();
      if (!value || value === stroke.label) {
        label.value = stroke.label;
        return;
      }
      pushHistory();
      stroke.label = value;
      dirty = true;
      renderAll();
    });

    const smooth = document.createElement("select");
    smooth.disabled = !canWrite;
    [
      ["none", "Original"],
      ["soft", "Suave"],
      ["medium", "Medio"]
    ].forEach(([value, text]) => {
      const opt = document.createElement("option");
      opt.value = value;
      opt.textContent = text;
      opt.selected = stroke.smoothing === value;
      smooth.append(opt);
    });
    smooth.addEventListener("change", () => {
      if (!smoothLevels.has(smooth.value) || smooth.value === stroke.smoothing) return;
      pushHistory();
      stroke.smoothing = smooth.value;
      dirty = true;
      renderAll();
    });

    const closeToggle = document.createElement("button");
    closeToggle.type = "button";
    closeToggle.className = "ghost";
    closeToggle.disabled = !canWrite;
    closeToggle.textContent = stroke.closed ? "Abrir" : "Cerrar";
    closeToggle.addEventListener("click", () => {
      pushHistory();
      stroke.closed = !stroke.closed;
      dirty = true;
      renderAll();
    });

    const visible = document.createElement("button");
    visible.type = "button";
    visible.className = "ghost";
    visible.disabled = !canWrite;
    visible.textContent = stroke.hidden ? "Mostrar" : "Ocultar";
    visible.addEventListener("click", () => {
      pushHistory();
      stroke.hidden = !stroke.hidden;
      dirty = true;
      renderAll();
    });

    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "ghost";
    remove.disabled = !canWrite;
    remove.textContent = "Borrar";
    remove.addEventListener("click", () => {
      pushHistory();
      strokes.splice(index, 1);
      dirty = true;
      renderAll();
    });

    const meta = document.createElement("div");
    meta.className = "stroke-row__meta";
    meta.textContent = stroke.raw_points.length + " puntos";

    row.append(label, smooth, closeToggle, visible, remove, meta);
    strokeList.append(row);
  });
}

function renderAll() {
  renderCanvas();
  renderStrokeList();
  updateButtons();
}

function beginStroke(event) {
  if (!canWrite || tool !== "draw" || event.button > 0) return;
  event.preventDefault();
  pointerId = event.pointerId;
  canvas.setPointerCapture(pointerId);
  drawing = true;
  pushHistory();

  const label = labelInput.value.trim() || "Trazo " + (strokes.length + 1);
  activeStroke = {
    id: crypto.randomUUID(),
    label,
    raw_points: [normalizePoint(event)],
    smoothing: "none",
    closed: false,
    hidden: false
  };
  strokes.push(activeStroke);
  dirty = true;
  renderAll();
}

function extendStroke(event) {
  if (!drawing || tool !== "draw" || event.pointerId !== pointerId || !activeStroke) return;
  event.preventDefault();
  const point = normalizePoint(event);
  const last = activeStroke.raw_points[activeStroke.raw_points.length - 1];
  if (pointDistance(last, point) < 0.0025) return;
  activeStroke.raw_points.push(point);
  renderCanvas();
}

function endStroke(event) {
  if (!drawing || event.pointerId !== pointerId) return;
  event.preventDefault();

  if (activeStroke?.raw_points?.length < 2) {
    strokes = strokes.filter(item => item !== activeStroke);
  } else {
    const first = activeStroke.raw_points[0];
    const last = activeStroke.raw_points[activeStroke.raw_points.length - 1];
    activeStroke.closed = pointDistance(first, last) < 0.035;
  }

  drawing = false;
  pointerId = null;
  activeStroke = null;
  renderAll();
}

function eraseAt(event) {
  if (!canWrite || tool !== "erase" || event.button > 0) return;
  event.preventDefault();

  const point = normalizePoint(event);
  let bestIndex = -1;
  let bestDistance = Infinity;

  strokes.forEach((stroke, index) => {
    if (stroke.hidden) return;
    const pts = renderedPoints(stroke);
    for (let i = 0; i < pts.length - 1; i++) {
      const distance = pointToSegmentDistance(point, pts[i], pts[i + 1]);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    }
  });

  const hitRadius = 0.025 / Math.max(1, zoom * 0.8);
  if (bestIndex >= 0 && bestDistance <= hitRadius) {
    pushHistory();
    strokes.splice(bestIndex, 1);
    dirty = true;
    renderAll();
  } else {
    message.textContent = "No hay ningún trazo cerca del punto tocado.";
  }
}

async function checkWritePermission(user, propertyId) {
  const role = user?.app_metadata?.role;
  if (role === "root") return true;

  if (role === "admin") {
    const org = user.app_metadata?.organization_id;
    return !org || org === pattern?.organization_id;
  }

  const { data, error } = await supabase
    .from("property_staff_access_v3")
    .select("property_id,can_write,valid_from,valid_until,revoked_at")
    .eq("property_id", propertyId)
    .eq("employee_user_id", user.id)
    .eq("can_write", true)
    .is("revoked_at", null);

  if (error) return false;
  const now = Date.now();
  return (data || []).some(row => {
    const fromOk = !row.valid_from || new Date(row.valid_from).getTime() <= now;
    const untilOk = !row.valid_until || new Date(row.valid_until).getTime() > now;
    return fromOk && untilOk;
  });
}

function sanitizeLoadedContour(data) {
  if (!data || data.version !== 1 || !Array.isArray(data.strokes)) return [];
  return data.strokes
    .filter(stroke =>
      stroke &&
      typeof stroke.id === "string" &&
      typeof stroke.label === "string" &&
      Array.isArray(stroke.raw_points)
    )
    .map(stroke => ({
      id: stroke.id,
      label: stroke.label.slice(0, 80) || "Trazo",
      raw_points: stroke.raw_points
        .filter(p => Array.isArray(p) && p.length === 2 && p.every(Number.isFinite))
        .map(p => [
          Math.min(1, Math.max(0, Number(p[0]))),
          Math.min(1, Math.max(0, Number(p[1])))
        ]),
      smoothing: smoothLevels.has(stroke.smoothing) ? stroke.smoothing : "none",
      closed: !!stroke.closed,
      hidden: !!stroke.hidden
    }))
    .filter(stroke => stroke.raw_points.length >= 2);
}

async function save() {
  if (!canWrite || !dirty) return;
  saveBtn.disabled = true;
  message.textContent = "Guardando silueta…";

  const payload = {
    version: 1,
    image: {
      width: image.naturalWidth,
      height: image.naturalHeight
    },
    strokes: strokes.map(stroke => ({
      id: stroke.id,
      label: stroke.label,
      raw_points: stroke.raw_points,
      smoothing: stroke.smoothing,
      closed: !!stroke.closed,
      hidden: !!stroke.hidden
    }))
  };

  const result = await supabase.functions.invoke("save-photo-pattern-contours", {
    body: {
      pattern_id: pattern.id,
      contour_data: payload,
      base_version: pattern.version
    }
  });

  if (result.error) throw result.error;
  if (!result.data?.ok) throw new Error(result.data?.error || "save_failed");

  pattern.version = result.data.version;
  dirty = false;
  undoStack = [];
  redoStack = [];
  message.textContent = "Silueta guardada correctamente.";
  updateButtons();
}

async function load() {
  if (!uuidLike(patternId)) throw new Error("invalid_pattern_id");

  const user = await getCurrentUser();

  const result = await supabase
    .from("photo_patterns_v2")
    .select("id,organization_id,property_id,name,target_key,reference_storage_path,contour_data,active,version")
    .eq("id", patternId)
    .maybeSingle();

  if (result.error) throw result.error;
  pattern = result.data;
  if (!pattern?.active || !pattern.reference_storage_path) throw new Error("pattern_not_available");

  canWrite = await checkWritePermission(user, pattern.property_id);
  title.textContent = "Patrón: " + (pattern.target_key || pattern.name || "sin etiqueta");

  const download = await supabase.storage
    .from("photo-verification")
    .download(pattern.reference_storage_path);

  if (download.error || !download.data) throw download.error || new Error("reference_download_failed");

  image.src = URL.createObjectURL(download.data);
  await image.decode();

  strokes = sanitizeLoadedContour(pattern.contour_data);
  dirty = false;

  stage.hidden = false;
  resizeObserver = new ResizeObserver(resizeCanvas);
  resizeObserver.observe(wrap);
  applyZoom(1);
  setTool("move");
  renderAll();

  if (!canWrite) {
    message.textContent = "Puedes consultar esta silueta, pero no tienes permiso de escritura para modificarla.";
  } else {
    message.textContent = strokes.length
      ? "Silueta cargada. Usa Mover para navegar y Dibujar para añadir trazos."
      : "Usa Mover para encuadrar la foto y Dibujar para crear el primer trazo.";
  }
}

canvas.addEventListener("pointerdown", event => {
  if (tool === "draw") beginStroke(event);
  else if (tool === "erase") eraseAt(event);
});
canvas.addEventListener("pointermove", extendStroke);
canvas.addEventListener("pointerup", endStroke);
canvas.addEventListener("pointercancel", endStroke);

moveTool.addEventListener("click", () => setTool("move"));
drawTool.addEventListener("click", () => setTool("draw"));
eraseTool.addEventListener("click", () => setTool("erase"));

undoBtn.addEventListener("click", () => {
  if (!undoStack.length || !canWrite) return;
  redoStack.push(cloneState());
  restoreState(undoStack.pop());
});

redoBtn.addEventListener("click", () => {
  if (!redoStack.length || !canWrite) return;
  undoStack.push(cloneState());
  restoreState(redoStack.pop());
});

zoomOutBtn.addEventListener("click", () => {
  const idx = zoomLevels.indexOf(zoom);
  if (idx > 0) applyZoom(zoomLevels[idx - 1]);
});

zoomInBtn.addEventListener("click", () => {
  const idx = zoomLevels.indexOf(zoom);
  if (idx < zoomLevels.length - 1) applyZoom(zoomLevels[idx + 1]);
});

clearBtn.addEventListener("click", () => {
  if (!canWrite || !strokes.length) return;
  if (!confirm("¿Borrar todos los trazos de esta silueta?")) return;
  pushHistory();
  strokes = [];
  dirty = true;
  renderAll();
});

saveBtn.addEventListener("click", () => {
  save().catch(error => {
    console.error("pattern contour save failed", error);
    if (String(error?.message || "").includes("pattern_version_conflict")) {
      message.textContent = "El patrón cambió en otra sesión. Vuelve a abrir el editor antes de guardar.";
    } else {
      message.textContent = "No se pudo guardar la silueta.";
    }
    updateButtons();
  });
});

load().catch(error => {
  console.error("manual pattern editor failed", error);
  message.textContent = "No se pudo abrir el editor de silueta.";
  saveBtn.disabled = true;
});
