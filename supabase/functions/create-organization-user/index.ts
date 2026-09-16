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

function isDuplicateUserError(error: { message?: string } | null) {
  const message = String(error?.message || "").toLowerCase();
  return message.includes("already") || message.includes("registered") || message.includes("exists");
}

async function retireArchivedEmailOwner(
  admin: ReturnType<typeof createClient>,
  organizationId: string,
  email: string,
) {
  const { data: archivedProfiles, error: profileError } = await admin
    .from("profiles")
    .select("user_id")
    .eq("email", email)
    .eq("status", "archived")
    .limit(50);
  if (profileError) throw new Error("archived_profile_lookup_failed");

  for (const profile of archivedProfiles || []) {
    const userId = String(profile.user_id || "");
    if (!userId) continue;

    const { data: roleRows, error: roleError } = await admin
      .from("user_roles")
      .select("role,organization_id,revoked_at")
      .eq("user_id", userId);
    if (roleError) throw new Error("archived_role_lookup_failed");

    const rows = roleRows || [];
    const hasActiveRole = rows.some((row) => row.revoked_at == null);
    const wasInternalStaffHere = rows.some(
      (row) =>
        row.organization_id === organizationId &&
        (row.role === "admin" || row.role === "employee") &&
        row.revoked_at != null,
    );
    if (hasActiveRole || !wasInternalStaffHere) continue;

    const { data: authData, error: authError } = await admin.auth.admin.getUserById(userId);
    const authUser = authData?.user;
    if (authError || !authUser || authUser.deleted_at) continue;
    if (String(authUser.email || "").trim().toLowerCase() !== email) continue;

    // Only reclaim an address from an account that was actually disabled by the
    // staff-deactivation flow. This prevents taking an email from another live user.
    const bannedUntil = Date.parse(String(authUser.banned_until || ""));
    if (!Number.isFinite(bannedUntil) || bannedUntil <= Date.now()) continue;

    const { error: retireError } = await admin.auth.admin.updateUserById(userId, {
      email: retiredEmailFor(userId),
      ban_duration: "876000h",
    });
    if (retireError) throw new Error("archived_auth_email_retire_failed");
    return true;
  }

  return false;
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

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: currentData, error: currentError } = await userClient.auth.getUser();
  const actor = currentData?.user;
  if (currentError || !actor) return json(401, { error: "invalid_session" });

  let body: { email?: string; display_name?: string; role?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const email = String(body.email || "").trim().toLowerCase();
  const displayName = String(body.display_name || "").trim();
  const role = String(body.role || "employee");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !displayName || !["admin", "employee"].includes(role)) {
    return json(400, { error: "invalid_input" });
  }

  const { data: organizationId, error: organizationError } = await userClient.rpc("get_effective_organization_id");
  if (organizationError || !organizationId) return json(403, { error: "organization_unavailable" });

  const { data: allowed, error: permissionError } = await userClient.rpc("can_manage_permissions", {
    p_organization_id: organizationId,
  });
  if (permissionError || allowed !== true) return json(403, { error: "permission_management_write_required" });

  let reclaimedArchivedEmail = false;
  let { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    user_metadata: { display_name: displayName },
  });

  if (createError && isDuplicateUserError(createError)) {
    try {
      reclaimedArchivedEmail = await retireArchivedEmailOwner(admin, organizationId, email);
    } catch (error) {
      console.error(error);
      return json(500, { error: String((error as Error)?.message || "archived_email_reclaim_failed") });
    }

    if (reclaimedArchivedEmail) {
      const retry = await admin.auth.admin.createUser({
        email,
        email_confirm: true,
        user_metadata: { display_name: displayName },
      });
      created = retry.data;
      createError = retry.error;
    }
  }

  if (createError || !created?.user) {
    if (isDuplicateUserError(createError)) return json(409, { error: "email_in_use" });
    return json(500, { error: "auth_user_create_failed" });
  }

  const userId = created.user.id;
  const { error: provisionError } = await admin.rpc("provision_employee_profile_role", {
    p_user_id: userId,
    p_email: email,
    p_display_name: displayName,
    p_organization_id: organizationId,
    p_role: role,
  });

  if (provisionError) {
    await admin.auth.admin.deleteUser(userId).catch(() => {});
    return json(500, { error: "profile_role_provision_failed" });
  }

  return json(201, {
    user: { id: userId, email, display_name: displayName, role },
    reclaimed_archived_email: reclaimedArchivedEmail,
  });
});
