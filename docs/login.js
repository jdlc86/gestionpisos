import { supabase, getCurrentSession } from "./supabase-client.js";

const form = document.getElementById("loginForm");
const email = document.getElementById("email");
const password = document.getElementById("password");
const loginBtn = document.getElementById("loginBtn");
const forgotBtn = document.getElementById("forgotBtn");
const message = document.getElementById("authMessage");

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

const params = new URLSearchParams(window.location.search);
if (params.get("password") === "updated") {
  show("Contraseña actualizada. Ya puedes iniciar sesión.");
} else if (params.get("activated") === "1") {
  show("Cuenta activada. Ya puedes iniciar sesión.");
}

const existing = await getCurrentSession().catch(() => null);
if (existing) window.location.replace(targetPage());

form.addEventListener("submit", async event => {
  event.preventDefault();
  if (loginBtn.disabled) return;
  loginBtn.disabled = true;
  show("Comprobando acceso…");

  try {
    const { error } = await supabase.auth.signInWithPassword({
      email: email.value.trim().toLowerCase(),
      password: password.value
    });

    if (error) {
      show("No se pudo iniciar sesión. Comprueba el email y la contraseña.", true);
      return;
    }

    window.location.replace(targetPage());
  } catch (error) {
    console.error("login_request_failed", error);
    show("No se pudo contactar con el servicio de acceso. Comprueba tu conexión e inténtalo de nuevo.", true);
  } finally {
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
    const { error } = await supabase.auth.resetPasswordForEmail(value, {
      redirectTo: recoveryRedirectUrl()
    });

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
