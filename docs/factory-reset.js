import { supabase } from "./supabase-client.js";

const previewBtn = document.getElementById("previewResetBtn");
const executeBtn = document.getElementById("executeResetBtn");
const previewPanel = document.getElementById("previewPanel");
const summary = document.getElementById("resetSummary");
const testDataConfirm = document.getElementById("testDataConfirm");
const resetPhrase = document.getElementById("resetPhrase");
const message = document.getElementById("resetMessage");
const backBtn = document.getElementById("backBtn");

let previewToken = "";
let previewExpiresAt = 0;

function show(text, error = false) {
  message.textContent = text || "";
  message.classList.toggle("is-error", error);
}

function resetConfirmationState() {
  const phraseOk = resetPhrase.value.trim().toUpperCase() === "RESTABLECER";
  const tokenOk = previewToken && Date.now() < previewExpiresAt;
  executeBtn.disabled = !(testDataConfirm.checked && phraseOk && tokenOk);
}

async function invokeFactoryReset(body) {
  const { data, error } = await supabase.functions.invoke("factory-reset-test-data", { body });
  if (error) {
    const detail = data?.error || error?.context?.body?.error || error.message || "factory_reset_request_failed";
    throw new Error(String(detail));
  }
  if (data?.error) throw new Error(String(data.error));
  return data;
}

function errorMessage(code) {
  const map = {
    root_required: "Solo ROOT puede utilizar este restablecimiento.",
    aal2_required: "Vuelve a iniciar sesión como ROOT y completa MFA antes de continuar.",
    factory_reset_requires_one_root_recovery_operator: "Debe existir exactamente un operador técnico activo capaz de recuperar ROOT.",
    factory_reset_operator_mfa_required: "El operador técnico preservado debe tener MFA verificado.",
    factory_reset_preview_expired: "La vista previa ha caducado. Prepárala de nuevo.",
    factory_reset_baseline_changed: "El baseline protegido cambió. Prepara una nueva vista previa.",
    factory_reset_storage_failed: "No se pudo vaciar Storage. No se continuó con el borrado de base de datos.",
    factory_reset_database_failed: "Storage se vació, pero la limpieza de base de datos falló. No repitas acciones manuales; vuelve a preparar el reset.",
    factory_reset_auth_cleanup_partial: "La base de datos ya se restableció, pero quedó una limpieza parcial de usuarios Auth. Repite el helper para completar la postcondición.",
  };
  return map[code] || `No se pudo completar el restablecimiento (${code}).`;
}

previewBtn.addEventListener("click", async () => {
  previewBtn.disabled = true;
  previewToken = "";
  previewPanel.hidden = true;
  show("Preparando vista previa segura…");
  try {
    const data = await invokeFactoryReset({ action: "preview" });
    previewToken = String(data.preview_token || "");
    previewExpiresAt = new Date(data.preview_expires_at || 0).getTime();
    const protectedUsers = Array.isArray(data.protected_users) ? data.protected_users : [];
    const root = protectedUsers.find(item => item.kind === "root");
    const operator = protectedUsers.find(item => item.kind === "platform_operator");
    const buckets = Array.isArray(data.storage_buckets_to_empty) ? data.storage_buckets_to_empty : [];

    summary.replaceChildren();
    const lines = [
      `ROOT protegido: ${root?.email || "—"}`,
      `Operador técnico protegido: ${operator?.email || "—"}`,
      `Usuarios Auth que se eliminarán: ${Number(data.auth_users_to_delete || 0)}`,
      `Storage a vaciar: ${buckets.length ? buckets.join(", ") : "sin objetos/buckets operativos"}`,
      "Se eliminará la auditoría histórica de pruebas y quedará un único recibo factory_reset_completed.",
      "Las plantillas estructurales se conservan.",
    ];
    lines.forEach(text => {
      const div = document.createElement("div");
      div.textContent = text;
      summary.append(div);
    });

    previewPanel.hidden = false;
    testDataConfirm.checked = false;
    resetPhrase.value = "";
    resetConfirmationState();
    show("Vista previa preparada. Caduca en 5 minutos.");
  } catch (error) {
    console.error("factory_reset_preview_failed", error);
    show(errorMessage(error.message), true);
  } finally {
    previewBtn.disabled = false;
  }
});

testDataConfirm.addEventListener("change", resetConfirmationState);
resetPhrase.addEventListener("input", resetConfirmationState);

executeBtn.addEventListener("click", async () => {
  resetConfirmationState();
  if (executeBtn.disabled) return;
  if (!window.confirm("Esta operación eliminará de forma irreversible todos los datos operativos de prueba y dejará únicamente ROOT y el operador técnico. ¿Continuar?")) return;

  executeBtn.disabled = true;
  previewBtn.disabled = true;
  show("Restableciendo entorno de pruebas… No cierres esta pantalla.");
  try {
    const data = await invokeFactoryReset({
      action: "execute",
      confirmation: "RESET_FACTORY_TEST_DATA",
      preview_token: previewToken,
    });
    previewToken = "";
    previewExpiresAt = 0;
    previewPanel.hidden = true;
    show(`Restablecimiento completado. Usuarios Auth restantes: ${Number(data.remaining_auth_user_count || 0)}.`);
  } catch (error) {
    console.error("factory_reset_execute_failed", error);
    show(errorMessage(error.message), true);
  } finally {
    previewBtn.disabled = false;
  }
});

backBtn.addEventListener("click", () => {
  window.location.href = "./permissions.html";
});

(async function bootstrap() {
  try {
    const { data, error } = await supabase.auth.getSession();
    if (error) throw error;
    if (!data.session) {
      previewBtn.disabled = true;
      show("Inicia sesión como ROOT antes de abrir esta herramienta.", true);
      return;
    }
    show("Preparado. El backend volverá a validar ROOT y MFA antes de cualquier acción.");
  } catch (error) {
    console.error("factory_reset_bootstrap_failed", error);
    previewBtn.disabled = true;
    show("No se pudo validar la sesión actual.", true);
  }
})();
