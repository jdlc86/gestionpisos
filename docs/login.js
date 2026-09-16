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
}

const existing = await getCurrentSession().catch(() => null);
if (existing) window.location.replace(targetPage());

form.addEventListener("submit", async event => {
  event.preventDefault();
  loginBtn.disabled = true;
  show("Comprobando acceso…");

  const { error } = await supabase.auth.signInWithPassword({
    email: email.value.trim(),
    password: password.value
  });

  if (error) {
    loginBtn.disabled = false;
    show("No se pudo iniciar sesión. Comprueba tus credenciales.", true);
    return;
  }

  window.location.replace(targetPage());
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
        show("Se han realizado demasiados intentos. Espera un poco y vuelve a probar.", true);
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
