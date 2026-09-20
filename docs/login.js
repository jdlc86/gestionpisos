import { supabase, getCurrentSession } from "./supabase-client.js?v=2026091603";
import { authFlowUrl, privilegedMfaRoute } from "./mfa-common.js?v=2026091701";

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

async function routeAuthenticatedSession(session) {
  const next = targetPage();

  const { data: platformAccess, error: platformAccessError } = await withTimeout(
    supabase.rpc("has_current_platform_access_v1"),
    5000,
    "platform_access_check_timeout"
  );
  if (platformAccessError) throw platformAccessError;
  if (platformAccess !== true) {
    try {
      const { error } = await supabase.auth.signOut({ scope: "global" });
      if (error) throw error;
    } catch {
      await supabase.auth.signOut({ scope: "local" }).catch(() => {});
    }
    throw new Error("platform_access_revoked");
  }

  const mfa = await withTimeout(
    privilegedMfaRoute(supabase, session, { requireEnrollment: true }),
    5000,
    "mfa_check_timeout"
  );
  if (mfa.route) {
    window.location.replace(authFlowUrl(mfa.route, next));
    return;
  }
  window.location.replace(next);
}

const params = new URLSearchParams(window.location.search);
if (params.get("access") === "revoked") {
  show("Tu acceso a Allaiso ya no está activo. Contacta con tu gestoría si necesitas recuperar el acceso.", true);
} else if (params.get("password") === "updated") {
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
    const { data, error } = await withTimeout(
      supabase.auth.signInWithPassword({
        email: email.value.trim().toLowerCase(),
        password: password.value
      }),
      12000,
      "login_timeout"
    );

    if (error || !data?.session) {
      show("No se pudo iniciar sesión. Comprueba el email y la contraseña.", true);
      return;
    }

    await routeAuthenticatedSession(data.session);
  } catch (error) {
    console.error("login_request_failed", error);
    const code = String(error?.message || "");
    if (code === "login_timeout") {
      show("El servicio de acceso no respondió a tiempo. Cierra GestionPisos, vuelve a abrirlo e inténtalo otra vez.", true);
    } else if (code === "platform_access_revoked") {
      show("Tu acceso a Allaiso ya no está activo. Contacta con tu gestoría si necesitas recuperarlo.", true);
    } else if (code === "platform_access_check_timeout") {
      show("No se pudo comprobar si tu acceso sigue activo. Comprueba tu conexión e inténtalo de nuevo.", true);
    } else if (code === "mfa_check_timeout") {
      show("No se pudo comprobar el segundo factor. Comprueba tu conexión e inténtalo de nuevo.", true);
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
    if (existing && !loginInProgress) return routeAuthenticatedSession(existing);
  })
  .catch(error => {
    if (String(error?.message || "") === "platform_access_revoked") {
      show("Tu acceso a Allaiso ya no está activo. Contacta con tu gestoría si necesitas recuperarlo.", true);
      return;
    }
    console.warn("login_session_check_skipped", error);
  });
