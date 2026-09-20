import { supabase, getCurrentSession } from "./supabase-client.js";
import {
  authFlowUrl,
  getMfaAssurance,
  protectedTarget,
  requestedNext,
  requiresPrivilegedMfa
} from "./mfa-common.js?v=2026091701";
import { createOtpInput } from "./mfa-code-input.js?v=2026092001";

const form = document.getElementById("mfaChallengeForm");
const factorField = document.getElementById("mfaFactorField");
const factorSelect = document.getElementById("mfaFactorSelect");
const code = document.getElementById("mfaCode");
const codeBoxes = document.getElementById("mfaCodeBoxes");
const submit = document.getElementById("mfaChallengeBtn");
const recoveryBtn = document.getElementById("mfaRecoveryBtn");
const recoveryBox = document.getElementById("mfaRecoveryBox");
const recoveryRequestId = document.getElementById("mfaRecoveryRequestId");
const copyRecoveryRequestBtn = document.getElementById("copyRecoveryRequestBtn");
const cancel = document.getElementById("cancelMfaBtn");
const message = document.getElementById("authMessage");

let factorId = null;
let ready = false;
let verifiedFactors = [];
let recoveryPending = false;

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
  submit.disabled = !ready || !factorId || value.length !== 6;
}

const otp = createOtpInput({
  container: codeBoxes,
  valueInput: code,
  length: 6,
  onChange: syncCode
});

function factorFriendlyName(factor, index = 0) {
  const value = String(factor?.friendly_name || factor?.friendlyName || "").trim();
  if (value) return value;
  return index === 0 ? "Autenticador principal" : `Autenticador ${index + 1}`;
}

function renderFactorChooser(factors) {
  factorSelect.replaceChildren();
  factors.forEach((factor, index) => {
    const option = document.createElement("option");
    option.value = factor.id;
    option.textContent = factorFriendlyName(factor, index);
    factorSelect.append(option);
  });

  factorId = factors[0]?.id || null;
  factorSelect.value = factorId || "";
  factorField.hidden = factors.length <= 1;
}

async function signOutToLogin() {
  cancel.disabled = true;
  await supabase.auth.signOut().catch(() => {});
  window.location.replace("./login.html");
}

async function requestEmergencyRecovery() {
  if (recoveryPending) return;
  const confirmed = window.confirm(
    "¿Has perdido el acceso a todos tus autenticadores? La recuperación no elimina nada automáticamente: un operador técnico deberá verificar tu identidad antes de continuar."
  );
  if (!confirmed) return;

  recoveryPending = true;
  recoveryBtn.disabled = true;
  show("Registrando solicitud de recuperación…");

  try {
    const { data, error } = await supabase.functions.invoke("request-mfa-recovery", {
      body: { reason: "lost_all_available_authenticators" }
    });
    if (error || !data?.request_id) throw error || new Error("recovery_request_missing_id");

    recoveryRequestId.textContent = String(data.request_id);
    recoveryBox.hidden = false;
    recoveryBtn.hidden = true;
    show(data.reused
      ? "Ya había una solicitud de recuperación pendiente. Conserva este código para la verificación con soporte."
      : "Solicitud registrada. Tus factores MFA siguen intactos hasta que un operador verifique tu identidad.");
  } catch (error) {
    console.error("mfa_recovery_request_failed", error);
    recoveryPending = false;
    recoveryBtn.disabled = false;
    show("No se pudo registrar la recuperación de emergencia. Tus autenticadores no se han modificado. Inténtalo de nuevo o contacta con soporte.", true);
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
    if (assurance?.currentLevel === "aal2") {
      window.location.replace(protectedTarget(requestedNext()));
      return;
    }

    const { data, error } = await supabase.auth.mfa.listFactors();
    if (error) throw error;
    verifiedFactors = (Array.isArray(data?.totp) ? data.totp : []).filter(factor => factor.status === "verified");

    if (!verifiedFactors.length) {
      window.location.replace(authFlowUrl("mfa-setup.html", requestedNext()));
      return;
    }

    renderFactorChooser(verifiedFactors);
    ready = Boolean(factorId);
    otp.setDisabled(!ready);
    recoveryBtn.disabled = false;
    syncCode();
    show(verifiedFactors.length > 1
      ? "Elige el autenticador que tienes disponible e introduce su código actual."
      : "Introduce el código actual de tu app autenticadora.");
    otp.focus();
  } catch (error) {
    console.error("mfa_challenge_bootstrap_failed", error);
    ready = false;
    otp.setDisabled(true);
    submit.disabled = true;
    recoveryBtn.disabled = true;
    show("No se pudo preparar la verificación MFA. Cierra sesión y vuelve a intentarlo.", true);
  }
}

factorSelect.addEventListener("change", () => {
  factorId = factorSelect.value || null;
  otp.clear();
  syncCode();
  otp.focus();
});
recoveryBtn.addEventListener("click", () => void requestEmergencyRecovery());
copyRecoveryRequestBtn.addEventListener("click", async () => {
  const value = recoveryRequestId.textContent.trim();
  if (!value) return;
  try {
    await navigator.clipboard.writeText(value);
    copyRecoveryRequestBtn.textContent = "Copiado";
    setTimeout(() => { copyRecoveryRequestBtn.textContent = "Copiar"; }, 1400);
  } catch {
    show("No se pudo copiar automáticamente. Mantén pulsado el código para copiarlo.", true);
  }
});
cancel.addEventListener("click", signOutToLogin);

form.addEventListener("submit", async event => {
  event.preventDefault();
  if (!ready || !factorId) return;

  const verifyCode = normalizedCode();
  if (verifyCode.length !== 6) {
    show("Introduce los 6 dígitos de tu app autenticadora.", true);
    code.focus();
    return;
  }

  submit.disabled = true;
  code.disabled = true;
  factorSelect.disabled = true;
  recoveryBtn.disabled = true;
  show("Verificando código…");

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

    show("Identidad verificada. Entrando…");
    setTimeout(() => window.location.replace(protectedTarget(requestedNext())), 500);
  } catch (error) {
    console.error("mfa_challenge_verification_failed", error);
    code.disabled = false;
    factorSelect.disabled = false;
    submit.disabled = false;
    recoveryBtn.disabled = recoveryPending;
    show("El código no es válido o ya ha caducado. Espera al siguiente código e inténtalo de nuevo.", true);
    otp.clear();
    otp.focus();
  }
});

bootstrap();
