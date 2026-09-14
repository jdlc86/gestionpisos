import { supabase, getCurrentUser } from "./supabase-client.js";

const propertySelect = document.getElementById("propertySelect");
const roomSelect = document.getElementById("roomSelect");
const patternName = document.getElementById("patternName");
const form = document.getElementById("patternForm");
const button = document.getElementById("captureReference");
const message = document.getElementById("patternMessage");
const list = document.getElementById("patternList");

let properties = [];
let rooms = [];

function option(value, text) {
  const node = document.createElement("option");
  node.value = value;
  node.textContent = text;
  return node;
}

function renderRooms() {
  const propertyId = propertySelect.value;
  const matches = rooms.filter(room => room.property_id === propertyId && room.status !== "archived");
  roomSelect.replaceChildren(...matches.map(room => option(room.id, room.label)));
  button.disabled = !matches.length;
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
    const room = rooms.find(item => item.id === pattern.target_key);
    const card = document.createElement("article");
    card.className = "pattern-card";

    const strong = document.createElement("strong");
    strong.textContent = pattern.name;

    const meta = document.createElement("span");
    meta.textContent = [property?.name, room?.label].filter(Boolean).join(" · ");

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

  const roomResult = await supabase
    .from("rooms_v2")
    .select("id,property_id,label,status")
    .in("property_id", properties.map(item => item.id))
    .order("created_at");

  if (roomResult.error) throw roomResult.error;
  rooms = roomResult.data || [];

  propertySelect.replaceChildren(...properties.map(item => option(item.id, item.name)));
  renderRooms();

  const patternResult = await supabase
    .from("photo_patterns_v2")
    .select("id,property_id,name,target_key,active")
    .eq("active", true)
    .order("created_at");

  if (patternResult.error) throw patternResult.error;
  renderPatterns(patternResult.data || []);
}

propertySelect.addEventListener("change", renderRooms);

form.addEventListener("submit", event => {
  event.preventDefault();

  const propertyId = propertySelect.value;
  const roomId = roomSelect.value;
  const name = patternName.value.trim();
  const room = rooms.find(item => item.id === roomId && item.property_id === propertyId);

  if (!room || !name) {
    message.textContent = "Selecciona un piso, una habitación y un nombre válido.";
    return;
  }

  const url = new URL("./photo-camera.html", window.location.href);
  url.searchParams.set("mode", "pattern");
  url.searchParams.set("property_id", propertyId);
  url.searchParams.set("room_id", roomId);
  url.searchParams.set("pattern_name", name);
  window.location.assign(url.href);
});

load().catch(error => {
  console.error("pattern bootstrap failed", error);
  form.hidden = true;
  message.textContent = "No se pudieron cargar los datos para registrar el patrón.";
});
