import { supabase } from "./supabase-client.js";

const form = document.getElementById("operatorActivationForm");
const password = document.getElementById("operatorNewPassword");
const confirmPassword = document.getElementById("operatorConfirmPassword");
const button = document.getElementById("operatorActivationButton");
const message = document.getElementById("operatorActivationMessage");
const checklist = document.getElementById("operatorPasswordChecklist");
const symbolPattern = /[!@#$%^&*()_+\-=\[\]{};'\\:"|<>?,.\/`~]/;

const hashParams = new URLSearchParams(window.location.hash.replace(/^#/, ""));
const queryParams = new URLSearchParams(window.location.search);
const activationHint =
  sessionStorage.getItem("allaiso-platform-operator-activation") === "1" ||
  hashParams.get("type") === "recovery" ||
  queryParams.get("type") === "recovery" ||
  queryParams.get("operator") === "1";

let activationReady = false;

function show(text, error = false) {
  message.textContent = text;
  message.classList.toggle("is-error", error);
}

function state() {
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

function valid() {
  return Object.values(state()).every(Boolean);
}

function renderChecklist() {
  const current = state();
  Object.entries(current).forEach(([rule, ok]) => {
    const item = checklist?.querySelector(`[data-password-rule="${rule}"]`);
    if (!item) return;
    item.classList.toggle("is-valid", ok);
    item.classList.toggle("is-invalid", rule === "match" && confirmPassword.value.length > 0 && !ok);
  });
  button.disabled = !activationReady || !valid();
}

function enable() {
  activationReady = true;
  password.disabled = false;
  confirmPassword.disabled = false;
  renderChecklist();
  show("Invitación verificada. Crea tu contraseña de operador.");
  password.focus();
}
async function enableVerifiedOperator() {
  try {
    const { data, error } = await supabase.functions.invoke("operator-mfa-recovery", {
      body: { action: "status" },
    });
    if (error || data?.ok !== true) {
      invalidate("El correo actual ya no coincide con la identidad de operador autorizada. Pide a ROOT que reprovisione el operador.");
      return;
    }
    sessionStorage.setItem("allaiso-platform-operator-activation", "1");
    enable();
  } catch {
    invalidate("No se pudo validar la identidad de operador. Pide a ROOT que revise o reprovisione el acceso.");
  }
}

function invalidate(text = "La invitación no es válida o ha caducado. Pide a ROOT que vuelva a designar el operador.") {
  activationReady = false;
  password.disabled = true;
  confirmPassword.disabled = true;
  button.disabled = true;
  sessionStorage.removeItem("allaiso-platform-operator-activation");
  show(text, true);
}

password.addEventListener("input", renderChecklist);
confirmPassword.addEventListener("input", renderChecklist);

const authError = hashParams.get("error_description") || queryParams.get("error_description");
if (authError) invalidate("La invitación ha caducado o ya fue utilizada. Pide a ROOT que la reenvíe.");

supabase.auth.onAuthStateChange((event, session) => {
  if (event === "PASSWORD_RECOVERY" && session) {
    enableVerifiedOperator();
  }
});

async function bootstrap() {
  if (authError) return;
  try {
    const { data, error } = await supabase.auth.getSession();
    if (error) throw error;
    if (data.session && activationHint) {
      await enableVerifiedOperator();
      return;
    }
    invalidate();
  } catch {
    invalidate("No se pudo validar la invitación. Comprueba la conexión o pide un nuevo enlace.");
  }
}

form.addEventListener("submit", async event => {
  event.preventDefault();
  if (!activationReady || !valid()) {
    show("La contraseña debe cumplir todos los requisitos indicados.", true);
    return;
  }

  button.disabled = true;
  password.disabled = true;
  confirmPassword.disabled = true;
  show("Activando cuenta de operador…");

  const { data: userData } = await supabase.auth.getUser();
  const email = String(userData?.user?.email || "");
  const { error } = await supabase.auth.updateUser({
    password: password.value,
    data: {
      platform_operator_invitation_pending: false,
      platform_operator_activated_at: new Date().toISOString(),
    },
  });

  if (error) {
    password.disabled = false;
    confirmPassword.disabled = false;
    renderChecklist();
    show("No se pudo guardar la contraseña. Revisa los requisitos o pide un enlace nuevo.", true);
    return;
  }

  sessionStorage.removeItem("allaiso-platform-operator-activation");
  if (email) sessionStorage.setItem("allaiso-platform-operator-email", email);
  await supabase.auth.signOut().catch(() => {});
  show("Cuenta activada. Abriendo la consola para registrar MFA…");
  setTimeout(() => window.location.replace("./operator-recovery.html?activated=1"), 900);
});

bootstrap();
