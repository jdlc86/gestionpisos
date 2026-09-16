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
  if (!supabaseUrl || !anonKey || !serviceKey || !authorization) return json(401, { error: "authentication_required" });

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  const { data: actorData, error: actorError } = await userClient.auth.getUser();
  const actor = actorData?.user;
  if (actorError || !actor) return json(401, { error: "invalid_session" });

  const { data: onboarding, error: onboardingError } = await admin.from("external_account_onboarding")
    .select("id,organization_id,subject_type,owner_id,tenant_id,intended_role,status,email")
    .eq("auth_user_id", actor.id).in("status", ["pending", "active"])
    .order("created_at", { ascending: false }).limit(1).maybeSingle();
  if (onboardingError) return json(500, { error: "external_onboarding_lookup_failed" });
  if (!onboarding) return json(409, { error: "external_onboarding_not_found" });
  if (!(["owner", "tenant"] as string[]).includes(String(onboarding.intended_role))) {
    return json(409, { error: "invalid_external_onboarding_role" });
  }

  let completion: Record<string, unknown> = { ok: true, status: onboarding.status };
  if (onboarding.status !== "active") {
    const { data, error } = await admin.rpc("complete_external_account_onboarding", { p_auth_user_id: actor.id });
    if (error) {
      console.error(error);
      return json(500, { error: String(error.message || "database_external_activation_failed").slice(0,160) });
    }
    if (!data?.ok || data?.status !== "active") return json(500, { error: "database_external_activation_incomplete" });
    completion = data;
  }

  // The database linkage and role are authoritative. Auth claims are published only
  // after that succeeds, so a metadata failure can deny access but never grant it early.
  const { data: authData, error: authLookupError } = await admin.auth.admin.getUserById(actor.id);
  if (authLookupError || !authData?.user) return json(500, { error: "auth_user_lookup_failed", database_active: true });
  if (String(authData.user.email || "").trim().toLowerCase() !== String(onboarding.email || "").trim().toLowerCase()) {
    return json(409, { error: "external_auth_email_mismatch", database_active: true });
  }

  const currentMetadata = authData.user.app_metadata || {};
  const nextMetadata = {
    ...currentMetadata,
    role: String(onboarding.intended_role),
    organization_id: String(onboarding.organization_id),
  };
  const { error: metadataError } = await admin.auth.admin.updateUserById(actor.id, { app_metadata: nextMetadata });
  if (metadataError) {
    console.error(metadataError);
    return json(500, { error: "external_auth_metadata_sync_failed", database_active: true, retryable: true });
  }

  const subjectId = onboarding.subject_type === "owner" ? onboarding.owner_id : onboarding.tenant_id;
  const { error: auditError } = await admin.from("audit_log_v2").insert({
    organization_id: onboarding.organization_id,
    actor_user_id: actor.id,
    action: "sync_external_account_auth_metadata",
    entity_type: onboarding.subject_type,
    entity_id: String(subjectId || actor.id),
    result: "success",
    details: { role: onboarding.intended_role, organization_id: onboarding.organization_id },
  });
  if (auditError) console.error("external_metadata_audit_failed", auditError);

  return json(200, {
    ...completion, ok: true, status: "active", auth_metadata_synced: true,
    role: onboarding.intended_role, organization_id: onboarding.organization_id,
    subject_type: onboarding.subject_type, subject_id: subjectId,
  });
});
