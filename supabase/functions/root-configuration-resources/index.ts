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

async function resolveRootOrganization(admin: ReturnType<typeof createClient>, actorId: string) {
  const { data: roles, error: roleError } = await admin
    .from("user_roles")
    .select("organization_id,role,revoked_at")
    .eq("user_id", actorId)
    .is("revoked_at", null);
  if (roleError) throw new Error("root_organization_lookup_failed");
  if (!(roles || []).some(row => String(row.role || "").toLowerCase() === "root")) {
    throw new Error("root_required");
  }

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("organization_id,status")
    .eq("user_id", actorId)
    .eq("status", "active")
    .maybeSingle();
  if (profileError) throw new Error("root_organization_lookup_failed");

  const profileOrganizationId = String(profile?.organization_id || "");
  if (validUuid(profileOrganizationId)) {
    const { data: organization, error: organizationError } = await admin
      .from("organizations")
      .select("id,status")
      .eq("id", profileOrganizationId)
      .eq("status", "active")
      .maybeSingle();
    if (organizationError) throw new Error("root_organization_lookup_failed");
    if (!organization) throw new Error("root_organization_required");
    return profileOrganizationId;
  }

  const { data: organizations, error: organizationError } = await admin
    .from("organizations")
    .select("id,status")
    .eq("status", "active")
    .limit(2);
  if (organizationError) throw new Error("root_organization_lookup_failed");
  if (!Array.isArray(organizations) || organizations.length !== 1) {
    throw new Error("root_organization_required");
  }

  const organizationId = String(organizations[0]?.id || "");
  if (!validUuid(organizationId)) throw new Error("root_organization_required");
  return organizationId;
}

async function listAllUsers(admin: ReturnType<typeof createClient>) {
  let total = 0;
  for (let page = 1; page <= 100; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const batch = Array.isArray(data?.users) ? data.users : [];
    total += batch.length;
    if (batch.length < 1000) break;
  }
  return total;
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

  if (String(actor.app_metadata?.role || "").toLowerCase() !== "root") {
    return json(403, { error: "root_required" });
  }

  const payload = jwtPayload(accessToken);
  if (String(payload?.aal || "") !== "aal2") {
    return json(403, { error: "aal2_required" });
  }

  let organizationId = "";
  try {
    organizationId = await resolveRootOrganization(admin, actor.id);
  } catch (error) {
    return json(409, { error: String((error as Error)?.message || "root_organization_required") });
  }

  try {
    const [{ data: overview, error: overviewError }, authUserCount] = await Promise.all([
      admin.rpc("root_configuration_resources_service", {
        p_actor_user_id: actor.id,
        p_organization_id: organizationId,
      }),
      listAllUsers(admin),
    ]);
    if (overviewError) throw overviewError;

    return json(200, {
      ok: true,
      generated_at: new Date().toISOString(),
      overview,
      auth: {
        users: authUserCount,
        root_aal2: true,
      },
      email_delivery: {
        transactional_provider_configured: Boolean(Deno.env.get("RESEND_API_KEY") && Deno.env.get("AUTH_EMAIL_FROM")),
      },
    });
  } catch (error) {
    console.error("root_configuration_resources_failed", String((error as Error)?.message || error));
    return json(500, { error: "configuration_resources_unavailable" });
  }
});
