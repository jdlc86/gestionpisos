import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const headers = {
  "Content-Type": "application/json",
};

const encoder = new TextEncoder();

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers });
}

function timingSafeEqual(a: string, b: string) {
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i += 1) diff |= left[i] ^ right[i];
  return diff === 0;
}

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[char] || char));
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get(["SUPABASE", "SERVICE", "ROLE", "KEY"].join("_"));
  const resendKey = String(Deno.env.get("RESEND_API_KEY") || "").trim();
  const sender = String(Deno.env.get("AUTH_EMAIL_FROM") || "").trim();

  if (!supabaseUrl || !serviceKey) {
    return json(500, { error: "server_configuration_missing" });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: configRows, error: configError } = await admin.rpc(
    "notification_email_server_config_v1",
  );
  if (configError) return json(503, { error: "email_dispatch_config_failed" });
  const config = Array.isArray(configRows) ? configRows[0] : configRows;
  const expectedSecret = String(config?.dispatch_secret || "");
  const providedSecret = req.headers.get("X-Allaiso-Email-Secret") || "";
  if (!expectedSecret || !timingSafeEqual(providedSecret, expectedSecret)) {
    return json(401, { error: "invalid_dispatch_secret" });
  }

  let body: { notification_id?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const notificationId = String(body.notification_id || "").trim();
  if (!notificationId) return json(400, { error: "notification_id_required" });

  const { data: claimed, error: claimError } = await admin.rpc(
    "notification_email_claim_delivery_v1",
    { p_notification_id: notificationId },
  );
  if (claimError) return json(500, { error: "email_delivery_claim_failed" });
  if (claimed !== true) {
    return json(200, { ok: true, delivered: false, skipped: "already_claimed_or_not_email" });
  }

  const finish = async (
    success: boolean,
    errorCode: string | null,
    providerMessageId: string | null = null,
  ) => {
    const { error } = await admin.rpc("notification_email_finish_delivery_v1", {
      p_notification_id: notificationId,
      p_success: success,
      p_error_code: errorCode,
      p_provider_message_id: providerMessageId,
    });
    if (error) console.error("notification_email_finish_failed", error);
  };

  const { data: notification, error: notificationError } = await admin
    .from("notifications_v2")
    .select("id,recipient_user_id,title,body,channel_email")
    .eq("id", notificationId)
    .maybeSingle();

  if (notificationError || !notification || notification.channel_email !== true) {
    await finish(false, "notification_lookup_failed");
    return json(404, { error: "notification_not_found" });
  }

  const { data: userData, error: userError } = await admin.auth.admin.getUserById(
    String(notification.recipient_user_id),
  );
  const email = String(userData?.user?.email || "").trim().toLowerCase();
  if (userError || !userData?.user || !email) {
    await finish(false, "recipient_email_unavailable");
    return json(200, { ok: true, delivered: false, error: "recipient_email_unavailable" });
  }

  if (!resendKey || !sender) {
    await finish(false, "professional_email_not_configured");
    return json(200, { ok: true, delivered: false, error: "professional_email_not_configured" });
  }

  const title = String(notification.title || "Allaiso").trim().slice(0, 180) || "Allaiso";
  const text = String(notification.body || "").trim().slice(0, 6000);
  const html = `<!doctype html><html><body style="font-family:Arial,sans-serif;line-height:1.5;color:#18212b"><div style="max-width:560px;margin:auto;padding:28px"><p style="font-size:12px;letter-spacing:.16em;font-weight:700">ALLAISO</p><h1 style="font-size:22px">${escapeHtml(title)}</h1><p>${escapeHtml(text).replace(/\n/g, "<br>")}</p><p style="font-size:12px;color:#667085;margin-top:28px">Mensaje enviado por tu gestoría a través de Allaiso.</p></div></body></html>`;

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `allaiso-notification/${notificationId}`,
      },
      body: JSON.stringify({
        from: sender,
        to: [email],
        subject: title,
        html,
      }),
    });

    const responseText = await response.text();
    if (!response.ok) {
      const code = `resend_${response.status}`;
      console.error("notification_email_send_failed", { notificationId, code });
      await finish(false, code);
      return json(200, { ok: true, delivered: false, error: code });
    }

    let providerMessageId: string | null = null;
    try {
      providerMessageId = String(JSON.parse(responseText)?.id || "") || null;
    } catch {
      providerMessageId = null;
    }

    await finish(true, null, providerMessageId);
    return json(200, { ok: true, delivered: true });
  } catch (error) {
    console.error("notification_email_send_failed", {
      notificationId,
      message: String((error as Error)?.message || "unknown").slice(0, 160),
    });
    await finish(false, "email_send_failed");
    return json(200, { ok: true, delivered: false, error: "email_send_failed" });
  }
});
