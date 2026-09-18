import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { sendStaffOnboardingInvitation } from "../_shared/staff-onboarding-email.ts";

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

  let body: { target_user_id?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const targetUserId = String(body.target_user_id || "").trim();
  if (!targetUserId) return json(400, { error: "target_user_id_required" });

  const { data: organizationId, error: organizationError } = await userClient.rpc("get_effective_organization_id");
  if (organizationError || !organizationId) return json(403, { error: "organization_unavailable" });

  const { data: allowed, error: permissionError } = await userClient.rpc("can_manage_permissions", {
    p_organization_id: organizationId,
  });
  if (permissionError || allowed !== true) return json(403, { error: "permission_management_write_required" });

  const { data: onboarding, error: onboardingError } = await admin
    .from("internal_staff_onboarding")
    .select("user_id,organization_id,intended_role,status")
    .eq("user_id", targetUserId)
    .eq("organization_id", organizationId)
    .eq("status", "pending")
    .maybeSingle();
  if (onboardingError) return json(500, { error: "onboarding_lookup_failed" });
  if (!onboarding) return json(409, { error: "pending_onboarding_required" });

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("email,display_name,status,archived_at")
    .eq("user_id", targetUserId)
    .maybeSingle();
  if (profileError) return json(500, { error: "profile_lookup_failed" });
  if (!profile || profile.status !== "active" || profile.archived_at) {
    return json(409, { error: "active_profile_required" });
  }

  const email = String(profile.email || "").trim().toLowerCase();
  const displayName = String(profile.display_name || email || "Usuario").trim();
  if (!email) return json(409, { error: "profile_email_required" });

  try {
    const result = await sendStaffOnboardingInvitation(admin, {
      userId: targetUserId,
      organizationId,
      actorUserId: actor.id,
      email,
      displayName,
      role: onboarding.intended_role === "admin" ? "admin" : "employee",
    });

    if (result.status === "cooldown") {
      return json(429, {
        error: "invitation_cooldown",
        retry_after_seconds: result.retry_after_seconds || 60,
      });
    }

    return json(200, {
      ok: true,
      target_user_id: targetUserId,
      invitation_status: result.status,
    });
  } catch (error) {
    console.error(error);
    const message = String((error as Error)?.message || "");
    if (message.includes("internal_staff_invitation_email_mismatch")) {
      return json(409, { error: "internal_staff_invitation_email_mismatch" });
    }
    return json(500, { error: "invitation_send_failed" });
  }
});
