import { supabase, getCurrentUser } from "./supabase-client.js";

const views = {
  owners: {
    title: "Propietarios",
    action: "Añadir propietario",
    emptyTitle: "No hay propietarios en este estado",
    emptyText: "Las altas aparecerán aquí y conservarán la relación con sus pisos.",
    singular: "propietario",
    statuses: ["active", "blocked", "archived"],
    fields: [
      { key: "fullName", label: "Nombre completo", type: "text", required: true },
      { key: "email", label: "Email", type: "email" },
      { key: "phone", label: "Teléfono", type: "tel" }
    ]
  },
  properties: {
    title: "Pisos",
    action: "Añadir piso",
    emptyTitle: "No hay pisos en este estado",
    emptyText: "Cada piso debe permanecer asociado a un propietario.",
    singular: "piso",
    statuses: ["onboarding", "active", "maintenance", "blocked", "offboarding", "archived"],
    fields: [
      { key: "ownerId", label: "Propietario", type: "relation", relation: "owners", required: true },
      { key: "name", label: "Nombre interno", type: "text", required: true },
      { key: "address", label: "Dirección", type: "text", required: true },
      { key: "city", label: "Ciudad", type: "text" },
      { key: "postalCode", label: "Código postal", type: "text" }
    ]
  },
  occupancies: {
    title: "Inquilinos",
    action: "Añadir inquilino",
    emptyTitle: "No hay inquilinos en este estado",
    emptyText: "Las ocupaciones relacionan al inquilino con su piso, habitación y periodo de estancia.",
    singular: "inquilino",
    statuses: ["active", "blocked", "archived"],
    fields: [
      { key: "fullName", label: "Nombre completo", type: "text", required: true },
      { key: "documentType", label: "Tipo de documento", type: "select", options: [["dni","DNI"],["nie","NIE"],["passport","Pasaporte"],["other","Otro"]], required: true },
      { key: "documentNumber", label: "Número de documento", type: "text", required: true },
      { key: "email", label: "Email", type: "email", required: true },
      { key: "propertyId", label: "Piso", type: "relation", relation: "properties", required: true },
      { key: "roomId", label: "Habitación", type: "relation", relation: "rooms", required: true },
      { key: "startsOn", label: "Fecha de entrada", type: "date", required: true },
      { key: "indefinite", label: "Estancia indefinida", type: "checkbox" },
      { key: "endsOn", label: "Fecha de salida", type: "date" }
    ]
  },
  rooms: {
    title: "Habitaciones",
    action: "Añadir habitación",
    emptyTitle: "No hay habitaciones en este estado",
    emptyText: "Cada habitación debe permanecer asociada a un piso.",
    singular: "habitación",
    statuses: ["active", "blocked", "archived"],
    fields: [
      { key: "propertyId", label: "Piso", type: "relation", relation: "properties", required: true },
      { key: "label", label: "Etiqueta", type: "text", required: true },
      { key: "description", label: "Descripción", type: "textarea" }
    ]
  }
};

const labels = {
  active: "Alta",
  blocked: "Suspendido",
  archived: "Baja · pendiente de eliminación",
  onboarding: "En alta",
  maintenance: "Mantenimiento",
  offboarding: "En baja"
};

const auditLabels = {
  owner_created: "Alta",
  owner_updated: "Datos editados",
  owner_archived: "Baja lógica",
  owner_reactivated: "Reactivado",
  property_created: "Alta",
  property_updated: "Datos editados",
  property_archived: "Baja lógica",
  property_reactivated: "Reactivado",
  room_created: "Alta",
  room_updated: "Datos editados",
  room_archived: "Baja lógica",
  room_reactivated: "Reactivado"
};

const state = { organizations: [], owners: [], properties: [], rooms: [], occupancies: [] };
let current = "owners";
let editingId = null;
let organizationId = null;
let role = null;

const $ = id => document.getElementById(id);
const title = $("sectionTitle");
const emptyState = $("emptyState");
const emptyTitle = $("emptyTitle");
const emptyText = $("emptyText");
const records = $("records");
const summary = $("relationshipSummary");
const action = $("newItemBtn");
const statusFilter = $("statusFilter");
const organizationField = $("organizationField");
const organizationSelect = $("organizationSelect");
const editorDialog = $("editorDialog");
const editorForm = $("editorForm");
const editorTitle = $("editorTitle");
const editorFields = $("editorFields");
const saveButton = $("saveDraftBtn");
const saveErrorDialog = $("saveErrorDialog");
const saveErrorMessage = $("saveErrorMessage");
const historyDialog = $("historyDialog");
const historyTitle = $("historyTitle");
const historyList = $("historyList");
const documentsDialog = $("documentsDialog");
const documentsTitle = $("documentsTitle");
const documentsList = $("documentsList");
const documentForm = $("documentForm");
const documentName = $("documentName");
const documentType = $("documentType");
const documentFile = $("documentFile");
let documentsTenantId = null;
const statusLine = $("portfolioStatus");

function setStatus(text, strong = "") {
  statusLine.replaceChildren();
  if (strong) {
    const s = document.createElement("strong");
    s.textContent = strong;
    statusLine.append(s, document.createTextNode(" " + text));
  } else {
    statusLine.textContent = text;
  }
}

function createElement(tag, className, content) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (content !== undefined) element.textContent = content;
  return element;
}

function itemName(type, item) {
  if (!item) return "Sin relación";
  if (type === "owners") return item.fullName;
  if (type === "properties") return item.name;
  if (type === "occupancies") return item.fullName || item.email;
  return item.label;
}

function findItem(type, id) {
  return state[type].find(item => item.id === id);
}

function makeSummaryCell(value, label) {
  const cell = createElement("div", "summary-cell");
  cell.append(createElement("strong", "", String(value)), createElement("span", "", label));
  return cell;
}

function renderSummary() {
  summary.replaceChildren(
    makeSummaryCell(state.owners.filter(x => x.status !== "archived").length, "propietarios en cartera"),
    makeSummaryCell(state.properties.filter(x => x.status !== "archived").length, "pisos en cartera"),
    makeSummaryCell(state.rooms.filter(x => x.status !== "archived").length, "habitaciones en cartera"),
    makeSummaryCell(state.occupancies.filter(x => x.status !== "archived").length, "inquilinos")
  );
}

function visibleItems() {
  const filter = statusFilter.value;
  return state[current].filter(item => {
    if (filter === "all") return true;
    if (filter === "archived") return item.status === "archived";
    return item.status !== "archived";
  });
}

function relationChips(item) {
  const chips = createElement("div", "relation-chips");
  if (current === "owners") {
    const properties = state.properties.filter(property => property.ownerId === item.id);
    chips.append(createElement("span", "relation-chip", `${properties.length} piso${properties.length === 1 ? "" : "s"}`));
    properties.slice(0, 2).forEach(property => chips.append(createElement("span", "relation-chip", property.name)));
  } else if (current === "properties") {
    const owner = findItem("owners", item.ownerId);
    const rooms = state.rooms.filter(room => room.propertyId === item.id);
    chips.append(
      createElement("span", "relation-chip", `Propietario: ${itemName("owners", owner)}`),
      createElement("span", "relation-chip", `${rooms.length} habitación${rooms.length === 1 ? "" : "es"}`)
    );
  } else if (current === "occupancies") {
    const property = findItem("properties", item.propertyId);
    const room = findItem("rooms", item.roomId);
    chips.append(
      createElement("span", "relation-chip", `Piso: ${itemName("properties", property)}`),
      createElement("span", "relation-chip", `Habitación: ${itemName("rooms", room)}`)
    );
  } else {
    const property = findItem("properties", item.propertyId);
    const owner = property ? findItem("owners", property.ownerId) : null;
    chips.append(
      createElement("span", "relation-chip", `Piso: ${itemName("properties", property)}`),
      createElement("span", "relation-chip", `Propietario: ${itemName("owners", owner)}`)
    );
  }
  return chips;
}

function descriptionFor(item) {
  if (current === "owners") return [item.email, item.phone].filter(Boolean).join(" · ") || "Sin datos de contacto";
  if (current === "properties") return [item.address, item.city, item.postalCode].filter(Boolean).join(" · ");
  if (current === "occupancies") return [item.email, item.documentNumber ? `${item.documentType.toUpperCase()}: ${item.documentNumber}` : "", item.startsOn ? `Entrada: ${item.startsOn}` : "", item.endsOn ? `Salida: ${item.endsOn}` : "Sin fecha de salida"].filter(Boolean).join(" · ");
  return item.description || "Sin descripción";
}

function formatDate(value) {
  return new Intl.DateTimeFormat("es-ES", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

function renderCard(item) {
  const card = createElement("article", "record-card");
  const content = createElement("div");
  const meta = createElement("div", "record-meta");
  meta.append(createElement("span", `status-pill is-${item.status}`, labels[item.status] || item.status));
  if (item.archivedAt) meta.append(createElement("span", "relation-chip", `Baja: ${formatDate(item.archivedAt)}`));
  content.append(
    createElement("h4", "", itemName(current, item)),
    createElement("p", "", descriptionFor(item)),
    meta,
    relationChips(item)
  );

  const buttons = createElement("div", "record-actions");
  for (const [kind, label] of [["edit","Editar"],["history","Histórico"]]) {
    const button = createElement("button", "secondary", label);
    button.type = "button";
    button.dataset.action = kind;
    button.dataset.id = item.id;
    buttons.append(button);
  }
  if (current === "occupancies" && item.tenantId) {
    const docs = createElement("button", "secondary", "Documentos");
    docs.type = "button"; docs.dataset.action = "documents"; docs.dataset.id = item.id; buttons.append(docs);
  }
  if (current === "properties") {
    const photos = createElement("button", "secondary", "Fotoverificaciones");
    photos.type = "button";
    photos.dataset.action = "photo-history";
    photos.dataset.id = item.id;
    buttons.append(photos);
  }
  if (item.status !== "archived") {
    const archive = createElement("button", "danger-soft", "Archivar");
    archive.type = "button";
    archive.dataset.action = "archive";
    archive.dataset.id = item.id;
    buttons.append(archive);
  }
  card.append(content, buttons);
  return card;
}

function render() {
  const view = views[current];
  const items = visibleItems();
  title.textContent = view.title;
  action.textContent = view.action;
  emptyTitle.textContent = view.emptyTitle;
  emptyText.textContent = view.emptyText;
  document.querySelectorAll(".segment").forEach(button => button.classList.toggle("is-active", button.dataset.view === current));
  records.replaceChildren(...items.map(renderCard));
  emptyState.hidden = items.length !== 0;
  renderSummary();
}

function relationOptions(type, selectedId) {
  return state[type].filter(item => item.status !== "archived" || item.id === selectedId);
}

function makeField(field, item) {
  const wrapper = createElement("label", "", field.label);
  let input;
  if (field.type === "relation") {
    input = document.createElement("select");
    const blank = document.createElement("option");
    blank.value = "";
    blank.textContent = "Selecciona una opción";
    input.append(blank);
    relationOptions(field.relation, item?.[field.key]).forEach(related => {
      const option = document.createElement("option");
      option.value = related.id;
      option.textContent = itemName(field.relation, related);
      input.append(option);
    });
  } else if (field.type === "select") {
    input = document.createElement("select");
    field.options.forEach(([value, label]) => {
      const option = document.createElement("option"); option.value = value; option.textContent = label; input.append(option);
    });
  } else if (field.type === "checkbox") {
    input = document.createElement("input"); input.type = "checkbox";
  } else if (field.type === "textarea") {
    input = document.createElement("textarea");
  } else {
    input = document.createElement("input");
    input.type = field.type;
    input.autocomplete = "off";
  }
  input.name = field.key;
  input.required = Boolean(field.required);
  if (field.type === "checkbox") input.checked = item ? !item.endsOn : true;
  else input.value = item?.[field.key] || "";
  wrapper.append(input);
  if (current === "occupancies" && field.key === "indefinite") {
    input.addEventListener("change", () => {
      const end = editorFields.querySelector('[name="endsOn"]');
      if (end) { end.disabled = input.checked; if (input.checked) end.value = ""; }
    });
    queueMicrotask(() => input.dispatchEvent(new Event("change")));
  }
  return wrapper;
}

function statusField(item) {
  const wrapper = createElement("label", "", "Estado");
  const select = document.createElement("select");
  select.name = "status";
  views[current].statuses.forEach(status => {
    const option = document.createElement("option");
    option.value = status;
    option.textContent = labels[status] || status;
    select.append(option);
  });
  select.value = item?.status || views[current].statuses[0];
  wrapper.append(select);
  return wrapper;
}

function openEditor(id = null) {
  const editorError = document.getElementById("editorError");
  if (editorError) { editorError.hidden = true; editorError.textContent = ""; }

  editingId = id;
  const view = views[current];
  const item = id ? findItem(current, id) : null;
  editorTitle.textContent = item ? `Editar ${view.singular}` : `Nuevo ${view.singular}`;
  editorFields.replaceChildren(...view.fields.map(field => makeField(field, item)), statusField(item));
  editorDialog.showModal();
}

function mapOwner(row) {
  return {
    id: row.id, fullName: row.full_name, email: row.email, phone: row.phone,
    status: row.status, archivedAt: row.archived_at
  };
}

function mapProperty(row) {
  return {
    id: row.id, ownerId: row.owner_id, name: row.name, address: row.address_line,
    city: row.city, postalCode: row.postal_code, status: row.status, archivedAt: row.archived_at
  };
}

function mapOccupancy(row) {
  return {
    id: row.id, tenantId: row.tenant_id, propertyId: row.property_id, roomId: row.room_id,
    fullName: row.tenants_v2?.full_name || row.occupant_email, documentType: row.tenants_v2?.document_type || "other",
    documentNumber: row.tenants_v2?.document_number || "", email: row.tenants_v2?.email || row.occupant_email,
    startsOn: row.starts_on, endsOn: row.ends_on, status: row.status, userId: row.user_id
  };
}

function mapRoom(row) {
  return {
    id: row.id, propertyId: row.property_id, label: row.label, description: row.description,
    status: row.status, archivedAt: row.archived_at
  };
}

async function loadPortfolio() {
  if (!organizationId) return;
  setStatus("Cargando datos autorizados…", "Supabase");

  const [ownersResult, propertiesResult] = await Promise.all([
    supabase.from("owners")
      .select("id,full_name,email,phone,status,archived_at")
      .eq("organization_id", organizationId)
      .order("created_at"),
    supabase.from("properties_v2")
      .select("id,owner_id,name,address_line,city,postal_code,status,archived_at")
      .eq("organization_id", organizationId)
      .order("created_at")
  ]);

  if (ownersResult.error) throw ownersResult.error;
  if (propertiesResult.error) throw propertiesResult.error;

  state.owners = ownersResult.data.map(mapOwner);
  state.properties = propertiesResult.data.map(mapProperty);

  if (state.properties.length) {
    const roomsResult = await supabase.from("rooms_v2")
      .select("id,property_id,label,description,status,archived_at")
      .in("property_id", state.properties.map(x => x.id))
      .order("created_at");
    if (roomsResult.error) throw roomsResult.error;
    state.rooms = roomsResult.data.map(mapRoom);
  } else {
    state.rooms = [];
  }

  const occupanciesResult = await supabase.from("occupancies_v2")
    .select("id,tenant_id,property_id,room_id,occupant_email,starts_on,ends_on,status,user_id,tenants_v2(full_name,document_type,document_number,email)")
    .eq("organization_id", organizationId)
    .order("starts_on", { ascending: false });
  if (occupanciesResult.error) throw occupanciesResult.error;
  state.occupancies = occupanciesResult.data.map(mapOccupancy).filter(item => item.tenantId);

  render();
  setStatus("Lectura y escritura protegidas por RLS. Las bajas son lógicas y los cambios quedan auditados.", "Sincronizado.");
}

function archivedAtFor(status, existing) {
  if (status === "archived") return existing?.archivedAt || new Date().toISOString();
  return null;
}

function friendlyWriteError(error, fallback) {
  if (error?.message === "tenant_email_identity_conflict") return "Ese email ya pertenece a otro inquilino con un documento diferente. Revisa la ficha existente antes de continuar.";
  if (error?.message === "tenant_orphan_identity_conflict") return "Ese email pertenece a una ficha existente sin ocupaciones, pero el documento no coincide. Revisa la identidad antes de reutilizarla.";

  const text = String(error?.message || error || "");
  if (text.includes("owner_has_active_properties")) {
    return "Archiva primero los pisos activos de este propietario.";
  }
  if (text.includes("property_has_active_rooms")) {
    return "Archiva primero las habitaciones activas de este piso.";
  }
  if (text.includes("row-level security") || error?.code === "42501") {
    return "Tu rol actual no tiene permiso para realizar este cambio.";
  }
  if (error?.code === "23505") {
    const detail = String(error?.details || "");
    if (detail.includes("email") || text.includes("tenants_v2_org_email_uidx")) return "Ya existe un inquilino con ese email en esta gestoría.";
    if (detail.includes("document") || text.includes("document")) return "Ya existe un inquilino con ese documento de identidad.";
    return "Ya existe un registro con esos datos.";
  }
  if (error?.code === "23503") return "El piso, la habitación o el inquilino seleccionado ya no existe o no está disponible. Actualiza la pantalla y vuelve a intentarlo.";
  if (error?.code === "23514") return "Alguno de los datos no cumple las reglas de la ficha. Revisa estado y fechas.";
  if (text.includes("room_property_mismatch")) return "La habitación seleccionada no pertenece al piso indicado.";
  if (text.includes("end_date_required")) return "Indica una fecha de salida o marca Indefinido.";
  if (current === "occupancies" && (error?.code || error?.message)) {
    const reference = error?.code ? ` (ref. ${error.code})` : "";
    return `No se pudo guardar el inquilino. ${String(error?.message || fallback)}${reference}`;
  }
  return fallback;
}

async function saveItem(event) {
  event.preventDefault();
  if (!editorForm.reportValidity()) return;

  saveButton.disabled = true;
  const data = Object.fromEntries(new FormData(editorForm).entries());
  const existing = editingId ? findItem(current, editingId) : null;
  const archivedAt = archivedAtFor(data.status, existing);
  const now = new Date().toISOString();
  let createdTenantId = null;

  try {
    if (current === "owners") {
      const payload = {
        organization_id: organizationId,
        full_name: data.fullName.trim(),
        email: data.email?.trim() || null,
        phone: data.phone?.trim() || null,
        status: data.status,
        archived_at: archivedAt
      };
      const query = existing
        ? supabase.from("owners").update({ ...payload, updated_at: now }).eq("id", existing.id)
        : supabase.from("owners").insert(payload);
      const { error } = await query;
      if (error) throw error;
    } else if (current === "properties") {
      const payload = {
        organization_id: organizationId,
        owner_id: data.ownerId,
        name: data.name.trim(),
        address_line: data.address.trim(),
        city: data.city?.trim() || null,
        postal_code: data.postalCode?.trim() || null,
        country_code: "ES",
        status: data.status,
        archived_at: archivedAt
      };
      const query = existing
        ? supabase.from("properties_v2").update({ ...payload, updated_at: now }).eq("id", existing.id)
        : supabase.from("properties_v2").insert(payload);
      const { error } = await query;
      if (error) throw error;
    } else if (current === "occupancies") {
      const room = findItem("rooms", data.roomId);
      if (!room || room.propertyId !== data.propertyId) throw new Error("room_property_mismatch");
      if (!data.indefinite && !data.endsOn) throw new Error("end_date_required");

      const tenantPayload = {
        organization_id: organizationId,
        full_name: data.fullName.trim(),
        document_type: data.documentType,
        document_number: data.documentNumber.trim().toUpperCase(),
        email: data.email.trim().toLowerCase(),
        status: data.status,
        archived_at: data.status === "archived" ? (existing?.archivedAt || now) : null
      };

      let tenantId = existing?.tenantId || null;
      if (tenantId) {
        const { error } = await supabase.from("tenants_v2").update(tenantPayload).eq("id", tenantId);
        if (error) throw error;
      } else {
        const normalizedEmail = tenantPayload.email;
        const { data: matches, error: lookupError } = await supabase.from("tenants_v2")
          .select("id,full_name,document_type,document_number,email,status")
          .eq("organization_id", organizationId)
          .ilike("email", normalizedEmail);
        if (lookupError) throw lookupError;
        const sameEmail = (matches || []).find(t => t.email.trim().toLowerCase() === normalizedEmail);
        if (sameEmail) {
          const { data: linkedOccupancies, error: linkedError } = await supabase.from("occupancies_v2")
            .select("id,status")
            .eq("organization_id", organizationId)
            .eq("tenant_id", sameEmail.id);
          if (linkedError) throw linkedError;
          const sameDocument = sameEmail.document_type === tenantPayload.document_type &&
            sameEmail.document_number.trim().toUpperCase() === tenantPayload.document_number;
          const isOrphan = !linkedOccupancies?.length;
          if (!sameDocument) {
            if (isOrphan) throw new Error("tenant_orphan_identity_conflict");
            throw new Error("tenant_email_identity_conflict");
          }
          const prompt = isOrphan
            ? `Este inquilino ya está registrado, pero no tiene ninguna ocupación. ¿Quieres utilizar la ficha de ${sameEmail.full_name} para asignarla a este piso y habitación?`
            : `Este email ya pertenece a ${sameEmail.full_name}. ¿Quieres reutilizar este inquilino para crear una nueva ocupación?`;
          if (!window.confirm(prompt)) return;
          tenantId = sameEmail.id;
        } else {
          const { data: tenant, error } = await supabase.from("tenants_v2").insert(tenantPayload).select("id").single();
          if (error) throw error;
          tenantId = tenant.id;
          createdTenantId = tenant.id;
        }
      }

      const payload = {
        organization_id: organizationId,
        tenant_id: tenantId,
        property_id: data.propertyId,
        room_id: data.roomId,
        occupant_email: tenantPayload.email,
        starts_on: data.startsOn,
        ends_on: data.indefinite ? null : data.endsOn,
        status: data.status
      };
      const query = existing
        ? supabase.from("occupancies_v2").update(payload).eq("id", existing.id)
        : supabase.from("occupancies_v2").insert(payload);
      const { error } = await query;
      if (error) {
        if (createdTenantId) {
          const rollback = await supabase.from("tenants_v2").delete().eq("id", createdTenantId);
          if (rollback.error) console.error("tenant rollback failed", rollback.error);
          createdTenantId = null;
        }
        throw error;
      }
    } else {
      const payload = {
        property_id: data.propertyId,
        label: data.label.trim(),
        description: data.description?.trim() || null,
        status: data.status,
        archived_at: archivedAt
      };
      const query = existing
        ? supabase.from("rooms_v2").update({ ...payload, updated_at: now }).eq("id", existing.id)
        : supabase.from("rooms_v2").insert(payload);
      const { error } = await query;
      if (error) throw error;
    }

    editorDialog.close();
    await loadPortfolio();
  } catch (error) {
    console.error("portfolio save failed", error);
    const message = friendlyWriteError(error, "No se pudo guardar el cambio.");
    saveErrorMessage.textContent = message;
    if (!saveErrorDialog.open) saveErrorDialog.showModal();
  } finally {
    saveButton.disabled = false;
  }
}

async function archiveItem(id) {
  const item = findItem(current, id);
  if (!item || item.status === "archived") return;

  if (current === "owners" && state.properties.some(x => x.ownerId === id && x.status !== "archived")) {
    setStatus("Archiva primero los pisos activos de este propietario.", "No se puede archivar.");
    return;
  }
  if (current === "properties" && state.rooms.some(x => x.propertyId === id && x.status !== "archived")) {
    setStatus("Archiva primero las habitaciones activas de este piso.", "No se puede archivar.");
    return;
  }

  const now = new Date().toISOString();

  try {
    let result;
    if (current === "owners") {
      result = await supabase.from("owners").update({ status: "archived", archived_at: now, updated_at: now }).eq("id", id);
    } else if (current === "properties") {
      result = await supabase.from("properties_v2").update({ status: "archived", archived_at: now, updated_at: now }).eq("id", id);
    } else if (current === "occupancies") {
      const nowIso = new Date().toISOString();
      result = await supabase.from("occupancies_v2").update({ status: "archived" }).eq("id", id);
      if (!result.error && item.tenantId) {
        const user = await getCurrentUser();
        const tenantUpdate = await supabase.from("tenants_v2").update({
          status:"archived", archived_at:nowIso, deletion_requested_at:nowIso, deletion_requested_by:user.id
        }).eq("id",item.tenantId);
        if (tenantUpdate.error) throw tenantUpdate.error;
      }
    } else {
      result = await supabase.from("rooms_v2").update({ status: "archived", archived_at: now, updated_at: now }).eq("id", id);
    }
    if (result.error) throw result.error;
    await loadPortfolio();
  } catch (error) {
    console.error("portfolio archive failed", error);
    setStatus(friendlyWriteError(error, "No se pudo tramitar la baja."), "Error.");
  }
}

async function showHistory(id) {
  const item = findItem(current, id);
  if (!item) return;
  historyTitle.textContent = itemName(current, item);
  historyList.replaceChildren(createElement("li", "", "Cargando histórico…"));
  historyDialog.showModal();

  const entityType = current === "owners" ? "owner" : current === "properties" ? "property" : current === "occupancies" ? "occupancy" : "room";
  const { data, error } = await supabase.from("audit_log_v2")
    .select("action,created_at")
    .eq("organization_id", organizationId)
    .eq("entity_type", entityType)
    .eq("entity_id", id)
    .order("created_at", { ascending: false });

  if (error) {
    historyList.replaceChildren(createElement("li", "", "No se pudo cargar el histórico."));
    return;
  }

  const entries = data.map(entry => {
    const row = document.createElement("li");
    row.append(
      createElement("strong", "", auditLabels[entry.action] || entry.action),
      createElement("time", "", formatDate(entry.created_at))
    );
    return row;
  });
  historyList.replaceChildren(...entries);
  if (!entries.length) historyList.append(createElement("li", "", "Sin cambios registrados."));
}

async function openDocuments(occupancyId) {
  const occupancy = findItem("occupancies", occupancyId);
  if (!occupancy?.tenantId) return;
  documentsTenantId = occupancy.tenantId;
  documentsTitle.textContent = `Documentos · ${occupancy.fullName || occupancy.email}`;
  documentsDialog.showModal();
  await loadDocuments();
}

async function loadDocuments() {
  documentsList.replaceChildren(createElement("li", "", "Cargando documentos…"));
  const { data, error } = await supabase.from("tenant_documents_v2")
    .select("id,document_type,display_name,storage_path,original_filename,created_at")
    .eq("tenant_id", documentsTenantId).order("created_at", { ascending: false });
  if (error) { documentsList.replaceChildren(createElement("li", "", "No se pudieron cargar los documentos.")); return; }
  const labels = {identification:"Identificación",contract:"Contrato",authorization:"Autorización",other:"Otro"};
  const rows = (data || []).map(doc => {
    const li = createElement("li", "document-row");
    const info = createElement("div");
    info.append(createElement("strong", "", doc.display_name), createElement("span", "muted small", `${labels[doc.document_type] || doc.document_type} · ${doc.original_filename}`));
    const actions = createElement("div", "record-actions");
    for (const [action,label] of [["open-document","Ver"],["delete-document","Eliminar"]]) {
      const btn=createElement("button", action==="delete-document"?"danger-soft":"secondary", label);
      btn.type="button"; btn.dataset.action=action; btn.dataset.documentId=doc.id; btn.dataset.path=doc.storage_path; actions.append(btn);
    }
    li.append(info,actions); return li;
  });
  documentsList.replaceChildren(...rows);
  if (!rows.length) documentsList.append(createElement("li", "", "Sin documentos adjuntos."));
}

async function uploadDocument(event) {
  event.preventDefault();
  const file=documentFile.files?.[0];
  if (!file || !documentsTenantId) return;
  const allowed=["application/pdf","image/jpeg","image/png","image/webp"];
  if (!allowed.includes(file.type) || file.size>10485760) { setStatus("El archivo debe ser PDF o imagen y no superar 10 MB.","Documento no válido."); return; }
  const user=await getCurrentUser();
  const ext=(file.name.split(".").pop() || "bin").replace(/[^a-z0-9]/gi,"").toLowerCase();
  const path=`${organizationId}/${documentsTenantId}/${crypto.randomUUID()}.${ext}`;
  const uploaded=await supabase.storage.from("tenant-documents-v2").upload(path,file,{contentType:file.type,upsert:false});
  if (uploaded.error) { setStatus("No se pudo subir el archivo.","Error."); return; }
  const inserted=await supabase.from("tenant_documents_v2").insert({
    organization_id:organizationId,tenant_id:documentsTenantId,document_type:documentType.value,
    display_name:documentName.value.trim(),storage_path:path,original_filename:file.name,mime_type:file.type,size_bytes:file.size,uploaded_by:user.id
  });
  if (inserted.error) { await supabase.storage.from("tenant-documents-v2").remove([path]); setStatus("No se pudo registrar el documento.","Error."); return; }
  documentForm.reset(); await loadDocuments();
}

async function documentAction(event) {
  const btn=event.target.closest("button[data-action]"); if(!btn) return;
  if(btn.dataset.action==="open-document"){
    const {data,error}=await supabase.storage.from("tenant-documents-v2").createSignedUrl(btn.dataset.path,60);
    if(error||!data?.signedUrl){setStatus("No se pudo abrir el documento.","Error.");return;}
    window.open(data.signedUrl,"_blank","noopener,noreferrer");
  }
  if(btn.dataset.action==="delete-document"){
    if(!window.confirm("¿Eliminar este documento? Esta acción elimina también el archivo privado.")) return;
    const removed=await supabase.storage.from("tenant-documents-v2").remove([btn.dataset.path]);
    if(removed.error){setStatus("No se pudo eliminar el archivo.","Error.");return;}
    const deleted=await supabase.from("tenant_documents_v2").delete().eq("id",btn.dataset.documentId);
    if(deleted.error){setStatus("El archivo se eliminó, pero no se pudo limpiar su registro. Requiere revisión.","Error.");return;}
    await loadDocuments();
  }
}

async function bootstrap() {
  try {
    const user = await getCurrentUser();
    role = user?.app_metadata?.role || null;
    if (!["root","admin"].includes(role)) {
      action.disabled = true;
      setStatus("Esta sección de gestión está reservada a ROOT/ADMIN.", "Acceso limitado.");
      return;
    }

    const { data: organizations, error } = await supabase
      .from("organizations")
      .select("id,name")
      .order("name");
    if (error) throw error;
    state.organizations = organizations || [];
    if (!state.organizations.length) throw new Error("no_organizations");

    organizationSelect.replaceChildren(...state.organizations.map(org => {
      const option = document.createElement("option");
      option.value = org.id;
      option.textContent = org.name;
      return option;
    }));

    const preferred = role === "admin" ? user.app_metadata?.organization_id : null;
    organizationId = state.organizations.find(x => x.id === preferred)?.id || state.organizations[0].id;
    organizationSelect.value = organizationId;
    organizationField.hidden = state.organizations.length <= 1;

    await loadPortfolio();
  } catch (error) {
    console.error("portfolio bootstrap failed", error);
    action.disabled = true;
    setStatus("No se pudo cargar la cartera autorizada.", "Error.");
  }
}

document.querySelectorAll(".segment").forEach(button => {
  button.addEventListener("click", () => {
    current = button.dataset.view;
    render();
  });
});

records.addEventListener("click", event => {
  const button = event.target.closest("button[data-action]");
  if (!button) return;
  if (button.dataset.action === "edit") openEditor(button.dataset.id);
  if (button.dataset.action === "archive") archiveItem(button.dataset.id);
  if (button.dataset.action === "history") showHistory(button.dataset.id);
  if (button.dataset.action === "documents") openDocuments(button.dataset.id);
  if (button.dataset.action === "photo-history") {
    const url = new URL("./photo-verifications.html", window.location.href);
    url.searchParams.set("property_id", button.dataset.id);
    url.searchParams.set("v", "2026091505");
    window.location.href = url.toString();
  }
});

action.addEventListener("click", () => openEditor());
statusFilter.addEventListener("change", render);
organizationSelect.addEventListener("change", async () => {
  organizationId = organizationSelect.value;
  await loadPortfolio();
});
editorForm.addEventListener("submit", saveItem);
$("closeEditorBtn").addEventListener("click", () => editorDialog.close());
$("cancelEditorBtn").addEventListener("click", () => editorDialog.close());
$("closeHistoryBtn").addEventListener("click", () => historyDialog.close());
$("closeDocumentsBtn").addEventListener("click", () => documentsDialog.close());
documentForm.addEventListener("submit", uploadDocument);
documentsList.addEventListener("click", documentAction);

bootstrap();

$("saveErrorAcceptBtn").addEventListener("click", () => saveErrorDialog.close());
$("saveErrorCancelBtn").addEventListener("click", () => { saveErrorDialog.close(); editorDialog.close(); });
