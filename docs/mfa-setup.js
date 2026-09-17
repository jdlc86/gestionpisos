import { supabase, getCurrentSession } from "./supabase-client.js";
import {
  authFlowUrl,
  getMfaAssurance,
  protectedTarget,
  requestedNext,
  requiresPrivilegedMfa
} from "./mfa-common.js?v=2026091701";

const managePanel = document.getElementById("mfaManagePanel");
const factorList = document.getElementById("mfaFactorList");
const addBackupBtn = document.getElementById("addBackupBtn");
const finishMfaBtn = document.getElementById("finishMfaBtn");
const panel = document.getElementById("mfaSetupPanel");
const enrollmentTitle = document.getElementById("mfaEnrollmentTitle");
const qr = document.getElementById("mfaQr");
const secret = document.getElementById("mfaSecret");
const copySecretBtn = document.getElementById("copySecretBtn");
const form = document.getElementById("mfaSetupForm");
const code = document.getElementById("mfaCode");
const submit = document.getElementById("mfaSetupBtn");
const cancelEnrollmentBtn = document.getElementById("cancelEnrollmentBtn");
const cancel = document.getElementById("cancelMfaBtn");
const message = document.getElementById("authMessage");

let factorId = null;
let setupReady = false;
let enrollmentMode = "initial";
let verifiedFactors = [];

function show(text, error = false) {
  message.textContent = text;
  message.classList.toggle("is-error", error);
}

function normalizedCode() {
  return code.value.replace(/\D/g, "").slice(0, 6);
}

function syncCode() {
  const value = normalizedCode();
  if (code.value !== value) code.value = value;
  submit.disabled = !setupReady || value.length !== 6;
}

function qrDataUrl(svg) {
  if (!svg) return "";
  if (String(svg).startsWith("data:")) return svg;
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}

function factorFriendlyName(factor, index = 0) {
  const value = String(factor?.friendly_name || factor?.friendlyName || "").trim();
  if (value) return value;
  return index === 0 ? "Autenticador principal" : `Autenticador ${index + 1}`;
}

function nextBackupName(factors) {
  const used = new Set(factors.map((factor, index) => factorFriendlyName(factor, index).toLowerCase()));
  let number = 1;
  while (used.has(`respaldo ${number}`)) number += 1;
  return `Respaldo ${number}`;
}

async function listTotpFactors() {
  const { data, error } = await supabase.auth.mfa.listFactors();
  if (error) throw error;
  return Array.isArray(data?.totp) ? data.totp : [];
}

async function removeUnverifiedFactors(factors) {
  const stale = factors.filter(factor => factor.status !== "verified");
  for (const factor of stale) {
    const { error } = await supabase.auth.mfa.unenroll({ factorId: factor.id });
    if (error) console.warn("mfa_unverified_cleanup_skipped", factor.id);
  }
}

function resetEnrollmentPanel() {
  factorId = null;
  setupReady = false;
  code.value = "";
  code.disabled = false;
  submit.disabled = true;
  qr.removeAttribute("src");
  secret.textContent = "";
  panel.hidden = true;
  cancelEnrollmentBtn.hidden = true;
}

function renderManagement(factors) {
  verifiedFactors = factors.filter(factor => factor.status === "verified");
  factorList.replaceChildren();

  verifiedFactors.forEach((factor, index) => {
    const row = document.createElement("div");
    row.className = "mfa-factor-row";

    const info = document.createElement("div");
    info.className = "mfa-factor-info";
    const name = document.createElement("strong");
    name.textContent = factorFriendlyName(factor, index);
    const status = document.createElement("span");
    status.textContent = "Verificado";
    info.append(name, status);

    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "ghost mfa-remove-factor";
    remove.textContent = "Eliminar";
    remove.disabled = verifiedFactors.length <= 1;
    remove.title = verifiedFactors.length <= 1
      ? "Añade primero un factor de respaldo."
      : "Eliminar este autenticador";
    remove.addEventListener("click", () => void removeVerifiedFactor(factor, remove));

    row.append(info, remove);
    factorList.append(row);
  });

  addBackupBtn.disabled = verifiedFactors.length >= 10;
  managePanel.hidden = false;
  panel.hidden = true;
  cancel.hidden = true;
}

async function loadAndShowManagement(statusText = "") {
  const factors = await listTotpFactors();
  renderManagement(factors);
  if (statusText) {
    show(statusText);
  } else if (verifiedFactors.length < 2) {
    show("MFA está activo. Añade un factor de respaldo para poder recuperar el acceso si pierdes el principal.");
  } else {
    show("MFA está protegido con un factor principal y al menos un respaldo.");
  }
}

async function signOutToLogin() {
  cancel.disabled = true;
  await supabase.auth.signOut().catch(() => {});
  window.location.replace("./login.html");
}

async function startEnrollment(mode) {
  enrollmentMode = mode;
  setupReady = false;
  submit.disabled = true;
  code.value = "";
  managePanel.hidden = true;
  panel.hidden = true;

  try {
    let factors = await listTotpFactors();
    await removeUnverifiedFactors(factors);
    factors = await listTotpFactors();
    const verified = factors.filter(factor => factor.status === "verified");

    const friendlyName = mode === "initial" ? "Principal" : nextBackupName(verified);
    const { data, error } = await supabase.auth.mfa.enroll({
      factorType: "totp",
      friendlyName
    });
    if (error) throw error;

    factorId = data?.id || null;
    const qrCode = data?.totp?.qr_code || "";
    const sharedSecret = data?.totp?.secret || "";
    if (!factorId || !qrCode || !sharedSecret) throw new Error("mfa_enrollment_payload_incomplete");

    enrollmentTitle.textContent = mode === "initial"
      ? "Configurar autenticador principal"
      : "Configurar factor de respaldo";
    qr.src = qrDataUrl(qrCode);
    secret.textContent = sharedSecret;
    panel.hidden = false;
    cancelEnrollmentBtn.hidden = mode === "initial";
    cancel.hidden = mode !== "initial";
    setupReady = true;
    syncCode();
    show(mode === "initial"
      ? "Escanea el QR e introduce el código de 6 dígitos para activar MFA."
      : "Escanea el QR con tu dispositivo de respaldo y confirma el código de 6 dígitos.");
    code.focus();
  } catch (error) {
    console.error("mfa_enrollment_start_failed", error);
    setupReady = false;
    submit.disabled = true;
    show("No se pudo preparar el nuevo autenticador. Inténtalo de nuevo.", true);
    if (mode === "backup") await loadAndShowManagement().catch(() => {});
  }
}

async function removeVerifiedFactor(factor, button) {
  if (verifiedFactors.length <= 1) {
    show("No puedes eliminar el único factor MFA. Añade primero uno de respaldo.", true);
    return;
  }

  const label = factorFriendlyName(factor, verifiedFactors.indexOf(factor));
  const confirmed = window.confirm(`¿Eliminar “${label}”? Dejará de servir para entrar en GestionPisos.`);
  if (!confirmed) return;

  button.disabled = true;
  show("Eliminando autenticador…");
  try {
    const assurance = await getMfaAssurance(supabase);
    if (assurance?.currentLevel !== "aal2") {
      window.location.replace(authFlowUrl("mfa-challenge.html", "mfa-setup.html"));
      return;
    }

    const { error } = await supabase.auth.mfa.unenroll({ factorId: factor.id });
    if (error) throw error;
    await loadAndShowManagement("Autenticador eliminado. El resto de factores siguen activos.");
  } catch (error) {
    console.error("mfa_verified_unenroll_failed", error);
    show("No se pudo eliminar el autenticador. Verifica de nuevo tu identidad e inténtalo otra vez.", true);
    button.disabled = false;
  }
}

async function cancelPendingEnrollment() {
  cancelEnrollmentBtn.disabled = true;
  try {
    if (factorId) await supabase.auth.mfa.unenroll({ factorId }).catch(() => {});
  } finally {
    resetEnrollmentPanel();
    cancelEnrollmentBtn.disabled = false;
    await loadAndShowManagement("Alta cancelada. Tus factores verificados no han cambiado.");
  }
}

async function bootstrap() {
  try {
    const session = await getCurrentSession();
    if (!session) {
      window.location.replace("./login.html");
      return;
    }

    if (!requiresPrivilegedMfa(session)) {
      window.location.replace(protectedTarget(requestedNext()));
      return;
    }

    const assurance = await getMfaAssurance(supabase);
    let factors = await listTotpFactors();
    const verified = factors.filter(factor => factor.status === "verified");

    if (verified.length) {
      if (assurance?.currentLevel !== "aal2") {
        window.location.replace(authFlowUrl("mfa-challenge.html", "mfa-setup.html"));
        return;
      }
      await removeUnverifiedFactors(factors);
      factors = await listTotpFactors();
      renderManagement(factors);
      show(verified.length < 2
        ? "MFA está activo. Añade un factor de respaldo para protegerte ante la pérdida del móvil."
        : "Tus factores MFA están listos.");
      return;
    }

    await removeUnverifiedFactors(factors);
    await startEnrollment("initial");
  } catch (error) {
    console.error("mfa_setup_failed", error);
    setupReady = false;
    submit.disabled = true;
    show("No se pudo preparar la autenticación multifactor. Cierra sesión y vuelve a intentarlo.", true);
  }
}

code.addEventListener("input", syncCode);
addBackupBtn.addEventListener("click", () => void startEnrollment("backup"));
finishMfaBtn.addEventListener("click", () => window.location.replace(protectedTarget(requestedNext())));
cancelEnrollmentBtn.addEventListener("click", () => void cancelPendingEnrollment());

copySecretBtn.addEventListener("click", async () => {
  const value = secret.textContent.trim();
  if (!value) return;
  try {
    await navigator.clipboard.writeText(value);
    copySecretBtn.textContent = "Copiado";
    setTimeout(() => { copySecretBtn.textContent = "Copiar"; }, 1400);
  } catch {
    show("No se pudo copiar automáticamente. Mantén pulsada la clave para copiarla.", true);
  }
});

cancel.addEventListener("click", signOutToLogin);

form.addEventListener("submit", async event => {
  event.preventDefault();
  if (!setupReady || !factorId) return;

  const verifyCode = normalizedCode();
  if (verifyCode.length !== 6) {
    show("Introduce los 6 dígitos de tu app autenticadora.", true);
    code.focus();
    return;
  }

  submit.disabled = true;
  code.disabled = true;
  show("Verificando autenticador…");

  try {
    const { data: challenge, error: challengeError } = await supabase.auth.mfa.challenge({ factorId });
    if (challengeError) throw challengeError;

    const { error: verifyError } = await supabase.auth.mfa.verify({
      factorId,
      challengeId: challenge.id,
      code: verifyCode
    });
    if (verifyError) throw verifyError;

    const assurance = await getMfaAssurance(supabase);
    if (assurance?.currentLevel !== "aal2") throw new Error("mfa_aal2_not_reached");

    if (enrollmentMode === "initial") {
      show("MFA activado correctamente. Entrando…");
      setTimeout(() => window.location.replace(protectedTarget(requestedNext())), 650);
      return;
    }

    resetEnrollmentPanel();
    await loadAndShowManagement("Factor de respaldo activado correctamente.");
  } catch (error) {
    console.error("mfa_setup_verification_failed", error);
    code.disabled = false;
    submit.disabled = false;
    show("El código no es válido o ya ha caducado. Espera al siguiente código de tu app e inténtalo de nuevo.", true);
    code.select();
  }
});

bootstrap();
