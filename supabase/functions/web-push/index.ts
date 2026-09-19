import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://jdlc86.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const encoder = new TextEncoder();

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function timingSafeEqual(a: string, b: string) {
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i += 1) diff |= left[i] ^ right[i];
  return diff === 0;
}

function routeFor(eventType: string) {
  if (eventType === "workflow_task_created") return "./workflow-tasks.html";
  if (eventType === "workflow_completed" || eventType === "workflow_rejected") return "./workflow-history.html";
  if (eventType === "workflow_schedule_blocked") return "./workflow-definitions.html";
  return "./";
}

type ServerConfig = {
  dispatch_secret?: string | null;
  vapid_public_key?: string | null;
  vapid_private_key?: string | null;
};

async function loadConfig(admin: ReturnType<typeof createClient>) {
  const { data, error } = await admin.rpc("web_push_server_config_v1");
  if (error) throw new Error("web_push_config_failed");
  const row = Array.isArray(data) ? data[0] : data;
  return (row || {}) as ServerConfig;
}

async function ensureVapid(admin: ReturnType<typeof createClient>) {
  let config = await loadConfig(admin);
  if (config.vapid_public_key && config.vapid_private_key) return config;

  const generated = webpush.generateVAPIDKeys();
  const { error } = await admin.rpc("web_push_store_vapid_v1", {
    p_public_key: generated.publicKey,
    p_private_key: generated.privateKey,
  });
  if (error) throw new Error("web_push_vapid_store_failed");

  config = await loadConfig(admin);
  if (!config.vapid_public_key || !config.vapid_private_key) {
    throw new Error("web_push_vapid_unavailable");
  }
  return config;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get(["SUPABASE", "SERVICE", "ROLE", "KEY"].join("_"));
  if (!supabaseUrl || !anonKey || !serviceKey) return json(500, { error: "server_configuration_missing" });

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: { action?: string; notification_id?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const action = String(body.action || "").trim();

  if (action === "config") {
    const authorization = req.headers.get("Authorization");
    if (!authorization) return json(401, { error: "authentication_required" });

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: actorData, error: actorError } = await userClient.auth.getUser();
    if (actorError || !actorData?.user) return json(401, { error: "invalid_session" });

    try {
      const config = await ensureVapid(admin);
      return json(200, { public_key: config.vapid_public_key });
    } catch (error) {
      console.error(error);
      return json(503, { error: "web_push_configuration_unavailable" });
    }
  }

  const notificationId = String(body.notification_id || "").trim();
  if (!notificationId) return json(400, { error: "notification_id_required" });

  let config: ServerConfig;
  try {
    config = await ensureVapid(admin);
  } catch (error) {
    console.error(error);
    return json(503, { error: "web_push_configuration_unavailable" });
  }

  const providedSecret = req.headers.get("X-Allaiso-Push-Secret") || "";
  const expectedSecret = String(config.dispatch_secret || "");
  if (!expectedSecret || !timingSafeEqual(providedSecret, expectedSecret)) {
    return json(401, { error: "invalid_dispatch_secret" });
  }

  const { data: notification, error: notificationError } = await admin
    .from("notifications_v2")
    .select("id,recipient_user_id,event_type,title,body,channel_in_app")
    .eq("id", notificationId)
    .maybeSingle();

  if (notificationError) return json(500, { error: "notification_lookup_failed" });
  if (!notification || notification.channel_in_app !== true) return json(404, { error: "notification_not_found" });

  const allowedEvents = new Set([
    "workflow_task_created",
    "workflow_completed",
    "workflow_rejected",
    "workflow_schedule_blocked",
  ]);
  if (!allowedEvents.has(String(notification.event_type))) {
    return json(200, { ok: true, delivered: 0, skipped: "event_not_push_enabled" });
  }

  const { data: subscriptions, error: subscriptionError } = await admin.rpc(
    "web_push_list_subscriptions_v1",
    { p_user_id: notification.recipient_user_id },
  );
  if (subscriptionError) return json(500, { error: "subscription_lookup_failed" });

  if (!subscriptions?.length) return json(200, { ok: true, delivered: 0 });

  webpush.setVapidDetails(
    "mailto:no-reply@auth.allaiso.com",
    String(config.vapid_public_key),
    String(config.vapid_private_key),
  );

  const payload = JSON.stringify({
    notificationId: notification.id,
    title: notification.title || "Allaiso",
    body: notification.body || "",
    url: routeFor(String(notification.event_type)),
    tag: "allaiso-" + notification.id,
  });

  let delivered = 0;
  let failed = 0;

  for (const subscription of subscriptions) {
    const subscriptionId = String(subscription.subscription_id || "");
    if (!subscriptionId) continue;

    const { data: claimed, error: claimError } = await admin.rpc(
      "web_push_claim_delivery_v1",
      {
        p_notification_id: notification.id,
        p_subscription_id: subscriptionId,
      },
    );
    if (claimError || claimed !== true) continue;

    try {
      await webpush.sendNotification(
        {
          endpoint: String(subscription.endpoint),
          keys: {
            p256dh: String(subscription.p256dh),
            auth: String(subscription.auth_secret),
          },
        },
        payload,
        { TTL: 300, urgency: "high" },
      );

      delivered += 1;
      await admin.rpc("web_push_finish_delivery_v1", {
        p_notification_id: notification.id,
        p_subscription_id: subscriptionId,
        p_success: true,
        p_error_code: null,
        p_disable_subscription: false,
      });
    } catch (error) {
      failed += 1;
      const statusCode = Number((error as { statusCode?: number })?.statusCode || 0);
      const disable = statusCode === 404 || statusCode === 410;
      const code = statusCode ? "push_http_" + statusCode : "push_send_failed";
      console.error("web_push_send_failed", { notificationId, subscriptionId, code });

      await admin.rpc("web_push_finish_delivery_v1", {
        p_notification_id: notification.id,
        p_subscription_id: subscriptionId,
        p_success: false,
        p_error_code: code,
        p_disable_subscription: disable,
      });
    }
  }

  return json(200, { ok: true, delivered, failed });
});
