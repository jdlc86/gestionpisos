import { supabase } from "./supabase-client.js";

const form = document.getElementById("resetForm");
const password = document.getElementById("newPassword");
const confirmPassword = document.getElementById("confirmPassword");
const button = document.getElementById("resetBtn");
const backToLogin = document.getElementById("backToLogin");
const message = document.getElementById("authMessage");
const passwordChecklist = document.getElementById("passwordChecklist");
const symbolPattern = /[!@#$%^&*()_+\-=\[\]{};'\\:"|<>?,.\/`~]/;

const hashParams = new URLSearchParams(window.location.hash.replace(/^#/, ""));
const queryParams = new URLSearchParams(window.location.search);
const recoveryHint =
  sessionStorage.getItem("allaiso-password-recovery") === "1" ||
  hashParams.get("type") === "recovery" ||
  queryParams.get("type") === "recovery";

let recoveryReady = false;

function show(text, error = false) {
  message.textContent = text;
  message.classList.toggle("is-error", error);
}

function passwordPolicyState() {
  const value = password.value;
  return {
    length: value.length >= 12,
    lowercase: /[a-z]/.test(value),
    uppercase: /[A-Z]/.test(value),
    digit: /[0-9]/.test(value),
    symbol: symbolPattern.test(value),
    match: confirmPassword.value.length > 0 && value === confirmPassword.value,
  };
}

function passwordPolicyValid() {
  return Object.values(passwordPolicyState()).every(Boolean);
}

function updatePasswordChecklist() {
  const state = passwordPolicyState();
  Object.entries(state).forEach(([rule, valid]) => {
    const item = passwordChecklist?.querySelector(`[data-password-rule="${rule}"]`);
    if (!item) return;
    item.classList.toggle("is-valid", valid);
    item.classList.toggle("is-invalid", rule === "match" && confirmPassword.value.length > 0 && !valid);
  });
  button.disabled = !recoveryReady || !passwordPolicyValid();
}

function enableRecoveryForm() {
  recoveryReady = true;
  password.disabled = false;
  confirmPassword.disabled = false;
  updatePasswordChecklist();
  show("Enlace verificado. Introduce tu nueva contraseña.");
  password.focus();
}

function invalidateRecovery(text = "El enlace de recuperación no es válido o ha caducado. Solicita uno nuevo desde la pantalla de acceso.") {
  recoveryReady = false;
  password.disabled = true;
  confirmPassword.disabled = true;
  button.disabled = true;
  sessionStorage.removeItem("allaiso-password-recovery");
  show(text, true);
}

password.addEventListener("input", updatePasswordChecklist);
confirmPassword.addEventListener("input", updatePasswordChecklist);

const authError = hashParams.get("error_description") || queryParams.get("error_description");
if (authError) {
  invalidateRecovery("El enlace de recuperación ha caducado o ya fue utilizado. Solicita uno nuevo.");
}

supabase.auth.onAuthStateChange((event, session) => {
  if (event === "PASSWORD_RECOVERY" && session) {
    sessionStorage.setItem("allaiso-password-recovery", "1");
    enableRecoveryForm();
  }
});

async function bootstrapRecovery() {
  if (authError) return;

  try {
    const { data, error } = await supabase.auth.getSession();
    if (error) throw error;

    if (data.session && recoveryHint) {
      enableRecoveryForm();
      return;
    }

    invalidateRecovery();
  } catch {
    invalidateRecovery("No se pudo validar el enlace de recuperación. Comprueba tu conexión o solicita un enlace nuevo.");
  }
}

backToLogin.addEventListener("click", async () => {
  sessionStorage.removeItem("allaiso-password-recovery");
  await supabase.auth.signOut({ scope: "local" }).catch(() => {});
  window.location.replace("./login.html");
});

form.addEventListener("submit", async event => {
  event.preventDefault();
  if (!recoveryReady) {
    invalidateRecovery();
    return;
  }

  const policy = passwordPolicyState();
  if (!policy.match) {
    show("Las dos contraseñas no coinciden.", true);
    confirmPassword.focus();
    updatePasswordChecklist();
    return;
  }
  if (!passwordPolicyValid()) {
    show("La contraseña debe cumplir todos los requisitos indicados.", true);
    password.focus();
    updatePasswordChecklist();
    return;
  }

  button.disabled = true;
  password.disabled = true;
  confirmPassword.disabled = true;
  show("Actualizando contraseña…");

  const { error } = await supabase.auth.updateUser({ password: password.value });

  if (error) {
    password.disabled = false;
    confirmPassword.disabled = false;
    updatePasswordChecklist();
    show("No se pudo actualizar la contraseña. Comprueba que cumpla todos los requisitos o solicita un enlace nuevo.", true);
    return;
  }

  sessionStorage.removeItem("allaiso-password-recovery");
  const { error: signOutError } = await supabase.auth.signOut();
  if (signOutError) await supabase.auth.signOut({ scope: "local" }).catch(() => {});

  show("Contraseña actualizada. Redirigiendo al acceso…");
  setTimeout(() => window.location.replace("./login.html?password=updated"), 900);
});

bootstrapRecovery();
