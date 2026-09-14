import { supabase, getCurrentUser } from "./supabase-client.js";

const params = new URLSearchParams(window.location.search);
const patternId = params.get("pattern_id");

const title = document.getElementById("editorTitle");
const message = document.getElementById("editorMessage");
const stage = document.getElementById("editorStage");
const wrap = document.getElementById("imageWrap");
const image = document.getElementById("referenceImage");
const canvas = document.getElementById("drawingCanvas");
const labelWrap = document.getElementById("labelWrap");
const labelInput = document.getElementById("strokeLabel");
const toolHint = document.getElementById("toolHint");

const moveTool = document.getElementById("moveTool");
const selectTool = document.getElementById("selectTool");
const drawTool = document.getElementById("drawTool");
const lineTool = document.getElementById("lineTool");
const rectTool = document.getElementById("rectTool");
const ellipseTool = document.getElementById("ellipseTool");
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
let selectedId = null;
let selectionAction = null;

const smoothLevels = new Set(["none", "soft", "medium"]);
const shapeKinds = new Set(["freehand", "line", "rect", "ellipse"]);
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
  selectedId = null;
  dirty = true;
  renderAll();
}

function selectedStroke() {
  return strokes.find(item => item.id === selectedId) || null;
}

function updateButtons() {
  undoBtn.disabled = !undoStack.length || !canWrite;
  redoBtn.disabled = !redoStack.length || !canWrite;
  saveBtn.disabled = !canWrite || !dirty;
  [selectTool, drawTool, lineTool, rectTool, ellipseTool, eraseTool].forEach(btn => {
    btn.disabled = !canWrite;
  });
  clearBtn.disabled = !canWrite || !strokes.length;

  const idx = zoomLevels.indexOf(zoom);
  zoomOutBtn.disabled = idx <= 0;
  zoomInBtn.disabled = idx >= zoomLevels.length - 1;
}

function syncLabelEditor() {
  const selected = selectedStroke();
  const creationMode = ["draw", "line", "rect", "ellipse"].includes(tool);
  const selectionMode = tool === "select" && !!selected;

  labelWrap.hidden = !(creationMode || selectionMode);

  if (selectionMode) {
    labelWrap.firstChild.textContent = "Etiqueta seleccionada ";
    labelInput.value = selected.label || "";
    labelInput.placeholder = "Ej. Ventilador";
  } else if (creationMode) {
    labelWrap.firstChild.textContent = "Etiqueta del siguiente elemento ";
    labelInput.placeholder = "Ej. Ventilador";
  }
}

function setTool(next) {
  const allowed = ["move", "select", "draw", "line", "rect", "ellipse", "erase"];
  if (!allowed.includes(next)) return;
  if (!canWrite && next !== "move") next = "move";

  tool = next;
  wrap.dataset.tool = tool;

  [
    [moveTool, "move"],
    [selectTool, "select"],
    [drawTool, "draw"],
    [lineTool, "line"],
    [rectTool, "rect"],
    [ellipseTool, "ellipse"],
    [eraseTool, "erase"]
  ].forEach(([button, name]) => {
    const active = tool === name;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  });

  syncLabelEditor();

  const hints = {
    move: "Modo Mover · desplaza la foto sin dibujar.",
    select: "Modo Seleccionar · toca una figura para moverla o cambiar su tamaño.",
    draw: "Modo Lápiz · dibuja un trazo libre.",
    line: "Modo Recta · arrastra entre dos puntos.",
    rect: "Modo Rectángulo · arrastra de una esquina a la opuesta.",
    ellipse: "Modo Elipse · arrastra para definir su caja.",
    erase: "Modo Borrar · toca una figura o trazo para eliminarlo."
  };
  toolHint.textContent = hints[tool];
  renderCanvas();
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
  if (stroke.kind !== "freehand") return stroke.raw_points;
  if (stroke.smoothing === "soft") return chaikin(stroke.raw_points, 1);
  if (stroke.smoothing === "medium") return chaikin(stroke.raw_points, 2);
  return stroke.raw_points;
}

function boundsOf(stroke) {
  const pts = stroke.raw_points;
  if (!pts.length) return null;
  if (stroke.kind === "line") {
    return {
      minX: Math.min(pts[0][0], pts[1][0]),
      minY: Math.min(pts[0][1], pts[1][1]),
      maxX: Math.max(pts[0][0], pts[1][0]),
      maxY: Math.max(pts[0][1], pts[1][1])
    };
  }
  if (stroke.kind === "rect" || stroke.kind === "ellipse") {
    return {
      minX: Math.min(pts[0][0], pts[1][0]),
      minY: Math.min(pts[0][1], pts[1][1]),
      maxX: Math.max(pts[0][0], pts[1][0]),
      maxY: Math.max(pts[0][1], pts[1][1])
    };
  }

  const rendered = renderedPoints(stroke);
  return rendered.reduce((acc, p) => ({
    minX: Math.min(acc.minX, p[0]),
    minY: Math.min(acc.minY, p[1]),
    maxX: Math.max(acc.maxX, p[0]),
    maxY: Math.max(acc.maxY, p[1])
  }), { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity });
}

function shapeHandles(stroke) {
  if (stroke.kind === "line") {
    return [
      { key: "p0", point: stroke.raw_points[0] },
      { key: "p1", point: stroke.raw_points[1] }
    ];
  }
  if (stroke.kind === "rect" || stroke.kind === "ellipse") {
    const b = boundsOf(stroke);
    return [
      { key: "nw", point: [b.minX, b.minY] },
      { key: "ne", point: [b.maxX, b.minY] },
      { key: "se", point: [b.maxX, b.maxY] },
      { key: "sw", point: [b.minX, b.maxY] }
    ];
  }
  return [];
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

function drawStroke(ctx, stroke, w, h) {
  const pts = renderedPoints(stroke);
  if (pts.length < 2) return;

  if (stroke.kind === "line") {
    ctx.beginPath();
    ctx.moveTo(pts[0][0] * w, pts[0][1] * h);
    ctx.lineTo(pts[1][0] * w, pts[1][1] * h);
    ctx.stroke();
    return;
  }

  if (stroke.kind === "rect") {
    const b = boundsOf(stroke);
    ctx.strokeRect(
      b.minX * w,
      b.minY * h,
      (b.maxX - b.minX) * w,
      (b.maxY - b.minY) * h
    );
    return;
  }

  if (stroke.kind === "ellipse") {
    const b = boundsOf(stroke);
    ctx.beginPath();
    ctx.ellipse(
      ((b.minX + b.maxX) / 2) * w,
      ((b.minY + b.maxY) / 2) * h,
      ((b.maxX - b.minX) / 2) * w,
      ((b.maxY - b.minY) / 2) * h,
      0,
      0,
      Math.PI * 2
    );
    ctx.stroke();
    return;
  }

  ctx.beginPath();
  ctx.moveTo(pts[0][0] * w, pts[0][1] * h);
  for (let i = 1; i < pts.length; i++) {
    ctx.lineTo(pts[i][0] * w, pts[i][1] * h);
  }
  if (stroke.closed) ctx.closePath();
  ctx.stroke();
}

function renderSelection(ctx, stroke, w, h) {
  if (!stroke || tool !== "select") return;
  const b = boundsOf(stroke);
  if (!b) return;

  ctx.save();
  ctx.setLineDash([8, 6]);
  ctx.strokeStyle = "rgba(255,215,0,.95)";
  ctx.lineWidth = Math.max(2, Math.min(w, h) * 0.003);
  ctx.strokeRect(
    b.minX * w,
    b.minY * h,
    Math.max(1, (b.maxX - b.minX) * w),
    Math.max(1, (b.maxY - b.minY) * h)
  );
  ctx.setLineDash([]);

  const radius = Math.max(7, Math.min(w, h) * 0.012);
  shapeHandles(stroke).forEach(handle => {
    ctx.beginPath();
    ctx.fillStyle = "#fff";
    ctx.strokeStyle = "#000";
    ctx.lineWidth = 2;
    ctx.arc(handle.point[0] * w, handle.point[1] * h, radius, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
  });
  ctx.restore();
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
    if (!stroke.hidden) drawStroke(ctx, stroke, w, h);
  });

  renderSelection(ctx, selectedStroke(), w, h);
}

function kindLabel(kind) {
  return {
    freehand: "Lápiz",
    line: "Recta",
    rect: "Rectángulo",
    ellipse: "Elipse"
  }[kind] || "Trazo";
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
    label.setAttribute("aria-label", "Etiqueta del elemento");
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
    smooth.disabled = !canWrite || stroke.kind !== "freehand";
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
      if (stroke.kind !== "freehand") return;
      if (!smoothLevels.has(smooth.value) || smooth.value === stroke.smoothing) return;
      pushHistory();
      stroke.smoothing = smooth.value;
      dirty = true;
      renderAll();
    });

    const closeToggle = document.createElement("button");
    closeToggle.type = "button";
    closeToggle.className = "ghost";
    closeToggle.disabled = !canWrite || stroke.kind !== "freehand";
    closeToggle.textContent = stroke.closed ? "Abrir" : "Cerrar";
    closeToggle.addEventListener("click", () => {
      if (stroke.kind !== "freehand") return;
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
      if (selectedId === stroke.id) selectedId = null;
      dirty = true;
      renderAll();
    });

    const meta = document.createElement("div");
    meta.className = "stroke-row__meta";
    meta.textContent = kindLabel(stroke.kind) + " · " + stroke.raw_points.length + " puntos";

    row.append(label, smooth, closeToggle, visible, remove, meta);
    strokeList.append(row);
  });
}

function renderAll() {
  renderCanvas();
  renderStrokeList();
  syncLabelEditor();
  updateButtons();
}

function defaultLabel(kind) {
  const typed = labelInput.value.trim();
  if (typed) return typed;
  const prefix = {
    freehand: "Trazo",
    line: "Recta",
    rect: "Rectángulo",
    ellipse: "Elipse"
  }[kind] || "Trazo";
  return prefix + " " + (strokes.length + 1);
}

function beginCreate(event, kind) {
  if (!canWrite || event.button > 0) return;
  event.preventDefault();
  pointerId = event.pointerId;
  canvas.setPointerCapture(pointerId);
  drawing = true;
  pushHistory();

  const start = normalizePoint(event);
  activeStroke = {
    id: crypto.randomUUID(),
    label: defaultLabel(kind),
    kind,
    raw_points: kind === "freehand" ? [start] : [start, start],
    smoothing: "none",
    closed: kind === "rect" || kind === "ellipse",
    hidden: false
  };

  strokes.push(activeStroke);
  selectedId = activeStroke.id;
  dirty = true;
  renderAll();
}

function extendCreate(event) {
  if (!drawing || event.pointerId !== pointerId || !activeStroke) return;
  event.preventDefault();
  const point = normalizePoint(event);

  if (activeStroke.kind === "freehand") {
    const last = activeStroke.raw_points[activeStroke.raw_points.length - 1];
    if (pointDistance(last, point) < 0.0025) return;
    activeStroke.raw_points.push(point);
  } else {
    activeStroke.raw_points[1] = point;
  }
  renderCanvas();
}

function endCreate(event) {
  if (!drawing || event.pointerId !== pointerId) return;
  event.preventDefault();

  if (activeStroke?.kind === "freehand") {
    if (activeStroke.raw_points.length < 2) {
      strokes = strokes.filter(item => item !== activeStroke);
      selectedId = null;
    } else {
      const first = activeStroke.raw_points[0];
      const last = activeStroke.raw_points[activeStroke.raw_points.length - 1];
      activeStroke.closed = pointDistance(first, last) < 0.035;
    }
  } else if (activeStroke && pointDistance(activeStroke.raw_points[0], activeStroke.raw_points[1]) < 0.005) {
    strokes = strokes.filter(item => item !== activeStroke);
    selectedId = null;
  }

  drawing = false;
  pointerId = null;
  activeStroke = null;
  renderAll();
}

function hitDistance(stroke, point) {
  if (stroke.hidden) return Infinity;

  if (stroke.kind === "line") {
    return pointToSegmentDistance(point, stroke.raw_points[0], stroke.raw_points[1]);
  }

  if (stroke.kind === "rect") {
    const b = boundsOf(stroke);
    const edges = [
      [[b.minX,b.minY],[b.maxX,b.minY]],
      [[b.maxX,b.minY],[b.maxX,b.maxY]],
      [[b.maxX,b.maxY],[b.minX,b.maxY]],
      [[b.minX,b.maxY],[b.minX,b.minY]]
    ];
    return Math.min(...edges.map(([a,bp]) => pointToSegmentDistance(point,a,bp)));
  }

  if (stroke.kind === "ellipse") {
    const b = boundsOf(stroke);
    const rx = Math.max(0.0001, (b.maxX - b.minX) / 2);
    const ry = Math.max(0.0001, (b.maxY - b.minY) / 2);
    const cx = (b.minX + b.maxX) / 2;
    const cy = (b.minY + b.maxY) / 2;
    const norm = Math.hypot((point[0]-cx)/rx, (point[1]-cy)/ry);
    return Math.abs(norm - 1) * Math.min(rx, ry);
  }

  const pts = renderedPoints(stroke);
  let best = Infinity;
  for (let i = 0; i < pts.length - 1; i++) {
    best = Math.min(best, pointToSegmentDistance(point, pts[i], pts[i+1]));
  }
  return best;
}

function nearestStroke(point) {
  let best = null;
  let distance = Infinity;
  strokes.forEach(stroke => {
    const d = hitDistance(stroke, point);
    if (d < distance) {
      distance = d;
      best = stroke;
    }
  });
  const hitRadius = 0.025 / Math.max(1, zoom * 0.8);
  return distance <= hitRadius ? best : null;
}

function handleAt(stroke, point) {
  const hitRadius = 0.03 / Math.max(1, zoom * 0.8);
  return shapeHandles(stroke).find(handle => pointDistance(handle.point, point) <= hitRadius) || null;
}

function beginSelection(event) {
  if (!canWrite || tool !== "select" || event.button > 0) return;
  event.preventDefault();
  pointerId = event.pointerId;
  canvas.setPointerCapture(pointerId);
  const point = normalizePoint(event);
  const selected = selectedStroke();

  if (selected) {
    const handle = handleAt(selected, point);
    if (handle) {
      pushHistory();
      selectionAction = {
        type: "resize",
        strokeId: selected.id,
        handle: handle.key,
        startPoint: point,
        startStroke: cloneState([selected])[0]
      };
      return;
    }
  }

  const hit = nearestStroke(point);
  selectedId = hit?.id || null;
  syncLabelEditor();
  if (hit) {
    pushHistory();
    selectionAction = {
      type: "move",
      strokeId: hit.id,
      startPoint: point,
      startStroke: cloneState([hit])[0]
    };
  } else {
    selectionAction = null;
  }
  renderCanvas();
}

function clamp01(value) {
  return Math.min(1, Math.max(0, value));
}

function moveStrokeFromSnapshot(stroke, snapshot, dx, dy) {
  stroke.raw_points = snapshot.raw_points.map(p => [
    clamp01(p[0] + dx),
    clamp01(p[1] + dy)
  ]);
}

function resizePrimitive(stroke, snapshot, handle, point) {
  if (stroke.kind === "line") {
    stroke.raw_points = cloneState([snapshot.raw_points])[0];
    stroke.raw_points[handle === "p0" ? 0 : 1] = [clamp01(point[0]), clamp01(point[1])];
    return;
  }

  if (stroke.kind !== "rect" && stroke.kind !== "ellipse") return;
  const b = boundsOf(snapshot);
  let minX = b.minX, minY = b.minY, maxX = b.maxX, maxY = b.maxY;

  if (handle.includes("w")) minX = clamp01(point[0]);
  if (handle.includes("e")) maxX = clamp01(point[0]);
  if (handle.includes("n")) minY = clamp01(point[1]);
  if (handle.includes("s")) maxY = clamp01(point[1]);

  stroke.raw_points = [[minX, minY], [maxX, maxY]];
}

function updateSelection(event) {
  if (!selectionAction || event.pointerId !== pointerId) return;
  event.preventDefault();

  const point = normalizePoint(event);
  const stroke = strokes.find(item => item.id === selectionAction.strokeId);
  if (!stroke) return;

  if (selectionAction.type === "move") {
    const dx = point[0] - selectionAction.startPoint[0];
    const dy = point[1] - selectionAction.startPoint[1];
    moveStrokeFromSnapshot(stroke, selectionAction.startStroke, dx, dy);
  } else if (selectionAction.type === "resize") {
    resizePrimitive(stroke, selectionAction.startStroke, selectionAction.handle, point);
  }

  dirty = true;
  renderCanvas();
}

function endSelection(event) {
  if (event.pointerId !== pointerId) return;
  if (selectionAction) {
    dirty = true;
    renderAll();
  }
  selectionAction = null;
  pointerId = null;
}

function eraseAt(event) {
  if (!canWrite || tool !== "erase" || event.button > 0) return;
  event.preventDefault();
  const hit = nearestStroke(normalizePoint(event));
  if (!hit) {
    message.textContent = "No hay ningún elemento cerca del punto tocado.";
    return;
  }
  pushHistory();
  strokes = strokes.filter(item => item.id !== hit.id);
  if (selectedId === hit.id) selectedId = null;
  dirty = true;
  renderAll();
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
    .map(stroke => {
      const kind = shapeKinds.has(stroke.kind) ? stroke.kind : "freehand";
      return {
        id: stroke.id,
        label: stroke.label.slice(0, 80) || "Trazo",
        kind,
        raw_points: stroke.raw_points
          .filter(p => Array.isArray(p) && p.length === 2 && p.every(Number.isFinite))
          .map(p => [
            Math.min(1, Math.max(0, Number(p[0]))),
            Math.min(1, Math.max(0, Number(p[1])))
          ]),
        smoothing: smoothLevels.has(stroke.smoothing) ? stroke.smoothing : "none",
        closed: kind === "rect" || kind === "ellipse" ? true : !!stroke.closed,
        hidden: !!stroke.hidden
      };
    })
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
      kind: stroke.kind || "freehand",
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

  if (result.error) {
    let detail = "edge_function_failed";
    try {
      if (result.error.context?.json) {
        const body = await result.error.context.json();
        detail = body?.error || detail;
      } else if (result.error.message) {
        detail = result.error.message;
      }
    } catch {}
    throw new Error(detail);
  }
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
      ? "Silueta cargada. Puedes mover, seleccionar o añadir nuevas figuras."
      : "Usa Lápiz, Recta, Rectángulo o Elipse para crear la primera referencia.";
  }
}

canvas.addEventListener("pointerdown", event => {
  if (tool === "draw") beginCreate(event, "freehand");
  else if (tool === "line") beginCreate(event, "line");
  else if (tool === "rect") beginCreate(event, "rect");
  else if (tool === "ellipse") beginCreate(event, "ellipse");
  else if (tool === "select") beginSelection(event);
  else if (tool === "erase") eraseAt(event);
});

canvas.addEventListener("pointermove", event => {
  if (drawing) extendCreate(event);
  else if (selectionAction) updateSelection(event);
});

canvas.addEventListener("pointerup", event => {
  if (drawing) endCreate(event);
  else if (selectionAction || pointerId === event.pointerId) endSelection(event);
});

canvas.addEventListener("pointercancel", event => {
  if (drawing) endCreate(event);
  else endSelection(event);
});


labelInput.addEventListener("input", () => {
  if (!canWrite || tool !== "select") return;
  const selected = selectedStroke();
  if (!selected) return;

  const value = labelInput.value.slice(0, 80);
  if (!value.trim() || value === selected.label) return;

  pushHistory();
  selected.label = value;
  dirty = true;
  updateButtons();
  renderStrokeList();
});

labelInput.addEventListener("change", () => {
  if (tool !== "select") return;
  const selected = selectedStroke();
  if (!selected) return;

  const value = labelInput.value.trim();
  if (!value) {
    labelInput.value = selected.label;
    return;
  }

  if (value !== selected.label) {
    pushHistory();
    selected.label = value;
    dirty = true;
    renderAll();
  }
});


moveTool.addEventListener("click", () => setTool("move"));
selectTool.addEventListener("click", () => setTool("select"));
drawTool.addEventListener("click", () => setTool("draw"));
lineTool.addEventListener("click", () => setTool("line"));
rectTool.addEventListener("click", () => setTool("rect"));
ellipseTool.addEventListener("click", () => setTool("ellipse"));
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
  selectedId = null;
  dirty = true;
  renderAll();
});

saveBtn.addEventListener("click", () => {
  save().catch(error => {
    console.error("pattern contour save failed", error);
    const code = String(error?.message || "save_failed");
    if (code.includes("pattern_version_conflict")) {
      message.textContent = "El patrón cambió en otra sesión. Vuelve a abrir el editor antes de guardar.";
    } else if (code.includes("invalid_session")) {
      message.textContent = "La sesión no es válida. Vuelve a entrar antes de guardar.";
    } else if (code.includes("insufficient_write_permission")) {
      message.textContent = "No tienes permiso de escritura para guardar esta silueta.";
    } else if (code.includes("invalid_contour_data")) {
      message.textContent = "La silueta contiene datos no válidos y no se ha guardado.";
    } else {
      message.textContent = "No se pudo guardar la silueta: " + code;
    }
    updateButtons();
  });
});

load().catch(error => {
  console.error("manual pattern editor failed", error);
  message.textContent = "No se pudo abrir el editor de silueta.";
  saveBtn.disabled = true;
});
