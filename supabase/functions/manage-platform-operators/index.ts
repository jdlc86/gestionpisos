import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://jdlc86.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const OPERATIONAL_ROLES = new Set(["root", "admin", "employee", "owner", "tenant"]);

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
  return String(value ?? "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function cleanEmail(value: unknown) {
  return String(value ?? "").trim().toLowerCase().slice(0, 254);
}

function adminHeaders(serviceKey: string) {
  return {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };
}

async function findUserByEmail(admin: ReturnType<typeof createClient>, email: string) {
  for (let page = 1; page <= 20; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const users = Array.isArray(data?.users) ? data.users : [];
    const match = users.find(user => String(user.email || "").trim().toLowerCase() === email);
    if (match) return match;
    if (users.length < 1000) break;
  }
  return null;
}

async function verifiedFactorCount(supabaseUrl: string, serviceKey: string, userId: string) {
  const response = await fetch(`${supabaseUrl}/auth/v1/admin/users/${userId}/factors`, {
    headers: adminHeaders(serviceKey),
  });
  if (!response.ok) return null;
  const body = await response.json();
  const factors = Array.isArray(body) ? body : [];
  return factors.filter((factor: Record<string, unknown>) => factor?.status === "verified").length;
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

  const role = String(actor.app_metadata?.role || "").toLowerCase();
  if (role !== "root") return json(403, { error: "root_required" });

  const payload = jwtPayload(accessToken);
  if (String(payload?.aal || "") !== "aal2") return json(403, { error: "aal2_required" });

  let body: {
    action?: string;
    email?: string;
    display_name?: string;
    target_user_id?: string;
    active?: boolean;
    can_recover_root?: boolean;
  } = {};
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const action = cleanText(body.action || "list", 32).toLowerCase();
  const organizationId = validUuid(actor.app_metadata?.organization_id) ? String(actor.app_metadata.organization_id) : null;

  async function activeRootRecoveryCount() {
    const { count, error } = await admin
      .from("platform_operators")
      .select("user_id", { count: "exact", head: true })
      .eq("active", true)
      .eq("can_recover_root", true);
    if (error) throw error;
    return Number(count || 0);
  }

  async function mutateOperator(input: {
    mutationAction: "upsert" | "update";
    targetUserId: string;
    displayName: string;
    active: boolean;
    canRecoverRoot: boolean;
    email: string;
  }) {
    const { data, error } = await admin.rpc("manage_platform_operator_service", {
      p_action: input.mutationAction,
      p_target_user_id: input.targetUserId,
      p_display_name: input.displayName,
      p_active: input.active,
      p_can_recover_root: input.canRecoverRoot,
      p_actor_user_id: actor.id,
      p_organization_id: organizationId,
      p_email: input.email,
    });
    if (error) {
      console.error("platform_operator_atomic_mutation_failed", error.message);
      throw new Error("operator_mutation_failed");
    }
    return data as Record<string, unknown>;
  }

  if (action === "list") {
    const { data: rows, error } = await admin
      .from("platform_operators")
      .select("user_id,display_name,active,can_recover_root,created_at,updated_at")
      .order("created_at", { ascending: true });
    if (error) return json(500, { error: "operator_list_failed" });

    const operators: Record<string, unknown>[] = [];
    for (const row of rows || []) {
      const { data: targetData } = await admin.auth.admin.getUserById(row.user_id);
      const target = targetData?.user;
      const factorCount = target ? await verifiedFactorCount(supabaseUrl, serviceKey, row.user_id) : null;
      operators.push({
        ...row,
        email: String(target?.email || ""),
        auth_user_exists: Boolean(target),
        mfa_ready: typeof factorCount === "number" ? factorCount > 0 : null,
        verified_factor_count: factorCount,
      });
    }

    return json(200, {
      ok: true,
      operators,
      active_root_recovery_count: await activeRootRecoveryCount(),
    });
  }

  if (action === "add") {
    const email = cleanEmail(body.email);
    const displayName = cleanText(body.display_name, 120);
    const canRecoverRoot = body.can_recover_root !== false;
    if (!email || !email.includes("@")) return json(400, { error: "valid_email_required" });
    if (displayName.length < 2) return json(400, { error: "display_name_required" });

    let target;
    try {
      target = await findUserByEmail(admin, email);
    } catch (error) {
      console.error("platform_operator_user_lookup_failed", String(error));
      return json(500, { error: "auth_user_lookup_failed" });
    }
    if (!target) return json(404, { error: "auth_user_not_found" });
    if (target.id === actor.id) return json(403, { error: "self_operator_forbidden" });
    if (!target.email_confirmed_at) return json(409, { error: "operator_email_not_confirmed" });

    const targetRole = String(target.app_metadata?.role || "").toLowerCase();
    if (OPERATIONAL_ROLES.has(targetRole)) {
      return json(409, { error: "dedicated_platform_identity_required" });
    }

    try {
      const result = await mutateOperator({
        mutationAction: "upsert",
        targetUserId: target.id,
        displayName,
        active: true,
        canRecoverRoot,
        email,
      });
      return json(200, {
        ...result,
        operator: {
          user_id: target.id,
          email,
          display_name: displayName,
          active: true,
          can_recover_root: canRecoverRoot,
        },
      });
    } catch (error) {
      return json(500, { error: String((error as Error)?.message || "operator_mutation_failed") });
    }
  }

  if (action === "update") {
    const targetUserId = String(body.target_user_id || "").trim();
    if (!validUuid(targetUserId)) return json(400, { error: "invalid_target_user_id" });
    if (targetUserId === actor.id) return json(403, { error: "self_operator_forbidden" });

    const { data: existing, error: existingError } = await admin
      .from("platform_operators")
      .select("user_id,display_name,active,can_recover_root")
      .eq("user_id", targetUserId)
      .maybeSingle();
    if (existingError) return json(500, { error: "operator_lookup_failed" });
    if (!existing) return json(404, { error: "operator_not_found" });

    const displayName = body.display_name === undefined ? existing.display_name : cleanText(body.display_name, 120);
    if (String(displayName).trim().length < 2) return json(400, { error: "display_name_required" });
    const active = typeof body.active === "boolean" ? body.active : existing.active;
    const canRecoverRoot = typeof body.can_recover_root === "boolean" ? body.can_recover_root : existing.can_recover_root;
    const { data: targetData } = await admin.auth.admin.getUserById(targetUserId);
    const target = targetData?.user;
    if (!target) return json(404, { error: "auth_user_not_found" });
    const targetRole = String(target.app_metadata?.role || "").toLowerCase();
    if (OPERATIONAL_ROLES.has(targetRole)) {
      return json(409, { error: "dedicated_platform_identity_required" });
    }

    try {
      const result = await mutateOperator({
        mutationAction: "update",
        targetUserId,
        displayName,
        active,
        canRecoverRoot,
        email: String(target.email || ""),
      });
      return json(200, result);
    } catch (error) {
      return json(500, { error: String((error as Error)?.message || "operator_mutation_failed") });
    }
  }

  return json(400, { error: "unsupported_action" });
});
