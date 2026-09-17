import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://jdlc86.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function bearerToken(authorization: string) {
  return authorization.replace(/^Bearer\s+/i, "").trim();
}

function jwtPayload(token: string): Record<string, unknown> | null {
  try {
    const part = token.split(".")[1];
    if (!part) return null;
    const base64 = part.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(part.length / 4) * 4, "=");
    return JSON.parse(atob(base64));
  } catch {
    return null;
  }
}

function validUuid(value: unknown) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || ""));
}

function cleanReason(value: unknown) {
  return String(value || "lost_authenticator_access").trim().replace(/\s+/g, " ").slice(0, 160);
}

function adminAuthHeaders(serviceKey: string) {
  return {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get(["SUPABASE", "SERVICE", "ROLE", "KEY"].join("_"));
  const authorization = req.headers.get("Authorization") || "";
  if (!supabaseUrl || !anonKey || !serviceKey || !authorization) {
    return json(401, { error: "authentication_required" });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  const actor = userData?.user;
  if (userError || !actor) return json(401, { error: "invalid_session" });

  const role = String(actor.app_metadata?.role || "").toLowerCase();
  if (role !== "root" && role !== "admin") return json(403, { error: "privileged_role_required" });

  const payload = jwtPayload(bearerToken(authorization));
  const aal = String(payload?.aal || "");
  if (aal === "aal2") return json(409, { error: "mfa_recovery_not_needed" });

  const factorsResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users/${actor.id}/factors`, {
    headers: adminAuthHeaders(serviceKey),
  });
  if (!factorsResponse.ok) return json(502, { error: "factor_lookup_failed" });

  const factorPayload = await factorsResponse.json();
  const factors = Array.isArray(factorPayload) ? factorPayload : [];
  const verifiedFactors = factors.filter((factor: Record<string, unknown>) => factor?.status === "verified");
  if (!verifiedFactors.length) return json(409, { error: "no_verified_factor_to_recover" });

  let body: { reason?: string } = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const reason = cleanReason(body.reason);

  const cooldownSince = new Date(Date.now() - 5 * 60 * 1000).toISOString();
  const { data: recentRows } = await admin
    .from("audit_log_v2")
    .select("details,created_at")
    .eq("action", "mfa_recovery_requested")
    .eq("entity_type", "auth_user")
    .eq("entity_id", actor.id)
    .eq("result", "pending")
    .gte("created_at", cooldownSince)
    .order("created_at", { ascending: false })
    .limit(1);

  const existingRequestId = String(recentRows?.[0]?.details?.request_id || "");
  if (validUuid(existingRequestId)) {
    return json(200, {
      ok: true,
      request_id: existingRequestId,
      status: "pending",
      reused: true,
      expires_in_minutes: 60,
    });
  }

  const requestId = crypto.randomUUID();
  const organizationId = validUuid(actor.app_metadata?.organization_id)
    ? String(actor.app_metadata.organization_id)
    : null;

  const { error: auditError } = await admin.from("audit_log_v2").insert({
    organization_id: organizationId,
    actor_user_id: actor.id,
    action: "mfa_recovery_requested",
    entity_type: "auth_user",
    entity_id: actor.id,
    result: "pending",
    details: {
      request_id: requestId,
      reason,
      role,
      verified_factor_count: verifiedFactors.length,
      requested_aal: aal || "aal1",
      expires_at: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    },
  });

  if (auditError) {
    console.error("mfa_recovery_request_audit_failed", auditError.message);
    return json(500, { error: "recovery_request_not_recorded" });
  }

  return json(200, {
    ok: true,
    request_id: requestId,
    status: "pending",
    reused: false,
    expires_in_minutes: 60,
  });
});
