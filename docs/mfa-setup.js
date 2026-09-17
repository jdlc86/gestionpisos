import { supabase, getCurrentSession } from "./supabase-client.js";
import {
  authFlowUrl,
  getMfaAssurance,
  protectedTarget,
  requestedNext,
  requiresPrivilegedMfa
} from "./mfa-common.js?v=2026091701";

const panel = document.getElementById("mfaSetupPanel");
const qr = document.getElementById("mfaQr");
const secret = document.getElementById("mfaSecret");
const copySecretBtn = document.getElementById("copySecretBtn");
const form = document.getElementById("mfaSetupForm");
const code = document.getElementById("mfaCode");
const submit = document.getElementById("mfaSetupBtn");
const cancel = document.getElementById("cancelMfaBtn");
const message = document.getElementById("authMessage");

let factorId = null;
let setupReady = false;

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

async function signOutToLogin() {
  cancel.disabled = true;
  await supabase.auth.signOut().catch(() => {});
  window.location.replace("./login.html");
}

async function removeStaleUnverifiedFactors() {
  const { data, error } = await supabase.auth.mfa.listFactors();
  if (error) throw error;
  const allTotp = Array.isArray(data?.totp) ? data.totp : [];
  const verified = allTotp.filter(factor => factor.status === "verified");
  if (verified.length) return { verified: true };

  const stale = allTotp.filter(factor => factor.status !== "verified");
  for (const factor of stale) {
    const { error: unenrollError } = await supabase.auth.mfa.unenroll({ factorId: factor.id });
    if (unenrollError) console.warn("mfa_unverified_cleanup_skipped", factor.id);
  }
  return { verified: false };
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

    const factorState = await removeStaleUnverifiedFactors();
    if (factorState.verified || assurance?.nextLevel === "aal2") {
      window.location.replace(authFlowUrl("mfa-challenge.html", requestedNext()));
      return;
    }

    const { data, error } = await supabase.auth.mfa.enroll({ factorType: "totp" });
    if (error) throw error;

    factorId = data?.id || null;
    const qrCode = data?.totp?.qr_code || "";
    const sharedSecret = data?.totp?.secret || "";
    if (!factorId || !qrCode || !sharedSecret) throw new Error("mfa_enrollment_payload_incomplete");

    qr.src = qrDataUrl(qrCode);
    secret.textContent = sharedSecret;
    panel.hidden = false;
    setupReady = true;
    syncCode();
    show("Escanea el QR e introduce el código de 6 dígitos para confirmar.");
    code.focus();
  } catch (error) {
    console.error("mfa_setup_failed", error);
    setupReady = false;
    submit.disabled = true;
    show("No se pudo preparar la autenticación multifactor. Cierra sesión y vuelve a intentarlo.", true);
  }
}

code.addEventListener("input", syncCode);

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
  show("Verificando segundo factor…");

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

    show("MFA activado correctamente. Entrando…");
    setTimeout(() => window.location.replace(protectedTarget(requestedNext())), 650);
  } catch (error) {
    console.error("mfa_setup_verification_failed", error);
    code.disabled = false;
    submit.disabled = false;
    show("El código no es válido o ya ha caducado. Espera al siguiente código de tu app e inténtalo de nuevo.", true);
    code.select();
  }
});

bootstrap();
