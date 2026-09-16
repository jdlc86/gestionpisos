const button = document.getElementById("continueInvitation");
const message = document.getElementById("authMessage");
const params = new URLSearchParams(window.location.search);
const rawContinue = params.get("continue") || "";
let actionLink = "";

function show(text, error = false) {
  message.textContent = text;
  message.classList.toggle("is-error", error);
}

function validActionLink(value) {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:") return false;
    if (url.hostname !== "qsxtmmkftsohkqqmytbb.supabase.co") return false;
    if (url.pathname !== "/auth/v1/verify") return false;
    const type = url.searchParams.get("type");
    return type === "recovery" || type === "invite";
  } catch {
    return false;
  }
}

if (validActionLink(rawContinue)) {
  actionLink = rawContinue;
  history.replaceState(null, "", "./accept-invitation.html");
  button.disabled = false;
  show("Invitación preparada. Pulsa continuar para verificarla y crear tu contraseña.");
} else {
  show("La invitación no es válida. Solicita al administrador que envíe una nueva.", true);
}

button.addEventListener("click", () => {
  if (!actionLink || !validActionLink(actionLink)) return;
  button.disabled = true;
  show("Verificando invitación…");
  window.location.assign(actionLink);
});
