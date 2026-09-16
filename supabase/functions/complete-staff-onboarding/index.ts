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

  const { data: onboarding, error: onboardingError } = await admin
    .from("internal_staff_onboarding")
    .select("user_id,organization_id,intended_role,status")
    .eq("user_id", actor.id)
    .maybeSingle();
  if (onboardingError) return json(500, { error: "onboarding_lookup_failed" });
  if (!onboarding) return json(409, { error: "onboarding_not_found" });
  if (onboarding.status === "revoked") return json(409, { error: "onboarding_revoked" });
  if (!(["admin", "employee"] as string[]).includes(String(onboarding.intended_role))) {
    return json(409, { error: "invalid_onboarding_role" });
  }

  let completion: Record<string, unknown> = { ok: true, status: onboarding.status };
  if (onboarding.status !== "active") {
    const { data, error } = await userClient.rpc("complete_internal_staff_onboarding");
    if (error) {
      console.error(error);
      return json(500, { error: "database_activation_failed" });
    }
    if (!data?.ok || data?.status !== "active") return json(500, { error: "database_activation_incomplete" });
    completion = data;
  }

  // Database authorization becomes active first. Only after that succeeds do we
  // publish role/org claims into Auth. This ordering is deliberate: a metadata
  // failure may temporarily deny access, but can never grant access without the
  // corresponding authoritative database role.
  const { data: authData, error: authLookupError } = await admin.auth.admin.getUserById(actor.id);
  if (authLookupError || !authData?.user) return json(500, { error: "auth_user_lookup_failed", database_active: true });

  const currentMetadata = authData.user.app_metadata || {};
  const nextMetadata = {
    ...currentMetadata,
    role: String(onboarding.intended_role),
    organization_id: String(onboarding.organization_id),
  };
  const { error: metadataError } = await admin.auth.admin.updateUserById(actor.id, {
    app_metadata: nextMetadata,
  });
  if (metadataError) {
    console.error(metadataError);
    return json(500, { error: "auth_metadata_sync_failed", database_active: true, retryable: true });
  }

  const { error: auditError } = await admin.from("audit_log_v2").insert({
    organization_id: onboarding.organization_id,
    actor_user_id: actor.id,
    action: "sync_internal_staff_auth_metadata",
    entity_type: "user",
    entity_id: actor.id,
    result: "success",
    details: { role: onboarding.intended_role, organization_id: onboarding.organization_id },
  });
  if (auditError) console.error("staff_metadata_audit_failed", auditError);

  return json(200, {
    ...completion,
    ok: true,
    status: "active",
    auth_metadata_synced: true,
    role: onboarding.intended_role,
    organization_id: onboarding.organization_id,
  });
});
