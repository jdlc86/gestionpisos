import { supabase } from "./supabase-client.js";

const $ = (id) => document.getElementById(id);
const pending = new Map();
let contextOrganizationId = null;
let refreshTimer = null;

function closeModal() {
  const root = $("permissionModal");
  if (root) root.hidden = true;
  const confirm = $("permissionModalConfirm");
  if (confirm) confirm.onclick = null;
}

function showPageError(text) {
  const error = $("permissionError");
  if (!error) return;
  error.hidden = false;
  error.textContent = text;
}

function showStatus(title, text) {
  const status = $("permissionStatus");
  if (status) status.innerHTML = `<strong>${title}</strong> ${text}`;
}

async function loadPendingContext() {
  const { data: organizationId, error: organizationError } = await supabase.rpc("get_effective_organization_id");
  if (organizationError || !organizationId) return;
  const { data, error } = await supabase.rpc("get_permission_management_context", { p_organization_id: organizationId });
  if (error) return;
  contextOrganizationId = organizationId;
  pending.clear();
  for (const person of data?.people || []) {
    if (person?.onboarding_status === "pending") pending.set(person.user_id, person);
  }
  enhancePendingUi();
}

function removePendingOptions(select) {
  if (!select) return;
  [...select.options].forEach((option) => {
    if (pending.has(option.value)) option.remove();
  });
}

function enhancePendingUi() {
  document.querySelectorAll(".remove-staff").forEach((removeButton) => {
    const userId = removeButton.dataset.userId;
    const person = pending.get(userId);
    if (!person) return;
    const card = removeButton.closest(".permission-item");
    const actions = card?.querySelector(".staff-card-actions");
    const badge = actions?.querySelector("em");
    if (badge) badge.textContent = "Pendiente de activación";
    if (actions && !actions.querySelector(`.resend-staff-invitation[data-user-id="${userId}"]`)) {
      const invite = document.createElement("button");
      invite.type = "button";
      invite.className = "ghost resend-staff-invitation";
      invite.dataset.userId = userId;
      invite.textContent = Number(person.onboarding_invite_count || 0) > 0 ? "Reenviar invitación" : "Enviar invitación";
      actions.insertBefore(invite, removeButton);
    }
  });

  document.querySelectorAll('select[id^="responsible-"],select[id^="staff-"],#initialWriteControlAdmin,#rootWriteControlAdmin,#responsibilityReplacement').forEach(removePendingOptions);

  const initialSelect = $("initialWriteControlAdmin");
  const initialButton = $("assignInitialWriteControl");
  if (initialSelect && initialButton) initialButton.disabled = initialSelect.options.length === 0;
  const transferSelect = $("rootWriteControlAdmin");
  const transferButton = $("rootTransferWriteControl");
  if (transferSelect && transferButton) transferButton.disabled = transferSelect.options.length === 0;
}

function scheduleEnhance() {
  clearTimeout(refreshTimer);
  refreshTimer = setTimeout(enhancePendingUi, 20);
}

new MutationObserver(scheduleEnhance).observe(document.body, { childList: true, subtree: true });

// This listener is registered before permissions.js, so creation is owned here and
// cannot accidentally create an immediately-active identity through the legacy handler.
document.addEventListener("submit", (event) => {
  if (event.target?.id !== "createUserForm") return;
  event.preventDefault();
  event.stopImmediatePropagation();

  const name = $("newUserName")?.value.trim();
  const email = $("newUserEmail")?.value.trim();
  const role = $("newUserRole")?.value;
  if (!name || !email || !["employee", "admin"].includes(role)) return;

  $("permissionModalTitle").textContent = "Crear e invitar usuario";
  $("permissionModalText").textContent = `Se creará ${name} (${email}) como ${role === "admin" ? "administrador" : "empleado"}. No tendrá permisos activos hasta verificar su correo y crear su propia contraseña.`;
  const confirm = $("permissionModalConfirm");
  confirm.textContent = "Crear e invitar";
  confirm.disabled = false;
  confirm.onclick = async () => {
    if (confirm.disabled) return;
    confirm.disabled = true;
    confirm.textContent = "Creando…";
    const createButton = $("createUserButton");
    if (createButton) createButton.disabled = true;
    $("createUserNote").textContent = "Creando usuario pendiente de activación…";
    try {
      const { data, error } = await supabase.functions.invoke("create-organization-user", {
        body: { display_name: name, email, role },
      });
      if (error) throw error;
      $("createUserForm").reset();
      closeModal();
      if (data?.invitation_status === "sent") {
        $("createUserNote").textContent = "Usuario creado. Invitación enviada correctamente.";
        showStatus("Usuario pendiente de activación.", "La invitación fue enviada por el proveedor profesional de correo.");
      } else if (data?.invitation_status === "not_configured") {
        $("createUserNote").textContent = "Usuario creado pendiente de activación. Falta configurar el correo profesional para enviar la invitación.";
        showStatus("Usuario creado de forma segura.", "No tiene permisos activos hasta completar la activación.");
      } else {
        $("createUserNote").textContent = "Usuario creado pendiente de activación. La invitación no pudo enviarse; puedes reenviarla desde su ficha.";
        showStatus("Usuario creado de forma segura.", "No tiene permisos activos hasta completar la activación.");
      }
      await loadPendingContext();
      setTimeout(() => window.location.reload(), 700);
    } catch (error) {
      confirm.disabled = false;
      confirm.textContent = "Crear e invitar";
      $("createUserNote").textContent = "No se pudo crear el usuario.";
      showPageError(String(error?.message || "No se pudo crear el usuario.").slice(0, 180));
    } finally {
      if (createButton) createButton.disabled = false;
    }
  };
  $("permissionModal").hidden = false;
}, true);

document.addEventListener("click", async (event) => {
  const button = event.target.closest(".resend-staff-invitation");
  if (!button) return;
  event.preventDefault();
  event.stopImmediatePropagation();

  const userId = button.dataset.userId;
  const person = pending.get(userId);
  if (!person) return;
  button.disabled = true;
  const previous = button.textContent;
  button.textContent = "Enviando…";
  showStatus("Enviando invitación…", "Espera un momento.");

  try {
    const { data, error } = await supabase.functions.invoke("resend-staff-invitation", {
      body: { target_user_id: userId },
    });
    if (error) throw error;
    if (data?.invitation_status === "sent") {
      showStatus("Invitación enviada.", `${person.display_name || person.email} puede activar su cuenta desde el correo recibido.`);
    } else if (data?.invitation_status === "not_configured") {
      showPageError("El flujo de onboarding está preparado, pero todavía falta configurar el proveedor profesional de correo (Resend) en Supabase.");
      showStatus("Invitación pendiente.", "El usuario continúa sin permisos activos.");
    } else {
      showPageError("No se pudo entregar la invitación. El usuario continúa pendiente y sin permisos activos.");
      showStatus("Invitación no enviada.", "Puedes volver a intentarlo cuando el proveedor de correo esté disponible.");
    }
    await loadPendingContext();
  } catch (error) {
    const text = String(error?.message || "").toLowerCase();
    if (text.includes("429") || text.includes("cooldown")) {
      showPageError("La invitación se acaba de solicitar. Espera aproximadamente un minuto antes de reenviarla.");
    } else {
      showPageError("No se pudo reenviar la invitación. El usuario continúa pendiente y sin permisos activos.");
    }
  } finally {
    button.disabled = false;
    button.textContent = previous;
  }
}, true);

document.querySelectorAll("[data-modal-close]").forEach((element) => element.addEventListener("click", closeModal));
loadPendingContext();
