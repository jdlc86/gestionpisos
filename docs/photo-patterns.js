const patternsBackLink = document.getElementById("patternsBackLink");
const patternsSource = new URLSearchParams(window.location.search).get("from");
if (patternsBackLink) {
  if (patternsSource === "workflows") {
    patternsBackLink.href = "./workflows.html";
    patternsBackLink.setAttribute("aria-label", "Volver a Flujos");
    patternsBackLink.title = "Volver a Flujos";
  } else if (patternsSource === "workflow-builder") {
    patternsBackLink.href = "./workflow-builder.html";
    patternsBackLink.setAttribute("aria-label", "Volver al Creador");
    patternsBackLink.title = "Volver al Creador";
    patternsBackLink.addEventListener("click", event => {
      if (window.history.length > 1) {
        event.preventDefault();
        window.history.back();
      }
    });
  }
}

import { supabase, getCurrentUser } from "./supabase-client.js";

const propertySelect = document.getElementById("propertySelect");
const zoneLabel = document.getElementById("zoneLabel");
const form = document.getElementById("patternForm");
const message = document.getElementById("patternMessage");
const list = document.getElementById("patternList");

let properties = [];
let writablePropertyIds = new Set();
let canCreatePatterns = false;

function option(value, text) {
  const node = document.createElement("option");
  node.value = value;
  node.textContent = text;
  return node;
}

function patternStrokeCount(pattern) {
  const strokes = pattern?.contour_data?.strokes;
  return Array.isArray(strokes) ? strokes.length : 0;
}

function renderPatterns(patterns) {
  list.replaceChildren();

  if (!patterns.length) {
    const empty = document.createElement("p");
    empty.textContent = "Todavía no hay patrones activos.";
    list.append(empty);
    return;
  }

  patterns.forEach(pattern => {
    const property = properties.find(item => item.id === pattern.property_id);
    const card = document.createElement("article");
    card.className = "pattern-card";

    const strong = document.createElement("strong");
    strong.textContent = pattern.name;

    const meta = document.createElement("span");
    const count = patternStrokeCount(pattern);
    meta.textContent = [
      property?.name,
      pattern.target_key,
      count ? count + (count === 1 ? " trazo" : " trazos") : "sin silueta"
    ].filter(Boolean).join(" · ");

    card.append(strong, meta);

    const actions = document.createElement("div");
    actions.className = "pattern-card__actions";

    if (writablePropertyIds.has(pattern.property_id)) {
      const edit = document.createElement("button");
      edit.type = "button";
      edit.className = "secondary";
      edit.textContent = count ? "Editar silueta" : "Dibujar silueta";
      edit.addEventListener("click", () => {
        const url = new URL("./photo-pattern-editor.html", window.location.href);
        url.searchParams.set("v", "2026091406");
        url.searchParams.set("pattern_id", pattern.id);
        window.location.assign(url.href);
      });
      actions.append(edit);

      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "secondary";
      remove.textContent = "Eliminar";
      remove.addEventListener("click", async () => {
        if (!window.confirm(`¿Eliminar el patrón “${pattern.name}”? Si ya tiene histórico, se conservará retirado.`)) return;
        remove.disabled = true;
        message.textContent = "Comprobando uso del patrón…";
        const { data, error } = await supabase.functions.invoke("manage-photo-pattern", {
          body: { pattern_id: pattern.id }
        });
        remove.disabled = false;
        const result = data?.result;
        if (error || !result) {
          console.error("pattern lifecycle failed", error, data);
          message.textContent = "No se pudo procesar el patrón.";
          return;
        }
        if (result.action === "blocked") {
          const uses = Array.isArray(result.usage?.uses) ? result.usage.uses : [];
          const cleaning = uses.find(item => item.kind === "cleaning");
          message.textContent = cleaning
            ? `Este patrón está siendo usado por una limpieza${cleaning.label ? " del " + cleaning.label : ""} y no puede eliminarse ni modificarse mientras siga activa.`
            : "Este patrón está siendo utilizado por un proceso activo y no puede eliminarse ni modificarse.";
          return;
        }
        message.textContent = result.action === "retired"
          ? "El patrón tiene histórico: se ha retirado y no se utilizará en nuevas asignaciones."
          : "Patrón eliminado.";
        await load();
      });
      actions.append(remove);
    }

    if (count > 0) {
      const verify = document.createElement("button");
      verify.type = "button";
      verify.className = "primary";
      verify.textContent = "Probar verificación";
      verify.addEventListener("click", () => {
        const url = new URL("./photo-camera.html", window.location.href);
        url.searchParams.set("mode", "verify");
        url.searchParams.set("pattern_id", pattern.id);
        window.location.assign(url.href);
      });
      actions.append(verify);
    }

    if (actions.childElementCount) card.append(actions);
    list.append(card);
  });
}

async function loadWriteScope(user, visibleProperties) {
  const role = user?.app_metadata?.role;

  if (role === "root" || role === "admin") {
    writablePropertyIds = new Set(visibleProperties.map(item => item.id));
    return;
  }

  const result = await supabase
    .from("property_staff_access_v3")
    .select("property_id,can_write,valid_from,valid_until,revoked_at")
    .eq("employee_user_id", user.id)
    .eq("can_write", true)
    .is("revoked_at", null);

  if (result.error) {
    writablePropertyIds = new Set();
    return;
  }

  const now = Date.now();
  writablePropertyIds = new Set(
    (result.data || [])
      .filter(row => {
        const fromOk = !row.valid_from || new Date(row.valid_from).getTime() <= now;
        const untilOk = !row.valid_until || new Date(row.valid_until).getTime() > now;
        return fromOk && untilOk;
      })
      .map(row => row.property_id)
  );
}

async function load() {
  const user = await getCurrentUser();
  const role = user?.app_metadata?.role;
  canCreatePatterns = ["root", "admin"].includes(role);

  const propertyResult = await supabase
    .from("properties_v2")
    .select("id,organization_id,name,status")
    .neq("status", "archived")
    .order("created_at");

  if (propertyResult.error) throw propertyResult.error;
  properties = propertyResult.data || [];

  await loadWriteScope(user, properties);

  if (canCreatePatterns) {
    if (!properties.length) {
      form.hidden = true;
      message.textContent = "Primero debes crear un piso en Cartera.";
    } else {
      form.hidden = false;
      propertySelect.replaceChildren(...properties.map(item => option(item.id, item.name)));
    }
  } else {
    form.hidden = true;
  }

  const patternResult = await supabase
    .from("photo_patterns_v2")
    .select("id,property_id,name,target_key,active,contour_data")
    .eq("active", true)
    .order("created_at");

  if (patternResult.error) throw patternResult.error;
  renderPatterns(patternResult.data || []);

  if (!canCreatePatterns && !writablePropertyIds.size) {
    message.textContent = "No tienes patrones con permiso de escritura.";
  }
}

form.addEventListener("submit", event => {
  event.preventDefault();
  if (!canCreatePatterns) return;

  const propertyId = propertySelect.value;
  const label = zoneLabel.value.trim();

  if (!propertyId || !label || label.length > 120) {
    message.textContent = "Selecciona un piso e indica una etiqueta de zona válida.";
    return;
  }

  const url = new URL("./photo-camera.html", window.location.href);
  url.searchParams.set("mode", "pattern");
  url.searchParams.set("property_id", propertyId);
  url.searchParams.set("zone_label", label);
  window.location.assign(url.href);
});

load().catch(error => {
  console.error("pattern bootstrap failed", error);
  form.hidden = true;
  message.textContent = "No se pudieron cargar los patrones de foto.";
});
