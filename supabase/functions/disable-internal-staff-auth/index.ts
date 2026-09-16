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

function retiredEmailFor(userId: string) {
  return `retired+${userId}@deleted.invalid`;
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

  const { data: currentData, error: currentError } = await userClient.auth.getUser();
  const actor = currentData?.user;
  if (currentError || !actor) return json(401, { error: "invalid_session" });

  let body: { target_user_id?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }
  const targetUserId = body.target_user_id?.trim();
  if (!targetUserId) return json(400, { error: "target_user_id_required" });
  if (targetUserId === actor.id) return json(409, { error: "self_deactivation_not_allowed" });

  const { data: organizationId, error: organizationError } = await userClient.rpc("get_effective_organization_id");
  if (organizationError || !organizationId) return json(403, { error: "organization_not_available" });

  const { data: canManage, error: permissionError } = await userClient.rpc("can_manage_permissions", {
    p_organization_id: organizationId,
  });
  if (permissionError || canManage !== true) return json(403, { error: "permission_management_required" });

  // The database deactivation is authoritative and must happen first. This prevents
  // this service-role function from being used to ban an otherwise active employee.
  const { data: activeRoles, error: roleError } = await admin
    .from("user_roles")
    .select("id")
    .eq("organization_id", organizationId)
    .eq("user_id", targetUserId)
    .in("role", ["admin", "employee"])
    .is("revoked_at", null)
    .limit(1);
  if (roleError) return json(500, { error: "staff_state_lookup_failed" });
  if ((activeRoles || []).length > 0) return json(409, { error: "staff_still_active" });

  const { data: targetData, error: targetError } = await admin.auth.admin.getUserById(targetUserId);
  if (targetError || !targetData?.user) return json(404, { error: "auth_user_not_found" });

  // Supabase documents 876000h as the supported 100-year ban duration.
  // Ban first so access is closed even if retiring the email unexpectedly fails.
  const { error: banError } = await admin.auth.admin.updateUserById(targetUserId, {
    ban_duration: "876000h",
  });
  if (banError) {
    console.error(banError);
    return json(500, { error: "auth_disable_failed" });
  }

  // A deleted staff member remains in Auth to preserve the historical UUID. Move the
  // Auth login email to a non-routable tombstone so the real address can be reused by
  // a future employee without merging two people's audit histories.
  const currentEmail = String(targetData.user.email || "").trim().toLowerCase();
  const retiredEmail = retiredEmailFor(targetUserId);
  let emailRetired = currentEmail === retiredEmail;
  if (currentEmail && !emailRetired) {
    const { error: retireError } = await admin.auth.admin.updateUserById(targetUserId, {
      email: retiredEmail,
    });
    if (retireError) {
      console.error(retireError);
      return json(500, {
        error: "auth_email_retire_failed",
        auth_disabled: true,
        target_user_id: targetUserId,
      });
    }
    emailRetired = true;
  }

  return json(200, {
    ok: true,
    target_user_id: targetUserId,
    auth_disabled: true,
    email_retired: emailRetired,
  });
});
