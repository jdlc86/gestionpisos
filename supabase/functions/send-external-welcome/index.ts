import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { sendExternalOnboardingInvitation } from "../_shared/external-onboarding-email.ts";
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

function duplicateAuthError(error: { message?: string } | null) {
  const text = String(error?.message || "").toLowerCase();
  return text.includes("already") || text.includes("registered") || text.includes("exists");
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

  let body: { subject_type?: string; subject_id?: string };
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const subjectType = String(body.subject_type || "").trim();
  const subjectId = String(body.subject_id || "").trim();
  if (!(["owner", "tenant"] as string[]).includes(subjectType) || !subjectId) return json(400, { error: "invalid_subject" });

  let organizationId = "";
  let email = "";
  let displayName = "";
  let linkedUserId: string | null = null;
  let tenantPropertyIds: string[] = [];

  if (subjectType === "owner") {
    const { data, error } = await admin.from("owners")
      .select("id,organization_id,user_id,full_name,email,status,archived_at")
      .eq("id", subjectId).maybeSingle();
    if (error) return json(500, { error: "owner_lookup_failed" });
    if (!data || data.status !== "active" || data.archived_at) return json(409, { error: "owner_not_active" });
    organizationId = String(data.organization_id);
    email = String(data.email || "").trim().toLowerCase();
    displayName = String(data.full_name || email || "Propietario").trim();
    linkedUserId = data.user_id ? String(data.user_id) : null;
    if (!email) return json(409, { error: "owner_email_required" });
  } else {
    const { data, error } = await admin.from("tenants_v2")
      .select("id,organization_id,user_id,full_name,email,status,archived_at")
      .eq("id", subjectId).maybeSingle();
    if (error) return json(500, { error: "tenant_lookup_failed" });
    if (!data || data.status !== "active" || data.archived_at) return json(409, { error: "tenant_not_active" });
    organizationId = String(data.organization_id);
    email = String(data.email || "").trim().toLowerCase();
    displayName = String(data.full_name || email || "Inquilino").trim();
    linkedUserId = data.user_id ? String(data.user_id) : null;
    const { data: occupancies, error: occupancyError } = await admin.from("occupancies_v2")
      .select("property_id")
      .eq("tenant_id", subjectId)
      .eq("organization_id", organizationId)
      .in("status", ["active", "blocked"]);
    if (occupancyError) return json(500, { error: "tenant_occupancy_lookup_failed" });
    tenantPropertyIds = [...new Set((occupancies || []).map((row) => String(row.property_id)).filter(Boolean))];
    if (!tenantPropertyIds.length) return json(409, { error: "tenant_occupancy_required" });
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
  const { data: existingData, error: existingError } = await admin.from("external_account_onboarding")
    .select("id,auth_user_id,status,email,last_delivery_status")
    .eq(subjectColumn, subjectId)
    .in("status", ["pending", "active"])
    .maybeSingle();
  if (existingError) return json(500, { error: "external_onboarding_lookup_failed" });
  let existing = existingData;
  if (existing?.status === "active" || linkedUserId) return json(409, { error: "external_account_already_active" });

  if (existing?.status === "pending" && String(existing.email || "").trim().toLowerCase() !== email) {
    try {
      await disableAndRevokeExternalOnboarding(admin, {
        authUserId: String(existing.auth_user_id),
        actorUserId: actor.id,
        replacementEmail: email,
      });
      existing = null;
    } catch (error) {
      console.error(error);
      return json(500, { error: "external_stale_onboarding_revoke_failed" });
    }
  }

  let authUserId = existing?.auth_user_id ? String(existing.auth_user_id) : "";

  if (!existing) {
    const { data: externalEmail, error: externalEmailError } = await admin.from("external_account_onboarding")
      .select("id,subject_type,owner_id,tenant_id")
      .eq("email", email).in("status", ["pending", "active"]).limit(1);
    if (externalEmailError) return json(500, { error: "external_email_lookup_failed" });
    if ((externalEmail || []).length) return json(409, { error: "email_external_identity_conflict" });

    const { data: profiles, error: profileError } = await admin.from("profiles")
      .select("user_id,status,archived_at")
      .eq("email", email).limit(20);
    if (profileError) return json(500, { error: "identity_profile_lookup_failed" });
    for (const profile of profiles || []) {
      if (profile.status !== "active" || profile.archived_at) continue;
      const userId = String(profile.user_id);
      const { data: internal } = await admin.from("internal_staff_onboarding")
        .select("status").eq("user_id", userId).in("status", ["pending", "active"]).limit(1);
      const { data: roles } = await admin.from("user_roles")
        .select("id").eq("user_id", userId).is("revoked_at", null).limit(1);
      if ((internal || []).length || (roles || []).length) return json(409, { error: "email_internal_identity_conflict" });
    }

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email, email_confirm: true, user_metadata: { display_name: displayName },
    });
    if (createError || !created?.user) {
      if (duplicateAuthError(createError)) return json(409, { error: "email_auth_identity_conflict" });
      return json(500, { error: "external_auth_user_create_failed" });
    }
    authUserId = created.user.id;

    const { error: provisionError } = await admin.rpc("provision_external_account_pending", {
      p_auth_user_id: authUserId,
      p_subject_type: subjectType,
      p_subject_id: subjectId,
      p_created_by: actor.id,
    });
    if (provisionError) {
      console.error(provisionError);
      await admin.auth.admin.deleteUser(authUserId).catch(() => {});
      return json(500, { error: "external_onboarding_provision_failed" });
    }
  }

  try {
    const invitation = await sendExternalOnboardingInvitation(admin, {
      authUserId, actorUserId: actor.id, email, displayName,
      subjectType: subjectType === "owner" ? "owner" : "tenant",
    });
    if (invitation.status === "cooldown") {
      return json(429, { error: "invitation_cooldown", retry_after_seconds: invitation.retry_after_seconds || 60 });
    }
    return json(200, {
      ok: true, subject_type: subjectType, subject_id: subjectId,
      onboarding_status: "pending", invitation_status: invitation.status,
      created_identity: !existing,
    });
  } catch (error) {
    console.error(error);
    return json(500, { error: "external_invitation_send_failed" });
  }
});
