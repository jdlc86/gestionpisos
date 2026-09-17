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

function validUuid(value: unknown) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || ""));
}

function cleanText(value: unknown, maxLength: number) {
  return String(value || "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function emergencyPassword() {
  return `Aa1!${crypto.randomUUID().replaceAll("-", "")}Zz9#`;
}

function adminAuthHeaders(serviceKey: string) {
  return {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };
}

async function listFactors(supabaseUrl: string, serviceKey: string, userId: string) {
  const response = await fetch(`${supabaseUrl}/auth/v1/admin/users/${userId}/factors`, {
    headers: adminAuthHeaders(serviceKey),
  });
  if (!response.ok) throw new Error(`factor_lookup_failed:${response.status}`);
  const payload = await response.json();
  return Array.isArray(payload) ? payload : [];
}

async function audit(
  admin: ReturnType<typeof createClient>,
  data: {
    organization_id?: string | null;
    action: string;
    entity_id: string;
    result: string;
    details: Record<string, unknown>;
  },
) {
  const { error } = await admin.from("audit_log_v2").insert({
    organization_id: data.organization_id || null,
    actor_user_id: null,
    action: data.action,
    entity_type: "auth_user",
    entity_id: data.entity_id,
    result: data.result,
    details: data.details,
  });
  if (error) console.error("mfa_recovery_audit_failed", data.action, error.message);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get(["SUPABASE", "SERVICE", "ROLE", "KEY"].join("_"));
  const authorization = req.headers.get("Authorization") || "";
  const callerToken = bearerToken(authorization);

  if (!supabaseUrl || !serviceKey || !callerToken) return json(401, { error: "authentication_required" });
  if (callerToken !== serviceKey) return json(403, { error: "platform_operator_required" });

  let body: { request_id?: string; operator_reference?: string; verification_note?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const requestId = String(body.request_id || "").trim();
  const operatorReference = cleanText(body.operator_reference, 80);
  const verificationNote = cleanText(body.verification_note, 300);

  if (!validUuid(requestId)) return json(400, { error: "invalid_request_id" });
  if (operatorReference.length < 3) return json(400, { error: "operator_reference_required" });
  if (verificationNote.length < 10) return json(400, { error: "verification_note_required" });

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: requests, error: requestError } = await admin
    .from("audit_log_v2")
    .select("organization_id,actor_user_id,entity_id,details,created_at")
    .eq("action", "mfa_recovery_requested")
    .eq("result", "pending")
    .contains("details", { request_id: requestId })
    .order("created_at", { ascending: false })
    .limit(1);

  if (requestError) return json(500, { error: "recovery_request_lookup_failed" });
  const requestRow = requests?.[0];
  if (!requestRow) return json(404, { error: "recovery_request_not_found" });

  const targetUserId = String(requestRow.entity_id || requestRow.actor_user_id || "");
  if (!validUuid(targetUserId)) return json(409, { error: "recovery_request_invalid_target" });

  const ageMs = Date.now() - new Date(requestRow.created_at).getTime();
  if (!Number.isFinite(ageMs) || ageMs < 0 || ageMs > 60 * 60 * 1000) {
    return json(410, { error: "recovery_request_expired" });
  }

  const { data: terminalRows } = await admin
    .from("audit_log_v2")
    .select("action")
    .in("action", ["mfa_recovery_completed", "mfa_recovery_rejected"])
    .contains("details", { request_id: requestId })
    .limit(1);
  if ((terminalRows || []).length) return json(409, { error: "recovery_request_already_closed" });

  const { data: partialRows } = await admin
    .from("audit_log_v2")
    .select("details,created_at")
    .eq("action", "mfa_recovery_partial")
    .contains("details", { request_id: requestId })
    .order("created_at", { ascending: false })
    .limit(1);
  const previousPartial = partialRows?.[0]?.details || {};
  let sessionsRevoked = previousPartial?.sessions_revoked === true;
  let passwordRotated = previousPartial?.password_rotated === true;

  const { data: userData, error: userError } = await admin.auth.admin.getUserById(targetUserId);
  const target = userData?.user;
  if (userError || !target) return json(404, { error: "target_user_not_found" });

  const role = String(target.app_metadata?.role || "").toLowerCase();
  if (role !== "root" && role !== "admin") return json(403, { error: "target_not_privileged" });

  let factors: Record<string, unknown>[];
  try {
    factors = await listFactors(supabaseUrl, serviceKey, targetUserId);
  } catch (error) {
    console.error(error);
    return json(502, { error: "factor_lookup_failed" });
  }

  if (!sessionsRevoked) {
    const firstVerified = factors.find(factor => factor?.status === "verified");
    if (!firstVerified || !firstVerified.id) return json(409, { error: "verified_factor_missing" });

    const { error: firstDeleteError } = await admin.auth.admin.mfa.deleteFactor({
      userId: targetUserId,
      id: String(firstVerified.id),
    });
    if (firstDeleteError) {
      console.error("mfa_recovery_first_factor_delete_failed", firstDeleteError.message);
      return json(502, { error: "session_revocation_failed" });
    }
    sessionsRevoked = true;
  }

  if (!passwordRotated) {
    const { error: passwordError } = await admin.auth.admin.updateUserById(targetUserId, {
      password: emergencyPassword(),
    });
    if (passwordError) {
      await audit(admin, {
        organization_id: requestRow.organization_id,
        action: "mfa_recovery_partial",
        entity_id: targetUserId,
        result: "partial",
        details: {
          request_id: requestId,
          operator_reference: operatorReference,
          sessions_revoked: sessionsRevoked,
          password_rotated: false,
          stage: "password_rotation_failed",
        },
      });
      return json(502, { error: "password_rotation_failed", sessions_revoked: sessionsRevoked });
    }
    passwordRotated = true;
  }

  try {
    factors = await listFactors(supabaseUrl, serviceKey, targetUserId);
  } catch (error) {
    console.error(error);
    await audit(admin, {
      organization_id: requestRow.organization_id,
      action: "mfa_recovery_partial",
      entity_id: targetUserId,
      result: "partial",
      details: {
        request_id: requestId,
        operator_reference: operatorReference,
        sessions_revoked: sessionsRevoked,
        password_rotated: passwordRotated,
        stage: "post_lock_factor_lookup_failed",
      },
    });
    return json(502, { error: "factor_lookup_failed", sessions_revoked: sessionsRevoked, password_rotated: passwordRotated });
  }

  let removedFactorCount = 0;
  const deleteErrors: string[] = [];
  for (const factor of factors) {
    const id = String(factor?.id || "");
    if (!validUuid(id)) continue;
    const { error } = await admin.auth.admin.mfa.deleteFactor({ userId: targetUserId, id });
    if (error) deleteErrors.push(id);
    else removedFactorCount += 1;
  }

  if (deleteErrors.length) {
    await audit(admin, {
      organization_id: requestRow.organization_id,
      action: "mfa_recovery_partial",
      entity_id: targetUserId,
      result: "partial",
      details: {
        request_id: requestId,
        operator_reference: operatorReference,
        sessions_revoked: sessionsRevoked,
        password_rotated: passwordRotated,
        stage: "factor_cleanup_partial",
        removed_factor_count: removedFactorCount,
        failed_factor_count: deleteErrors.length,
      },
    });
    return json(502, {
      error: "factor_cleanup_partial",
      sessions_revoked: sessionsRevoked,
      password_rotated: passwordRotated,
      removed_factor_count: removedFactorCount,
      failed_factor_count: deleteErrors.length,
    });
  }

  let recoveryEmailSent = false;
  let recoveryEmailError = "";
  const targetEmail = String(target.email || "").trim().toLowerCase();
  if (targetEmail) {
    const { error: emailError } = await admin.auth.resetPasswordForEmail(targetEmail, {
      redirectTo: "https://jdlc86.github.io/gestionpisos/reset-password.html",
    });
    if (emailError) recoveryEmailError = emailError.message;
    else recoveryEmailSent = true;
  } else {
    recoveryEmailError = "target_email_missing";
  }

  await audit(admin, {
    organization_id: requestRow.organization_id,
    action: "mfa_recovery_completed",
    entity_id: targetUserId,
    result: "success",
    details: {
      request_id: requestId,
      operator_reference: operatorReference,
      verification_note: verificationNote,
      target_role: role,
      sessions_revoked: sessionsRevoked,
      password_rotated: passwordRotated,
      removed_factor_count: removedFactorCount + (previousPartial?.sessions_revoked === true ? 0 : 1),
      recovery_email_sent: recoveryEmailSent,
      recovery_email_error: recoveryEmailError || null,
      completed_at: new Date().toISOString(),
    },
  });

  return json(200, {
    ok: true,
    request_id: requestId,
    target_user_id: targetUserId,
    sessions_revoked: sessionsRevoked,
    password_rotated: passwordRotated,
    factors_cleared: true,
    recovery_email_sent: recoveryEmailSent,
    manual_password_recovery_required: !recoveryEmailSent,
  });
});
