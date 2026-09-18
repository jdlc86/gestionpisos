import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { disableAndRevokeExternalOnboarding } from "../_shared/external-onboarding-revocation.ts";

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
  if (!supabaseUrl || !anonKey || !serviceKey || !authorization) return json(401, { error: "authentication_required" });

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: actorData, error: actorError } = await userClient.auth.getUser();
  const actor = actorData?.user;
  if (actorError || !actor) return json(401, { error: "invalid_session" });

  let body: { subject_type?: string; subject_id?: string; new_email?: string };
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }

  const subjectType = String(body.subject_type || "").trim();
  const subjectId = String(body.subject_id || "").trim();
  const newEmail = String(body.new_email ?? "").trim().toLowerCase();
  const emailValid = newEmail === "" ? subjectType === "owner" : newEmail.includes("@");
  if (!(["owner", "tenant"] as string[]).includes(subjectType) || !subjectId || !emailValid) {
    return json(400, { error: "invalid_subject_or_email" });
  }

  let organizationId = "";
  let currentEmail = "";
  let tenantPropertyIds: string[] = [];

  if (subjectType === "owner") {
    const { data, error } = await admin.from("owners")
      .select("id,organization_id,email,status,archived_at")
      .eq("id", subjectId).maybeSingle();
    if (error) return json(500, { error: "owner_lookup_failed" });
    if (!data || data.status !== "active" || data.archived_at) return json(409, { error: "owner_not_active" });
    organizationId = String(data.organization_id);
    currentEmail = String(data.email || "").trim().toLowerCase();
  } else {
    const { data, error } = await admin.from("tenants_v2")
      .select("id,organization_id,email,status,archived_at")
      .eq("id", subjectId).maybeSingle();
    if (error) return json(500, { error: "tenant_lookup_failed" });
    if (!data || data.status !== "active" || data.archived_at) return json(409, { error: "tenant_not_active" });
    organizationId = String(data.organization_id);
    currentEmail = String(data.email || "").trim().toLowerCase();

    const { data: occupancies, error: occupancyError } = await admin.from("occupancies_v2")
      .select("property_id")
      .eq("tenant_id", subjectId)
      .eq("organization_id", organizationId)
      .in("status", ["active", "blocked"]);
    if (occupancyError) return json(500, { error: "tenant_occupancy_lookup_failed" });
    tenantPropertyIds = [...new Set((occupancies || []).map((row) => String(row.property_id)).filter(Boolean))];
  }

  const { data: actorRoles, error: actorRoleError } = await admin.from("user_roles")
    .select("role,organization_id,revoked_at")
    .eq("user_id", actor.id).is("revoked_at", null);
  if (actorRoleError) return json(500, { error: "actor_role_lookup_failed" });

  const isRoot = (actorRoles || []).some((row) => row.role === "root");
  const isAdminHere = (actorRoles || []).some((row) => row.role === "admin" && row.organization_id === organizationId);
  const isEmployeeHere = (actorRoles || []).some((row) => row.role === "employee" && row.organization_id === organizationId);

  const { data: canManage } = await userClient.rpc("can_manage_permissions", { p_organization_id: organizationId });
  let authorized = canManage === true;
  if (!authorized && subjectType === "tenant" && isEmployeeHere && !isAdminHere) {
    for (const propertyId of tenantPropertyIds) {
      const { data: canWrite, error } = await userClient.rpc("can_operate_property_v3", { p_property_id: propertyId, p_require_write: true });
      if (!error && canWrite === true) { authorized = true; break; }
    }
  }
  if (!authorized && !isRoot) return json(403, { error: "external_welcome_permission_required" });

  const subjectColumn = subjectType === "owner" ? "owner_id" : "tenant_id";
  const { data: onboarding, error: onboardingError } = await admin.from("external_account_onboarding")
    .select("id,auth_user_id,status,email")
    .eq(subjectColumn, subjectId)
    .in("status", ["pending", "active"])
    .maybeSingle();
  if (onboardingError) return json(500, { error: "external_onboarding_lookup_failed" });

  if (!onboarding) {
    return json(200, { ok: true, revoked: false, reason: "no_pending_onboarding" });
  }
  if (onboarding.status === "active") {
    return json(409, { error: "external_active_account_email_change_requires_account_flow" });
  }

  const onboardingEmail = String(onboarding.email || "").trim().toLowerCase();
  if (newEmail === onboardingEmail) {
    return json(400, { error: "external_replacement_email_invalid" });
  }

  try {
    const result = await disableAndRevokeExternalOnboarding(admin, {
      authUserId: String(onboarding.auth_user_id),
      actorUserId: actor.id,
      replacementEmail: newEmail || null,
    });
    return json(200, {
      ok: true,
      revoked: true,
      subject_type: subjectType,
      subject_id: subjectId,
      old_email: onboardingEmail || currentEmail,
      replacement_email: newEmail,
      result,
    });
  } catch (error) {
    console.error(error);
    return json(500, { error: "external_onboarding_revoke_failed" });
  }
});
