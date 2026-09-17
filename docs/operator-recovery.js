const SOURCES = [
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.116.0/+esm",
  "https://esm.sh/@supabase/supabase-js@2.116.0"
];

let createClient;
for (const source of SOURCES) {
  try {
    const mod = await import(source);
    if (typeof mod.createClient === "function") {
      createClient = mod.createClient;
      break;
    }
  } catch {}
}
if (!createClient) throw new Error("supabase_client_module_unavailable");

const supabase = createClient(
  "https://qsxtmmkftsohkqqmytbb.supabase.co",
  "sb_publishable_InXekvnoNNlI1BX_pRWUBw_UMGnzgxR",
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: false,
      storageKey: "gestionpisos-platform-operator-auth"
    }
  }
);

const loginPanel = document.getElementById("loginPanel");
const loginForm = document.getElementById("operatorLoginForm");
const emailInput = document.getElementById("operatorEmail");
const passwordInput = document.getElementById("operatorPassword");
const loginBtn = document.getElementById("operatorLoginBtn");
const mfaPanel = document.getElementById("mfaPanel");
const mfaHelp = document.getElementById("mfaHelp");
const mfaEnrollPanel = document.getElementById("mfaEnrollPanel");
const qr = document.getElementById("operatorQr");
const secret = document.getElementById("operatorSecret");
const mfaForm = document.getElementById("operatorMfaForm");
const factorField = document.getElementById("operatorFactorField");
const factorSelect = document.getElementById("operatorFactorSelect");
const mfaCode = document.getElementById("operatorMfaCode");
const mfaBtn = document.getElementById("operatorMfaBtn");
const consolePanel = document.getElementById("consolePanel");
const operatorIdentity = document.getElementById("operatorIdentity");
const requestList = document.getElementById("requestList");
const refreshBtn = document.getElementById("refreshRequestsBtn");
const logoutBtn = document.getElementById("operatorLogoutBtn");
const message = document.getElementById("operatorMessage");

let operator = null;
let mfaMode = "challenge";
let enrollment = null;
let verifiedFactors = [];

function show(text, error = false) {
  message.textContent = text || "";
  message.classList.toggle("is-error", error);
}

function setPanel(name) {
  loginPanel.hidden = name !== "login";
  mfaPanel.hidden = name !== "mfa";
  consolePanel.hidden = name !== "console";
}

function cleanCode() {
  const value = mfaCode.value.replace(/\D/g, "").slice(0, 6);
  if (mfaCode.value !== value) mfaCode.value = value;
  return value;
}

async function invoke(action, extra = {}) {
  const { data, error } = await supabase.functions.invoke("operator-mfa-recovery", {
    body: { action, ...extra }
  });
  if (error) {
    const detail = data?.error || error?.context?.body?.error || error.message || "operator_request_failed";
    const wrapped = new Error(String(detail));
    wrapped.data = data;
    throw wrapped;
  }
  if (data?.error) throw new Error(String(data.error));
  return data;
}

async function ensureAuthorizedOperator() {
  const status = await invoke("status");
  operator = status.operator;
  return status;
}

function factorName(factor, index) {
  return String(factor?.friendly_name || factor?.friendlyName || "").trim() || `Autenticador ${index + 1}`;
}

async function prepareMfa() {
  const { data, error } = await supabase.auth.mfa.listFactors();
  if (error) throw error;
  verifiedFactors = (Array.isArray(data?.totp) ? data.totp : []).filter(f => f.status === "verified");
  factorSelect.replaceChildren();

  if (verifiedFactors.length) {
    mfaMode = "challenge";
    enrollment = null;
    mfaEnrollPanel.hidden = true;
    qr.hidden = true;
    secret.hidden = true;
    verifiedFactors.forEach((factor, index) => {
      const option = document.createElement("option");
      option.value = factor.id;
      option.textContent = factorName(factor, index);
      factorSelect.append(option);
    });
    factorField.hidden = verifiedFactors.length <= 1;
    mfaHelp.textContent = "Introduce un código de un autenticador verificado de la cuenta de operador.";
    mfaBtn.textContent = "Verificar operador";
    setPanel("mfa");
    mfaCode.focus();
    return;
  }

  mfaMode = "enroll";
  factorField.hidden = true;
  mfaEnrollPanel.hidden = false;
  mfaHelp.textContent = "Antes de usar la consola, registra MFA en esta cuenta técnica de operador.";
  show("Generando MFA para la cuenta de operador…");
  const { data: enrollData, error: enrollError } = await supabase.auth.mfa.enroll({
    factorType: "totp",
    friendlyName: "Allaiso · Operador"
  });
  if (enrollError) throw enrollError;
  enrollment = enrollData;
  qr.src = enrollData?.totp?.qr_code || "";
  qr.hidden = !qr.src;
  const secretValue = String(enrollData?.totp?.secret || "");
  secret.textContent = secretValue ? `Clave manual: ${secretValue}` : "";
  secret.hidden = !secretValue;
  mfaBtn.textContent = "Activar MFA de operador";
  setPanel("mfa");
  show("Escanea el QR con una app autenticadora y confirma con el código de 6 dígitos.");
}

async function enterConsole() {
  const status = await ensureAuthorizedOperator();
  if (status.aal !== "aal2") {
    await prepareMfa();
    return;
  }
  operatorIdentity.textContent = `${operator.display_name} · MFA verificado${operator.can_recover_root ? " · autorizado para ROOT" : ""}`;
  setPanel("console");
  show("");
  await loadRequests();
}

function fmt(value) {
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toLocaleString("es-ES") : "—";
}

function requestCard(item) {
  const article = document.createElement("article");
  article.className = "operator-request";

  const title = document.createElement("h3");
  title.textContent = `${String(item.role || "").toUpperCase()} · ${item.email || item.target_user_id}`;
  article.append(title);

  const meta = document.createElement("div");
  meta.className = "operator-meta";
  meta.innerHTML = `
    <span><strong>Solicitud:</strong> ${item.request_id}</span>
    <span><strong>Creada:</strong> ${fmt(item.requested_at)}</span>
    <span><strong>Caduca:</strong> ${fmt(item.expires_at)}</span>
    <span><strong>Factores declarados:</strong> ${Number(item.verified_factor_count || 0)}</span>
  `;
  article.append(meta);

  const note = document.createElement("textarea");
  note.className = "operator-note";
  note.placeholder = "Describe la verificación independiente realizada: canal, comprobaciones y resultado. No incluyas contraseñas ni códigos MFA.";
  note.maxLength = 500;
  article.append(note);

  const actions = document.createElement("div");
  actions.className = "operator-actions";

  const approve = document.createElement("button");
  approve.type = "button";
  approve.className = "operator-danger";
  approve.textContent = "Aprobar recuperación";
  approve.disabled = item.can_approve !== true;
  if (item.self_request) approve.title = "Un operador no puede aprobar su propia recuperación.";
  else if (item.role === "root" && item.can_approve !== true) approve.title = "Este operador no tiene capacidad para recuperar ROOT.";

  const reject = document.createElement("button");
  reject.type = "button";
  reject.className = "operator-secondary";
  reject.textContent = "Rechazar";

  approve.addEventListener("click", async () => {
    const verificationNote = note.value.trim();
    if (verificationNote.length < 20) {
      show("Documenta primero la verificación de identidad con al menos 20 caracteres.", true);
      note.focus();
      return;
    }
    const confirmed = window.confirm("Esta acción cerrará las sesiones del usuario, invalidará su contraseña y eliminará sus factores MFA. ¿Confirmas que su identidad ya fue verificada por un canal independiente?");
    if (!confirmed) return;
    approve.disabled = true;
    reject.disabled = true;
    show("Ejecutando recuperación segura…");
    try {
      const result = await invoke("approve", { request_id: item.request_id, verification_note: verificationNote });
      show(result?.recovery?.recovery_email_sent
        ? "Recuperación completada. Se envió el correo para crear una contraseña nueva."
        : "Recuperación completada. El usuario debe iniciar 'He olvidado mi contraseña'.");
      await loadRequests();
    } catch (error) {
      console.error("operator_recovery_approve_failed", error);
      show(`No se pudo completar: ${error.message}`, true);
      approve.disabled = item.can_approve !== true;
      reject.disabled = false;
    }
  });

  reject.addEventListener("click", async () => {
    const rejectionNote = note.value.trim();
    if (rejectionNote.length < 10) {
      show("Indica brevemente por qué se rechaza la solicitud.", true);
      note.focus();
      return;
    }
    if (!window.confirm("¿Rechazar esta solicitud de recuperación?")) return;
    approve.disabled = true;
    reject.disabled = true;
    show("Registrando rechazo…");
    try {
      await invoke("reject", { request_id: item.request_id, rejection_note: rejectionNote });
      show("Solicitud rechazada y auditada.");
      await loadRequests();
    } catch (error) {
      console.error("operator_recovery_reject_failed", error);
      show(`No se pudo rechazar: ${error.message}`, true);
      approve.disabled = item.can_approve !== true;
      reject.disabled = false;
    }
  });

  actions.append(approve, reject);
  article.append(actions);
  return article;
}

async function loadRequests() {
  refreshBtn.disabled = true;
  requestList.innerHTML = '<div class="operator-empty">Consultando solicitudes…</div>';
  try {
    const data = await invoke("list");
    const items = Array.isArray(data?.requests) ? data.requests : [];
    requestList.replaceChildren();
    if (!items.length) {
      const empty = document.createElement("div");
      empty.className = "operator-empty";
      empty.textContent = "No hay solicitudes MFA pendientes y vigentes.";
      requestList.append(empty);
    } else {
      items.forEach(item => requestList.append(requestCard(item)));
    }
  } catch (error) {
    console.error("operator_recovery_list_failed", error);
    requestList.innerHTML = '<div class="operator-empty">No se pudieron cargar las solicitudes.</div>';
    show(`Error de consola: ${error.message}`, true);
  } finally {
    refreshBtn.disabled = false;
  }
}

loginForm.addEventListener("submit", async event => {
  event.preventDefault();
  loginBtn.disabled = true;
  show("Verificando cuenta de operador…");
  try {
    const { error } = await supabase.auth.signInWithPassword({
      email: emailInput.value.trim(),
      password: passwordInput.value
    });
    if (error) throw error;
    await ensureAuthorizedOperator();
    passwordInput.value = "";
    await enterConsole();
  } catch (error) {
    console.error("operator_login_failed", error);
    await supabase.auth.signOut().catch(() => {});
    setPanel("login");
    show(error.message === "platform_operator_required"
      ? "Esta cuenta no está autorizada como operador de plataforma Allaiso."
      : "No se pudo iniciar sesión en la consola de operador.", true);
  } finally {
    loginBtn.disabled = false;
  }
});

mfaCode.addEventListener("input", cleanCode);
mfaForm.addEventListener("submit", async event => {
  event.preventDefault();
  const code = cleanCode();
  if (code.length !== 6) {
    show("Introduce los 6 dígitos del autenticador.", true);
    return;
  }
  mfaBtn.disabled = true;
  show("Verificando MFA…");
  try {
    if (mfaMode === "enroll") {
      const factorId = enrollment?.id;
      if (!factorId) throw new Error("operator_mfa_enrollment_missing");
      const { data: challenge, error: challengeError } = await supabase.auth.mfa.challenge({ factorId });
      if (challengeError) throw challengeError;
      const { error: verifyError } = await supabase.auth.mfa.verify({ factorId, challengeId: challenge.id, code });
      if (verifyError) throw verifyError;
    } else {
      const factorId = factorSelect.value || verifiedFactors[0]?.id;
      if (!factorId) throw new Error("operator_mfa_factor_missing");
      const { data: challenge, error: challengeError } = await supabase.auth.mfa.challenge({ factorId });
      if (challengeError) throw challengeError;
      const { error: verifyError } = await supabase.auth.mfa.verify({ factorId, challengeId: challenge.id, code });
      if (verifyError) throw verifyError;
    }
    mfaCode.value = "";
    await enterConsole();
  } catch (error) {
    console.error("operator_mfa_failed", error);
    show("El código no es válido o ya ha caducado. Inténtalo con el código actual.", true);
  } finally {
    mfaBtn.disabled = false;
  }
});

refreshBtn.addEventListener("click", loadRequests);
logoutBtn.addEventListener("click", async () => {
  await supabase.auth.signOut();
  operator = null;
  setPanel("login");
  show("Sesión de operador cerrada.");
});

(async function bootstrap() {
  try {
    const { data } = await supabase.auth.getSession();
    if (!data.session) {
      setPanel("login");
      return;
    }
    await ensureAuthorizedOperator();
    await enterConsole();
  } catch (error) {
    console.error("operator_console_bootstrap_failed", error);
    await supabase.auth.signOut().catch(() => {});
    setPanel("login");
    show("Inicia sesión con una cuenta de operador de plataforma autorizada.");
  }
})();
