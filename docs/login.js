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
  const value = email.value.trim();
  if (!value) {
    show("Introduce primero tu email.", true);
    email.focus();
    return;
  }

  forgotBtn.disabled = true;
  const redirectTo = new URL("./reset-password.html", window.location.href).href;
  await supabase.auth.resetPasswordForEmail(value, { redirectTo });
  forgotBtn.disabled = false;
  show("Si la cuenta existe, recibirás un enlace para restablecer la contraseña.");
});
