import { supabase, getCurrentSession } from "./supabase-client.js";
import {
  authFlowUrl,
  getMfaAssurance,
  protectedTarget,
  requestedNext,
  requiresPrivilegedMfa
} from "./mfa-common.js?v=2026091701";

const form = document.getElementById("mfaChallengeForm");
const code = document.getElementById("mfaCode");
const submit = document.getElementById("mfaChallengeBtn");
const cancel = document.getElementById("cancelMfaBtn");
const message = document.getElementById("authMessage");

let factorId = null;
let ready = false;

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
  submit.disabled = !ready || value.length !== 6;
}

async function signOutToLogin() {
  cancel.disabled = true;
  await supabase.auth.signOut().catch(() => {});
  window.location.replace("./login.html");
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
    const verified = (Array.isArray(data?.totp) ? data.totp : []).filter(factor => factor.status === "verified");

    if (!verified.length) {
      window.location.replace(authFlowUrl("mfa-setup.html", requestedNext()));
      return;
    }

    factorId = verified[0].id;
    ready = true;
    code.disabled = false;
    syncCode();
    show("Introduce el código actual de tu app autenticadora.");
    code.focus();
  } catch (error) {
    console.error("mfa_challenge_bootstrap_failed", error);
    ready = false;
    code.disabled = true;
    submit.disabled = true;
    show("No se pudo preparar la verificación MFA. Cierra sesión y vuelve a intentarlo.", true);
  }
}

code.addEventListener("input", syncCode);
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
    submit.disabled = false;
    show("El código no es válido o ya ha caducado. Espera al siguiente código e inténtalo de nuevo.", true);
    code.select();
  }
});

bootstrap();
