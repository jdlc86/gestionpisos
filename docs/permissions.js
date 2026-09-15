import { supabase, getCurrentSession } from "./supabase-client.js";

const $ = (id) => document.getElementById(id);
const esc = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const personName = (p) => p?.display_name || p?.email || "Usuario sin nombre";
const roles = (p) => Array.isArray(p?.roles) ? p.roles : [];
const card = (title, meta = "", badge = "") => `<article class="permission-item"><div><strong>${esc(title)}</strong>${meta ? `<span>${esc(meta)}</span>` : ""}</div>${badge ? `<em>${esc(badge)}</em>` : ""}</article>`;

async function load() {
  try {
    const session = await getCurrentSession();
    if (!session) return;
    const { data, error } = await supabase.rpc("get_permission_management_context", { p_organization_id: null });
    if (error) throw error;

    const people = data?.people || [];
    const byId = new Map(people.map((p) => [p.user_id, p]));
    const admins = people.filter((p) => roles(p).includes("admin"));
    const employees = people.filter((p) => roles(p).includes("employee"));
    const holders = data?.capability_holders || [];
    const requests = data?.pending_requests || [];
    const writeHolder = holders.find((h) => h.capability === "write_control");

    $("adminsList").innerHTML = admins.length ? admins.map((p) => card(personName(p), p.email, p.user_id === writeHolder?.holder_user_id ? "Control de escritura" : "Admin")).join("") : card("Sin administradores", "No hay administradores activos en esta organización.");
    $("employeesList").innerHTML = employees.length ? employees.map((p) => card(personName(p), p.email, "Empleado")).join("") : card("Sin empleados", "No hay empleados activos en esta organización.");
    $("propertiesList").innerHTML = (data?.properties || []).length ? data.properties.map((p) => {
      const responsible = byId.get(p.responsible_user_id);
      const where = [p.address_line, p.city].filter(Boolean).join(" · ");
      return card(p.name || "Vivienda", where, responsible ? `Responsable: ${personName(responsible)}` : "Sin responsable");
    }).join("") : card("Sin viviendas", "No hay viviendas activas en esta organización.");

    const capabilityRows = [];
    capabilityRows.push(writeHolder ? card("Control de escritura", personName(byId.get(writeHolder.holder_user_id)), "Titular actual") : card("Control de escritura", "No existe titular activo.", "Sin titular"));
    requests.filter((r) => r.capability === "write_control").forEach((r) => capabilityRows.push(card("Solicitud pendiente", personName(byId.get(r.requester_user_id)), "Pendiente")));
    $("capabilitiesList").innerHTML = capabilityRows.join("");

    $("permissionContent").hidden = false;
    $("permissionStatus").innerHTML = "<strong>Contexto cargado.</strong> Los datos proceden de la RPC autorizada.";
  } catch (error) {
    $("permissionError").textContent = error?.message === "not_authorized" ? "No tienes autorización para acceder a Gestión de Permisos." : "No se pudo cargar Gestión de Permisos. No se ha realizado ningún cambio.";
    $("permissionError").hidden = false;
    $("permissionStatus").innerHTML = "<strong>Acceso no disponible.</strong> La seguridad permanece aplicada en backend.";
  }
}
load();