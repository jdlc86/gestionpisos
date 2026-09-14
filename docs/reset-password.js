import { supabase } from "./supabase-client.js";

const form = document.getElementById("resetForm");
const password = document.getElementById("newPassword");
const button = document.getElementById("resetBtn");
const message = document.getElementById("authMessage");

form.addEventListener("submit", async event => {
  event.preventDefault();
  button.disabled = true;
  message.textContent = "Actualizando contraseña…";

  const { error } = await supabase.auth.updateUser({ password: password.value });

  if (error) {
    button.disabled = false;
    message.textContent = "No se pudo actualizar la contraseña. Abre de nuevo el enlace de recuperación.";
    message.classList.add("is-error");
    return;
  }

  await supabase.auth.signOut();
  message.textContent = "Contraseña actualizada. Redirigiendo al acceso…";
  setTimeout(() => window.location.replace("./login.html"), 900);
});
