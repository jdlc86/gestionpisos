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

function cleanText(value: unknown, maxLength: number) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function adminHeaders(serviceKey: string) {
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
  const accessToken = bearerToken(authorization);

  if (!supabaseUrl || !anonKey || !serviceKey || !accessToken) {
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

  const { data: operator, error: operatorError } = await admin
    .from("platform_operators")
    .select("user_id,display_name,active,can_recover_root,identity_email")
    .eq("user_id", actor.id)
    .eq("active", true)
    .maybeSingle();

  if (operatorError) {
    console.error("operator_lookup_failed", operatorError.message);
    return json(500, { error: "operator_lookup_failed" });
  }
  if (!operator) return json(403, { error: "platform_operator_required" });

  const actorEmail = String(actor.email || "").trim().toLowerCase();
  const identityEmail = String(operator.identity_email || "").trim().toLowerCase();
  if (!actorEmail || !identityEmail || actorEmail !== identityEmail) {
    return json(403, { error: "platform_operator_identity_email_mismatch" });
  }

  let body: { action?: string; request_id?: string; verification_note?: string; rejection_note?: string } = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const action = cleanText(body.action || "status", 32).toLowerCase();
  const payload = jwtPayload(accessToken);
  const aal = String(payload?.aal || "aal1");

  if (action === "status") {
    return json(200, {
      ok: true,
      operator: {
        user_id: actor.id,
        display_name: operator.display_name,
        can_recover_root: operator.can_recover_root === true,
      },
      aal,
      mfa_required: aal !== "aal2",
    });
  }

  if (aal !== "aal2") return json(403, { error: "aal2_required" });

  if (action === "list") {
    const since = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
    const { data: requests, error: requestError } = await admin
      .from("audit_log_v2")
      .select("id,organization_id,actor_user_id,entity_id,details,created_at")
      .eq("action", "mfa_recovery_requested")
      .eq("result", "pending")
      .gte("created_at", since)
      .order("created_at", { ascending: false })
      .limit(50);

    if (requestError) return json(500, { error: "recovery_request_lookup_failed" });

    const requestIds = (requests || [])
      .map(row => String(row.details?.request_id || ""))
      .filter(validUuid);

    const { data: terminalRows } = requestIds.length
      ? await admin
          .from("audit_log_v2")
          .select("action,details,created_at")
          .in("action", ["mfa_recovery_completed", "mfa_recovery_rejected"])
          .in("details->>request_id", requestIds)
      : { data: [] as Record<string, unknown>[] };

    const closed = new Set((terminalRows || []).map(row => String(row.details?.request_id || "")));
    const items: Record<string, unknown>[] = [];

    for (const row of requests || []) {
      const requestId = String(row.details?.request_id || "");
      if (!validUuid(requestId) || closed.has(requestId)) continue;
      const createdMs = new Date(row.created_at).getTime();
      if (!Number.isFinite(createdMs) || Date.now() - createdMs > 60 * 60 * 1000) continue;

      const targetUserId = String(row.entity_id || row.actor_user_id || "");
      if (!validUuid(targetUserId)) continue;
      const { data: targetData } = await admin.auth.admin.getUserById(targetUserId);
      const target = targetData?.user;
      if (!target) continue;
      const role = String(target.app_metadata?.role || "").toLowerCase();
      if (role !== "root" && role !== "admin") continue;

      items.push({
        request_id: requestId,
        target_user_id: targetUserId,
        email: String(target.email || ""),
        role,
        reason: String(row.details?.reason || "lost_authenticator_access"),
        verified_factor_count: Number(row.details?.verified_factor_count || 0),
        requested_at: row.created_at,
        expires_at: row.details?.expires_at || new Date(createdMs + 60 * 60 * 1000).toISOString(),
        self_request: targetUserId === actor.id,
        can_approve: targetUserId !== actor.id && (role !== "root" || operator.can_recover_root === true),
      });
    }

    return json(200, { ok: true, requests: items });
  }

  const requestId = String(body.request_id || "").trim();
  if (!validUuid(requestId)) return json(400, { error: "invalid_request_id" });

  const { data: rows, error: lookupError } = await admin
    .from("audit_log_v2")
    .select("organization_id,actor_user_id,entity_id,details,created_at")
    .eq("action", "mfa_recovery_requested")
    .eq("result", "pending")
    .contains("details", { request_id: requestId })
    .order("created_at", { ascending: false })
    .limit(1);

  if (lookupError) return json(500, { error: "recovery_request_lookup_failed" });
  const requestRow = rows?.[0];
  if (!requestRow) return json(404, { error: "recovery_request_not_found" });

  const ageMs = Date.now() - new Date(requestRow.created_at).getTime();
  if (!Number.isFinite(ageMs) || ageMs < 0 || ageMs > 60 * 60 * 1000) {
    return json(410, { error: "recovery_request_expired" });
  }

  const { data: terminal } = await admin
    .from("audit_log_v2")
    .select("action")
    .in("action", ["mfa_recovery_completed", "mfa_recovery_rejected"])
    .contains("details", { request_id: requestId })
    .limit(1);
  if ((terminal || []).length) return json(409, { error: "recovery_request_already_closed" });

  const targetUserId = String(requestRow.entity_id || requestRow.actor_user_id || "");
  if (!validUuid(targetUserId)) return json(409, { error: "recovery_request_invalid_target" });

  const { data: targetData, error: targetError } = await admin.auth.admin.getUserById(targetUserId);
  const target = targetData?.user;
  if (targetError || !target) return json(404, { error: "target_user_not_found" });
  const targetRole = String(target.app_metadata?.role || "").toLowerCase();
  if (targetRole !== "root" && targetRole !== "admin") return json(403, { error: "target_not_privileged" });

  if (action === "reject") {
    const rejectionNote = cleanText(body.rejection_note, 300);
    if (rejectionNote.length < 10) return json(400, { error: "rejection_note_required" });

    const { error: auditError } = await admin.from("audit_log_v2").insert({
      organization_id: requestRow.organization_id || null,
      actor_user_id: actor.id,
      action: "mfa_recovery_rejected",
      entity_type: "auth_user",
      entity_id: targetUserId,
      result: "rejected",
      details: {
        request_id: requestId,
        operator_user_id: actor.id,
        operator_display_name: operator.display_name,
        rejection_note: rejectionNote,
        rejected_at: new Date().toISOString(),
      },
    });
    if (auditError) return json(500, { error: "recovery_rejection_not_recorded" });
    return json(200, { ok: true, request_id: requestId, status: "rejected" });
  }

  if (action !== "approve") return json(400, { error: "unsupported_action" });
  if (targetUserId === actor.id) return json(403, { error: "self_approval_forbidden" });
  if (targetRole === "root" && operator.can_recover_root !== true) {
    return json(403, { error: "root_recovery_capability_required" });
  }

  const verificationNote = cleanText(body.verification_note, 500);
  if (verificationNote.length < 20) return json(400, { error: "verification_note_required" });

  const operatorReference = `platform:${actor.id}:${cleanText(operator.display_name, 80)}`;
  const recoveryResponse = await fetch(`${supabaseUrl}/functions/v1/recover-privileged-mfa`, {
    method: "POST",
    headers: adminHeaders(serviceKey),
    body: JSON.stringify({
      request_id: requestId,
      operator_reference: operatorReference,
      operator_user_id: actor.id,
      verification_note: verificationNote,
    }),
  });

  let recoveryBody: Record<string, unknown> = {};
  try {
    recoveryBody = await recoveryResponse.json();
  } catch {
    recoveryBody = {};
  }

  if (!recoveryResponse.ok) {
    console.error("operator_mfa_recovery_execution_failed", recoveryResponse.status, recoveryBody);
    return json(recoveryResponse.status, {
      error: String(recoveryBody.error || "recovery_execution_failed"),
      details: recoveryBody,
    });
  }

  return json(200, { ok: true, status: "completed", recovery: recoveryBody });
});
