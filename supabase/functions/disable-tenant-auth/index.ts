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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get(["SUPABASE", "SERVICE", "ROLE", "KEY"].join("_"));
  const authorization = req.headers.get("Authorization");
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

  const { data: actorData, error: actorError } = await userClient.auth.getUser();
  const actor = actorData?.user;
  if (actorError || !actor) return json(401, { error: "invalid_session" });

  let body: { occupancy_id?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const occupancyId = String(body.occupancy_id || "").trim();
  if (!occupancyId) return json(400, { error: "occupancy_id_required" });

  const { data: state, error: stateError } = await userClient.rpc(
    "get_tenant_offboarding_auth_state_v1",
    { p_occupancy_id: occupancyId },
  );
  if (stateError) {
    const message = String(stateError.message || "");
    if (message.includes("property_write_required")) {
      return json(403, { error: "property_write_required" });
    }
    if (message.includes("tenant_offboarding_not_completed")) {
      return json(409, { error: "tenant_offboarding_not_completed" });
    }
    if (message.includes("occupancy_not_found")) {
      return json(404, { error: "occupancy_not_found" });
    }
    console.error(stateError);
    return json(500, { error: "tenant_offboarding_state_failed" });
  }

  const targetUserId = String(state?.target_user_id || "");
  const organizationId = String(state?.organization_id || "");
  const tenantId = String(state?.tenant_id || "");
  const disableAuth = state?.disable_auth === true;

  if (!targetUserId) {
    return json(200, {
      ok: true,
      occupancy_id: occupancyId,
      auth_disabled: false,
      reason: "no_auth_identity",
    });
  }

  if (!disableAuth) {
    return json(200, {
      ok: true,
      occupancy_id: occupancyId,
      target_user_id: targetUserId,
      auth_disabled: false,
      reason: state?.other_active_occupancy === true
        ? "other_active_occupancy"
        : state?.other_active_role === true
        ? "other_active_role"
        : "tenant_role_still_active",
    });
  }

  const { data: authData, error: lookupError } = await admin.auth.admin.getUserById(targetUserId);
  if (lookupError || !authData?.user) {
    console.error(lookupError);
    return json(404, { error: "auth_user_not_found", database_access_revoked: true });
  }

  const metadata = { ...(authData.user.app_metadata || {}) } as Record<string, unknown>;
  if (
    String(metadata.role || "") === "tenant" &&
    (!organizationId || String(metadata.organization_id || "") === organizationId)
  ) {
    delete metadata.role;
    delete metadata.organization_id;
  }

  const { error: disableError } = await admin.auth.admin.updateUserById(targetUserId, {
    ban_duration: "876000h",
    app_metadata: metadata,
  });
  if (disableError) {
    console.error(disableError);
    return json(500, {
      error: "tenant_auth_disable_failed",
      database_access_revoked: true,
      target_user_id: targetUserId,
    });
  }

  if (tenantId) {
    const { error: onboardingError } = await admin
      .from("external_account_onboarding")
      .update({
        status: "revoked",
        revoked_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("tenant_id", tenantId)
      .eq("auth_user_id", targetUserId)
      .in("status", ["pending", "active"]);
    if (onboardingError) {
      // Auth is already disabled and DB access revoked. Do not roll those back.
      console.error("tenant_external_onboarding_revoke_failed", onboardingError);
    }
  }

  const { error: auditError } = await admin.from("audit_log_v2").insert({
    organization_id: organizationId || null,
    actor_user_id: actor.id,
    action: "tenant_auth_disabled",
    entity_type: "tenant",
    entity_id: tenantId || targetUserId,
    result: "success",
    details: {
      occupancy_id: occupancyId,
      auth_user_id: targetUserId,
      reason: "tenant_offboarding",
    },
  });
  if (auditError) console.error("tenant_auth_disable_audit_failed", auditError);

  return json(200, {
    ok: true,
    occupancy_id: occupancyId,
    target_user_id: targetUserId,
    auth_disabled: true,
    database_access_revoked: true,
  });
});
