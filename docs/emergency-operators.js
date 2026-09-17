import { supabase, getCurrentSession } from "./supabase-client.js";

const panel = document.getElementById("emergencyOperatorsPanel");
const form = document.getElementById("emergencyOperatorForm");
const emailInput = document.getElementById("emergencyOperatorEmail");
const nameInput = document.getElementById("emergencyOperatorName");
const rootCapabilityInput = document.getElementById("emergencyOperatorCanRecoverRoot");
const list = document.getElementById("emergencyOperatorsList");
const status = document.getElementById("emergencyOperatorsStatus");
const warning = document.getElementById("emergencyOperatorsWarning");
const addButton = document.getElementById("emergencyOperatorAddButton");

let busy = false;
let operators = [];

function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, char => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[char]));
}

function setStatus(text, error = false) {
  if (!status) return;
  status.textContent = text || "";
  status.classList.toggle("is-error", error);
}

function messageFor(error) {
  const code = String(error?.message || error || "");
  const messages = {
    root_required: "Solo ROOT puede gestionar operadores de emergencia.",
    aal2_required: "Confirma primero tu MFA de ROOT para modificar esta configuración.",
    auth_user_not_found: "No existe una cuenta Auth con ese correo.",
    operator_auth_identity_prepare_failed: "No se pudo preparar la identidad técnica del operador. Inténtalo de nuevo.",
    operator_email_not_confirmed: "La cuenta todavía no tiene el correo confirmado.",
    self_operator_forbidden: "La cuenta ROOT actual no puede designarse a sí misma como operador de emergencia.",
    dedicated_platform_identity_required: "Esa cuenta ya tiene un rol operativo en GestionPisos. Usa una identidad técnica independiente.",
    display_name_required: "Indica un nombre para identificar al operador.",
    valid_email_required: "Introduce un correo válido.",
    audit_failed: "El cambio no se confirmó porque no pudo registrarse correctamente en auditoría.",
    operator_mutation_failed: "No se pudo guardar la autorización del operador. La configuración anterior se mantiene.",
  };
  return messages[code] || "No se pudo guardar el cambio. La configuración anterior se mantiene.";
}

async function errorDetail(error, data) {
  if (data?.error) return String(data.error);
  const context = error?.context;
  if (context && typeof context.clone === "function") {
    try {
      const payload = await context.clone().json();
      if (payload?.error) return String(payload.error);
    } catch {}
  }
  return String(error?.message || "operator_management_failed");
}

async function invoke(action, extra = {}) {
  const { data, error } = await supabase.functions.invoke("manage-platform-operators", {
    body: { action, ...extra },
  });
  if (error) throw new Error(await errorDetail(error, data));
  if (data?.error) throw new Error(String(data.error));
  return data;
}

function operatorCard(operator) {
  const article = document.createElement("article");
  article.className = "permission-item emergency-operator-item";
  const state = operator.active ? "Activo" : "Inactivo";
  const rootCapability = operator.can_recover_root ? "Puede recuperar ROOT" : "Sin permiso ROOT";
  const mfa = operator.mfa_ready === true
    ? "MFA listo"
    : operator.invitation_pending === true
      ? "Activación pendiente"
      : operator.mfa_ready === false
        ? "MFA pendiente"
        : "MFA sin confirmar";

  article.innerHTML = `
    <div class="emergency-operator-main">
      <strong>${esc(operator.display_name || "Operador")}</strong>
      <span>${esc(operator.email || "Cuenta Auth no disponible")}</span>
      <div class="emergency-operator-badges">
        <em>${esc(state)}</em>
        <em>${esc(rootCapability)}</em>
        <em>${esc(mfa)}</em>
      </div>
    </div>
    <div class="staff-card-actions emergency-operator-actions">
      <button class="ghost emergency-toggle-active" type="button">${operator.active ? "Desactivar" : "Activar"}</button>
      <button class="ghost emergency-toggle-root" type="button">${operator.can_recover_root ? "Retirar permiso ROOT" : "Permitir recuperar ROOT"}</button>
    </div>
  `;

  article.querySelector(".emergency-toggle-active")?.addEventListener("click", async () => {
    const nextActive = !operator.active;
    const prompt = nextActive
      ? `¿Activar a ${operator.display_name} como operador de emergencia?`
      : `¿Desactivar a ${operator.display_name}? Ya no podrá gestionar recuperaciones mientras esté inactivo.`;
    if (!window.confirm(prompt)) return;
    await updateOperator(operator, { active: nextActive });
  });

  article.querySelector(".emergency-toggle-root")?.addEventListener("click", async () => {
    const nextCapability = !operator.can_recover_root;
    const prompt = nextCapability
      ? `¿Permitir que ${operator.display_name} pueda aprobar recuperaciones de ROOT?`
      : `¿Retirar a ${operator.display_name} el permiso para recuperar ROOT?`;
    if (!window.confirm(prompt)) return;
    await updateOperator(operator, { can_recover_root: nextCapability });
  });

  return article;
}

function render(data) {
  operators = Array.isArray(data?.operators) ? data.operators : [];
  list?.replaceChildren();

  if (!operators.length) {
    const empty = document.createElement("div");
    empty.className = "operator-empty";
    empty.textContent = "No hay operadores de emergencia configurados.";
    list?.append(empty);
  } else {
    operators.forEach(operator => list?.append(operatorCard(operator)));
  }

  const count = Number(data?.active_root_recovery_count || 0);
  if (warning) {
    warning.hidden = count > 0;
    warning.textContent = count > 0
      ? ""
      : "Todavía no existe ningún operador activo con MFA listo y permiso para recuperar ROOT. La protección quedará completa cuando al menos uno termine su activación y registre MFA.";
  }
  setStatus(count > 0
    ? `${count} operador${count === 1 ? "" : "es"} activo${count === 1 ? "" : "s"} y con MFA puede${count === 1 ? "" : "n"} recuperar ROOT.`
    : "Configura al menos un operador independiente y completa su activación MFA.");
}

async function loadOperators() {
  if (busy) return;
  busy = true;
  setStatus("Consultando operadores autorizados…");
  try {
    const data = await invoke("list");
    render(data);
  } catch (error) {
    setStatus(messageFor(error), true);
  } finally {
    busy = false;
  }
}

async function updateOperator(operator, patch) {
  if (busy) return;
  busy = true;
  setStatus("Guardando configuración de seguridad…");
  try {
    await invoke("update", {
      target_user_id: operator.user_id,
      ...patch,
    });
    const data = await invoke("list");
    render(data);
  } catch (error) {
    setStatus(messageFor(error), true);
  } finally {
    busy = false;
  }
}

form?.addEventListener("submit", async event => {
  event.preventDefault();
  if (busy) return;
  const email = emailInput?.value.trim() || "";
  const displayName = nameInput?.value.trim() || "";
  const canRecoverRoot = rootCapabilityInput?.checked !== false;
  if (!email || !displayName) {
    setStatus("Completa el correo y el nombre del operador.", true);
    return;
  }
  if (!window.confirm(`¿Designar ${displayName} (${email}) como operador de emergencia${canRecoverRoot ? " con permiso para recuperar ROOT" : ""}?`)) return;

  busy = true;
  if (addButton) addButton.disabled = true;
  setStatus("Autorizando operador…");
  try {
    const result = await invoke("add", {
      email,
      display_name: displayName,
      can_recover_root: canRecoverRoot,
    });
    form.reset();
    if (rootCapabilityInput) rootCapabilityInput.checked = true;
    const data = await invoke("list");
    render(data);
    if (result?.invitation_status === "sent") {
      setStatus("Operador configurado. Se ha enviado un correo para crear su contraseña; después deberá registrar MFA.");
    } else if (result?.invitation_status === "failed") {
      setStatus("Operador configurado, pero el correo de activación no pudo enviarse. Vuelve a designar el mismo correo para reintentar el envío.", true);
    } else if (result?.invitation_status === "not_configured") {
      setStatus("Operador configurado, pero el servicio profesional de correo no está disponible. No se considera listo para recuperación.", true);
    } else {
      setStatus("Operador configurado. Debe entrar en la consola independiente y completar MFA antes de quedar listo.");
    }
  } catch (error) {
    setStatus(messageFor(error), true);
  } finally {
    busy = false;
    if (addButton) addButton.disabled = false;
  }
});

(async function bootstrapEmergencyOperators() {
  if (!panel) return;
  try {
    const session = await getCurrentSession();
    const role = String(session?.user?.app_metadata?.role || "").toLowerCase();
    if (role !== "root") {
      panel.hidden = true;
      return;
    }
    panel.hidden = false;
    await loadOperators();
  } catch (error) {
    panel.hidden = false;
    setStatus(messageFor(error), true);
  }
})();
