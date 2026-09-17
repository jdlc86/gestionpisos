import { supabase, getCurrentSession } from "./supabase-client.js";

const $ = (id) => document.getElementById(id);

function fmtBytes(value) {
  const n = Number(value || 0);
  if (!Number.isFinite(n)) return "—";
  if (n >= 1073741824) return `${(n / 1073741824).toFixed(2)} GB`;
  if (n >= 1048576) return `${(n / 1048576).toFixed(1)} MB`;
  if (n >= 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${Math.round(n)} B`;
}

function fmtCount(value) {
  const n = Number(value || 0);
  return Number.isFinite(n) ? new Intl.NumberFormat("es-ES").format(n) : "—";
}

function fmtDate(value) {
  if (!value) return "Sin restablecimientos registrados";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : date.toLocaleString("es-ES");
}

async function invokeOverview() {
  const { data, error } = await supabase.functions.invoke("root-configuration-resources", { body: {} });
  if (error) {
    let detail = data?.error || "";
    const response = error?.context;
    if (!detail && response && typeof response.clone === "function") {
      try {
        const payload = await response.clone().json();
        detail = payload?.error || "";
      } catch {
        // SDK error is the final fallback.
      }
    }
    throw new Error(detail || error.message || "configuration_resources_unavailable");
  }
  if (data?.error) throw new Error(String(data.error));
  return data;
}

function friendlyError(code) {
  const messages = {
    root_required: "Esta configuración global solo está disponible para ROOT.",
    aal2_required: "Completa MFA como ROOT antes de abrir Configuración y Recursos.",
    root_organization_required: "No se pudo resolver la organización activa de ROOT.",
    root_organization_lookup_failed: "No se pudo consultar la organización activa.",
    configuration_resources_unavailable: "No se pudo cargar el estado técnico del sistema."
  };
  return messages[code] || code || "No se pudo cargar Configuración y Recursos.";
}

function renderInventory(inventory = {}) {
  const values = {
    inventoryProperties: inventory.properties,
    inventoryRooms: inventory.rooms,
    inventoryOwners: inventory.owners,
    inventoryTenants: inventory.tenants,
    inventoryOccupancies: inventory.occupancies,
    inventoryIncidents: inventory.incidents,
    inventoryCleaning: inventory.cleaning_tasks,
    inventoryPhotoRuns: inventory.photo_verification_runs,
    inventoryDocuments: inventory.tenant_documents,
    inventoryNotifications: inventory.notifications,
  };
  for (const [id, value] of Object.entries(values)) {
    if ($(id)) $(id).textContent = fmtCount(value);
  }
}

function render(data) {
  const overview = data?.overview || {};
  const organization = overview.organization || {};
  const database = overview.database || {};
  const storage = overview.storage || {};
  const security = overview.security || {};

  $("organizationName").textContent = organization.name || "—";
  $("organizationStatus").textContent = organization.status === "active" ? "ACTIVA" : String(organization.status || "—").toUpperCase();
  $("databaseMetric").textContent = fmtBytes(database.used_bytes);
  $("storageMetric").textContent = fmtBytes(storage.used_bytes);
  $("storageDetail").textContent = `${fmtCount(storage.objects)} archivos en buckets de GestionPisos`;
  $("authMetric").textContent = fmtCount(data?.auth?.users);
  $("recoveryMetric").textContent = fmtCount(security.root_recovery_operator_count);
  $("recoveryDetail").textContent = Number(security.root_recovery_operator_count) === 1
    ? "Operador técnico preparado para recuperación de ROOT"
    : "Revisar operadores técnicos de emergencia";
  $("emailDeliveryStatus").textContent = data?.email_delivery?.transactional_provider_configured ? "CONFIGURADO" : "REVISAR";
  $("emailDeliveryStatus").className = `status-pill ${data?.email_delivery?.transactional_provider_configured ? "ok" : "warning"}`;
  $("mfaStatus").textContent = data?.auth?.root_aal2 ? "MFA ACTIVO" : "REVISAR";
  $("lastReset").textContent = fmtDate(security.latest_factory_reset_at);
  $("generatedAt").textContent = data?.generated_at ? `Última lectura: ${fmtDate(data.generated_at)}` : "";
  renderInventory(overview.inventory || {});
}

async function boot() {
  const state = $("configurationResourcesState");
  try {
    const session = await getCurrentSession();
    if (!session) return;
    if (String(session.user?.app_metadata?.role || "").toLowerCase() !== "root") {
      state.textContent = friendlyError("root_required");
      return;
    }
    const data = await invokeOverview();
    render(data);
    state.textContent = "Estado actualizado. Los datos de esta pantalla son de solo lectura; las acciones sensibles conservan sus propias confirmaciones.";
  } catch (error) {
    state.textContent = friendlyError(String(error?.message || error));
  }
}

$("refreshResources")?.addEventListener("click", async () => {
  const button = $("refreshResources");
  const state = $("configurationResourcesState");
  button.disabled = true;
  button.textContent = "Actualizando…";
  try {
    const data = await invokeOverview();
    render(data);
    state.textContent = "Estado actualizado correctamente.";
  } catch (error) {
    state.textContent = friendlyError(String(error?.message || error));
  } finally {
    button.disabled = false;
    button.textContent = "↻ Actualizar";
  }
});

boot();
