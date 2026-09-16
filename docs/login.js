import { supabase, getCurrentSession } from "./supabase-client.js?v=2026091603";

window.__loginModuleReady = true;
window.__loginModuleFailureHandled = false;
sessionStorage.removeItem("allaiso-login-module-recovery-v2");

const form = document.getElementById("loginForm");
const email = document.getElementById("email");
const password = document.getElementById("password");
const loginBtn = document.getElementById("loginBtn");
const forgotBtn = document.getElementById("forgotBtn");
const message = document.getElementById("authMessage");
let loginInProgress = false;

function targetPage() {
  const params = new URLSearchParams(window.location.search);
  const next = params.get("next");
  if (!next || next.includes("://") || next.startsWith("//") || next.includes("..")) return "./";
  return "./" + next.replace(/^\.\//, "");
}

function show(text, error = false) {
  message.textContent = text;
  message.classList.toggle("is-error", error);
}

function recoveryRedirectUrl() {
  return new URL("./reset-password.html", window.location.origin + window.location.pathname).href;
}

function isRateLimitError(error) {
  const status = Number(error?.status || 0);
  const text = String(error?.message || "").toLowerCase();
  return status === 429 || text.includes("rate limit") || text.includes("too many");
}

function withTimeout(promise, milliseconds, code) {
  let timeoutId;
  const timeout = new Promise((_, reject) => {
    timeoutId = setTimeout(() => reject(new Error(code)), milliseconds);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timeoutId));
}

const params = new URLSearchParams(window.location.search);
if (params.get("password") === "updated") {
  show("Contraseña actualizada. Ya puedes iniciar sesión.");
} else if (params.get("activated") === "1") {
  show("Cuenta activada. Ya puedes iniciar sesión.");
}

// Register interactive handlers before checking any existing session. A stale or
// slow auth initialization must never leave the login form inert.
form.addEventListener("submit", async event => {
  event.preventDefault();
  if (loginBtn.disabled) return;

  loginInProgress = true;
  loginBtn.disabled = true;
  show("Comprobando acceso…");

  try {
    const { error } = await withTimeout(
      supabase.auth.signInWithPassword({
        email: email.value.trim().toLowerCase(),
        password: password.value
      }),
      12000,
      "login_timeout"
    );

    if (error) {
      show("No se pudo iniciar sesión. Comprueba el email y la contraseña.", true);
      return;
    }

    window.location.replace(targetPage());
  } catch (error) {
    console.error("login_request_failed", error);
    if (String(error?.message || "") === "login_timeout") {
      show("El servicio de acceso no respondió a tiempo. Cierra GestionPisos, vuelve a abrirlo e inténtalo otra vez.", true);
    } else {
      show("No se pudo contactar con el servicio de acceso. Comprueba tu conexión e inténtalo de nuevo.", true);
    }
  } finally {
    loginInProgress = false;
    loginBtn.disabled = false;
  }
});

forgotBtn.addEventListener("click", async () => {
  const value = email.value.trim().toLowerCase();
  if (!value) {
    show("Introduce primero tu email.", true);
    email.focus();
    return;
  }

  forgotBtn.disabled = true;
  show("Enviando enlace de recuperación…");

  try {
    const { error } = await withTimeout(
      supabase.auth.resetPasswordForEmail(value, {
        redirectTo: recoveryRedirectUrl()
      }),
      12000,
      "recovery_timeout"
    );

    if (error) {
      if (isRateLimitError(error)) {
        show("Límite temporal de recuperación. Por seguridad no podemos enviar otro correo en este momento. Espera unos minutos y vuelve a intentarlo.", true);
      } else {
        show("No se pudo enviar el enlace de recuperación. Inténtalo de nuevo más tarde.", true);
      }
      return;
    }

    show("Si la cuenta existe, recibirás un enlace para restablecer la contraseña.");
  } catch {
    show("No se pudo enviar el enlace de recuperación. Comprueba tu conexión e inténtalo de nuevo.", true);
  } finally {
    forgotBtn.disabled = false;
  }
});

// Existing-session detection is best effort and deliberately non-blocking.
void withTimeout(getCurrentSession(), 4000, "session_check_timeout")
  .then(existing => {
    if (existing && !loginInProgress) window.location.replace(targetPage());
  })
  .catch(error => console.warn("login_session_check_skipped", error));
