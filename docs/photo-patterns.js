import { supabase, getCurrentUser } from "./supabase-client.js";

const propertySelect = document.getElementById("propertySelect");
const zoneLabel = document.getElementById("zoneLabel");
const form = document.getElementById("patternForm");
const message = document.getElementById("patternMessage");
const list = document.getElementById("patternList");

let properties = [];

function option(value, text) {
  const node = document.createElement("option");
  node.value = value;
  node.textContent = text;
  return node;
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
    meta.textContent = [property?.name, pattern.target_key].filter(Boolean).join(" · ");

    card.append(strong, meta);
    list.append(card);
  });
}

async function load() {
  const user = await getCurrentUser();
  const role = user?.app_metadata?.role;

  if (!["root", "admin"].includes(role)) {
    form.hidden = true;
    message.textContent = "Solo ROOT/ADMIN pueden registrar patrones.";
    return;
  }

  const propertyResult = await supabase
    .from("properties_v2")
    .select("id,organization_id,name,status")
    .neq("status", "archived")
    .order("created_at");

  if (propertyResult.error) throw propertyResult.error;
  properties = propertyResult.data || [];

  if (!properties.length) {
    form.hidden = true;
    message.textContent = "Primero debes crear un piso en Cartera.";
    return;
  }

  propertySelect.replaceChildren(...properties.map(item => option(item.id, item.name)));

  const patternResult = await supabase
    .from("photo_patterns_v2")
    .select("id,property_id,name,target_key,active")
    .eq("active", true)
    .order("created_at");

  if (patternResult.error) throw patternResult.error;
  renderPatterns(patternResult.data || []);
}

form.addEventListener("submit", event => {
  event.preventDefault();

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
  message.textContent = "No se pudieron cargar los datos para registrar el patrón.";
});
