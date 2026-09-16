import { createClient } from "npm:@supabase/supabase-js@2";

const DEFAULT_APP_BASE_URL = "https://jdlc86.github.io/gestionpisos";

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[char] || char));
}

function appBaseUrl() {
  const configured = String(Deno.env.get("AUTH_APP_BASE_URL") || DEFAULT_APP_BASE_URL).trim();
  const url = new URL(configured);
  if (url.protocol !== "https:") throw new Error("invalid_auth_app_base_url");
  return url.href.replace(/\/$/, "");
}

async function recordDelivery(
  admin: ReturnType<typeof createClient>,
  input: {
    userId: string;
    organizationId: string;
    actorUserId: string;
    status: "sent" | "failed" | "not_configured";
    error?: string | null;
  },
) {
  const { error } = await admin.rpc("record_internal_staff_invitation_result", {
    p_user_id: input.userId,
    p_organization_id: input.organizationId,
    p_actor_user_id: input.actorUserId,
    p_status: input.status,
    p_error: input.error || null,
  });
  if (error) console.error("record_invitation_delivery_failed", error);
}

export type StaffInvitationResult = {
  status: "sent" | "failed" | "not_configured" | "cooldown";
  retry_after_seconds?: number;
  provider_message_id?: string | null;
};

export async function sendStaffOnboardingInvitation(
  admin: ReturnType<typeof createClient>,
  input: {
    userId: string;
    organizationId: string;
    actorUserId: string;
    email: string;
    displayName: string;
    role: "admin" | "employee";
  },
): Promise<StaffInvitationResult> {
  const { data: claim, error: claimError } = await admin.rpc("claim_internal_staff_invitation_attempt", {
    p_user_id: input.userId,
    p_organization_id: input.organizationId,
    p_actor_user_id: input.actorUserId,
    p_cooldown_seconds: 60,
  });
  if (claimError) throw new Error("invitation_claim_failed");
  if (claim?.allowed !== true) {
    return {
      status: "cooldown",
      retry_after_seconds: Number(claim?.retry_after_seconds || 60),
    };
  }

  const resendKey = String(Deno.env.get("RESEND_API_KEY") || "").trim();
  const sender = String(Deno.env.get("AUTH_EMAIL_FROM") || "").trim();
  if (!resendKey || !sender) {
    await recordDelivery(admin, {
      userId: input.userId,
      organizationId: input.organizationId,
      actorUserId: input.actorUserId,
      status: "not_configured",
      error: "professional_email_not_configured",
    });
    return { status: "not_configured" };
  }

  let actionLink = "";
  try {
    const redirectTo = `${appBaseUrl()}/activate-account.html?onboarding=1`;
    const { data, error } = await admin.auth.admin.generateLink({
      type: "recovery",
      email: input.email,
      options: { redirectTo },
    });
    if (error) throw error;
    actionLink = String(data?.properties?.action_link || "");
    if (!actionLink) throw new Error("empty_action_link");
  } catch (error) {
    const message = String((error as Error)?.message || "generate_onboarding_link_failed").slice(0, 200);
    await recordDelivery(admin, {
      userId: input.userId,
      organizationId: input.organizationId,
      actorUserId: input.actorUserId,
      status: "failed",
      error: message,
    });
    return { status: "failed" };
  }

  const continueUrl = new URL(`${appBaseUrl()}/accept-invitation.html`);
  continueUrl.searchParams.set("continue", actionLink);
  const name = escapeHtml(input.displayName || "usuario");
  const roleLabel = input.role === "admin" ? "administrador" : "empleado";

  const html = `<!doctype html><html><body style="font-family:Arial,sans-serif;line-height:1.5;color:#18212b"><div style="max-width:560px;margin:auto;padding:28px"><p style="font-size:12px;letter-spacing:.16em;font-weight:700">ALLAISO</p><h1 style="font-size:24px">Bienvenido a GestionPisos</h1><p>Hola ${name},</p><p>Se ha creado tu acceso como <strong>${roleLabel}</strong>. Para proteger tu cuenta, nadie ha definido una contraseña por ti.</p><p>Confirma que eres el titular de este correo y crea tu propia contraseña desde el botón siguiente.</p><p style="margin:28px 0"><a href="${escapeHtml(continueUrl.href)}" style="display:inline-block;padding:12px 18px;background:#111827;color:white;text-decoration:none;border-radius:8px">Activar mi cuenta</a></p><p>El enlace es de un solo uso. Si no esperabas esta invitación, no la abras y contacta con el administrador de GestionPisos.</p><p style="font-size:12px;color:#667085">Por seguridad, GestionPisos nunca envía contraseñas temporales por correo.</p></div></body></html>`;

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: sender,
        to: [input.email],
        subject: "Activa tu cuenta de GestionPisos",
        html,
      }),
    });

    const responseText = await response.text();
    if (!response.ok) {
      throw new Error(`resend_${response.status}:${responseText.slice(0, 120)}`);
    }

    let providerMessageId: string | null = null;
    try {
      providerMessageId = String(JSON.parse(responseText)?.id || "") || null;
    } catch {
      providerMessageId = null;
    }

    await recordDelivery(admin, {
      userId: input.userId,
      organizationId: input.organizationId,
      actorUserId: input.actorUserId,
      status: "sent",
    });
    return { status: "sent", provider_message_id: providerMessageId };
  } catch (error) {
    const message = String((error as Error)?.message || "professional_email_send_failed").slice(0, 200);
    await recordDelivery(admin, {
      userId: input.userId,
      organizationId: input.organizationId,
      actorUserId: input.actorUserId,
      status: "failed",
      error: message,
    });
    return { status: "failed" };
  }
}
