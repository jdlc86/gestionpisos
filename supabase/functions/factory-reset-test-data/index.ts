import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://jdlc86.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const RESET_CONFIRMATION = "RESET_FACTORY_TEST_DATA";
const PREVIEW_TTL_MS = 5 * 60 * 1000;
const DATA_BUCKETS = ["photo-verification", "tenant-documents-v2"] as const;

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

function toBase64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function fromBase64Url(value: string) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(padded);
  return Uint8Array.from(binary, char => char.charCodeAt(0));
}

async function hmacKey(secret: string) {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function createPreviewToken(
  serviceKey: string,
  payload: Record<string, unknown>,
) {
  const body = toBase64Url(new TextEncoder().encode(JSON.stringify(payload)));
  const key = await hmacKey(serviceKey);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return `${body}.${toBase64Url(new Uint8Array(signature))}`;
}

async function verifyPreviewToken(serviceKey: string, token: string) {
  const [body, signature] = String(token || "").split(".");
  if (!body || !signature) return null;
  try {
    const key = await hmacKey(serviceKey);
    const ok = await crypto.subtle.verify(
      "HMAC",
      key,
      fromBase64Url(signature),
      new TextEncoder().encode(body),
    );
    if (!ok) return null;
    const payload = JSON.parse(new TextDecoder().decode(fromBase64Url(body)));
    return payload && typeof payload === "object" ? payload as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

async function listAllUsers(admin: ReturnType<typeof createClient>) {
  const users: Array<{ id?: string }> = [];
  for (let page = 1; page <= 100; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const batch = Array.isArray(data?.users) ? data.users : [];
    users.push(...batch);
    if (batch.length < 1000) break;
  }
  return users;
}

async function resolveRootOrganization(
  admin: ReturnType<typeof createClient>,
  actorId: string,
) {
  const { data: roles, error: roleError } = await admin
    .from("user_roles")
    .select("organization_id,role,revoked_at")
    .eq("user_id", actorId)
    .is("revoked_at", null);

  if (roleError) throw new Error("root_organization_lookup_failed");
  const rootOrganizationIds = [...new Set(
    (roles || [])
      .filter(row => String(row.role || "").toLowerCase() === "root")
      .map(row => String(row.organization_id || ""))
      .filter(validUuid),
  )];

  if (rootOrganizationIds.length !== 1) throw new Error("root_organization_required");
  const organizationId = rootOrganizationIds[0];

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("organization_id,status")
    .eq("user_id", actorId)
    .eq("organization_id", organizationId)
    .eq("status", "active")
    .maybeSingle();

  if (profileError || !profile) throw new Error("root_organization_required");
  return organizationId;
}

async function verifiedFactorCount(supabaseUrl: string, serviceKey: string, userId: string) {
  const response = await fetch(`${supabaseUrl}/auth/v1/admin/users/${userId}/factors`, {
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
  });
  if (!response.ok) throw new Error("factory_reset_operator_factor_lookup_failed");
  const body = await response.json();
  const factors = Array.isArray(body) ? body : [];
  return factors.filter((factor: Record<string, unknown>) => factor?.status === "verified").length;
}

async function resolveProtectedBaseline(
  admin: ReturnType<typeof createClient>,
  actorId: string,
  organizationId: string,
  supabaseUrl: string,
  serviceKey: string,
) {
  const { data: operators, error: operatorError } = await admin
    .from("platform_operators")
    .select("user_id,display_name,active,can_recover_root")
    .eq("active", true)
    .eq("can_recover_root", true);

  if (operatorError) throw new Error("factory_reset_operator_lookup_failed");
  if (!Array.isArray(operators) || operators.length !== 1) {
    throw new Error("factory_reset_requires_one_root_recovery_operator");
  }

  const operator = operators[0];
  const operatorUserId = String(operator.user_id || "");
  if (!validUuid(operatorUserId) || operatorUserId === actorId) {
    throw new Error("factory_reset_invalid_operator_identity");
  }

  const { data: operatorData, error: operatorAuthError } = await admin.auth.admin.getUserById(operatorUserId);
  if (operatorAuthError || !operatorData?.user) throw new Error("factory_reset_operator_auth_missing");
  const factorCount = await verifiedFactorCount(supabaseUrl, serviceKey, operatorUserId);
  if (factorCount < 1) throw new Error("factory_reset_operator_mfa_required");

  return {
    root_user_id: actorId,
    organization_id: organizationId,
    operator_user_id: operatorUserId,
    operator_email: String(operatorData.user.email || ""),
    operator_verified_factor_count: factorCount,
  };
}

async function availableDataBuckets(admin: ReturnType<typeof createClient>) {
  const { data, error } = await admin.storage.listBuckets();
  if (error) throw error;
  const existing = new Set((data || []).map(bucket => bucket.id));
  return DATA_BUCKETS.filter(bucket => existing.has(bucket));
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

  let organizationId = "";
  try {
    organizationId = await resolveRootOrganization(admin, actor.id);
  } catch (error) {
    return json(409, { error: String((error as Error)?.message || "root_organization_required") });
  }

  const claimedOrganizationId = String(actor.app_metadata?.organization_id || "");
  if (claimedOrganizationId && validUuid(claimedOrganizationId) && claimedOrganizationId !== organizationId) {
    return json(409, { error: "root_organization_claim_mismatch" });
  }

  let body: { action?: string; confirmation?: string; preview_token?: string } = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  const action = String(body.action || "preview").trim().toLowerCase();

  let baseline;
  try {
    baseline = await resolveProtectedBaseline(admin, actor.id, organizationId, supabaseUrl, serviceKey);
  } catch (error) {
    return json(409, { error: String((error as Error)?.message || "factory_reset_baseline_invalid") });
  }

  if (action === "preview") {
    try {
      const users = await listAllUsers(admin);
      const protectedIds = new Set([baseline.root_user_id, baseline.operator_user_id]);
      const buckets = await availableDataBuckets(admin);
      const expiresAt = Date.now() + PREVIEW_TTL_MS;
      const previewToken = await createPreviewToken(serviceKey, {
        root_user_id: baseline.root_user_id,
        operator_user_id: baseline.operator_user_id,
        organization_id: baseline.organization_id,
        expires_at_ms: expiresAt,
        nonce: crypto.randomUUID(),
      });

      return json(200, {
        ok: true,
        action: "preview",
        protected_users: [
          { user_id: baseline.root_user_id, email: String(actor.email || ""), kind: "root" },
          { user_id: baseline.operator_user_id, email: baseline.operator_email, kind: "platform_operator" },
        ],
        auth_users_total: users.length,
        auth_users_to_delete: users.filter(user => !protectedIds.has(String(user.id || ""))).length,
        storage_buckets_to_empty: buckets,
        historical_audit_will_be_cleared: true,
        reset_receipt_will_remain: true,
        static_workflow_templates_preserved: true,
        preview_token: previewToken,
        preview_expires_at: new Date(expiresAt).toISOString(),
      });
    } catch (error) {
      console.error("factory_reset_preview_failed", String((error as Error)?.message || error));
      return json(500, { error: "factory_reset_preview_failed" });
    }
  }

  if (action !== "execute") return json(400, { error: "unsupported_action" });
  if (body.confirmation !== RESET_CONFIRMATION) return json(400, { error: "factory_reset_confirmation_required" });

  const preview = await verifyPreviewToken(serviceKey, String(body.preview_token || ""));
  if (!preview) return json(400, { error: "factory_reset_preview_token_invalid" });
  if (Number(preview.expires_at_ms || 0) < Date.now()) return json(410, { error: "factory_reset_preview_expired" });
  if (
    String(preview.root_user_id || "") !== baseline.root_user_id ||
    String(preview.operator_user_id || "") !== baseline.operator_user_id ||
    String(preview.organization_id || "") !== baseline.organization_id
  ) {
    return json(409, { error: "factory_reset_baseline_changed" });
  }

  const emptiedBuckets: string[] = [];
  try {
    const buckets = await availableDataBuckets(admin);
    for (const bucket of buckets) {
      const { error } = await admin.storage.emptyBucket(bucket);
      if (error) throw new Error(`storage_empty_failed:${bucket}:${error.message}`);
      emptiedBuckets.push(bucket);
    }
  } catch (error) {
    console.error("factory_reset_storage_failed", String((error as Error)?.message || error));
    return json(500, {
      error: "factory_reset_storage_failed",
      emptied_buckets: emptiedBuckets,
    });
  }

  let databaseReset: Record<string, unknown> = {};
  try {
    const { data, error } = await admin.rpc("factory_reset_test_data_service", {
      p_actor_user_id: baseline.root_user_id,
      p_operator_user_id: baseline.operator_user_id,
      p_organization_id: baseline.organization_id,
    });
    if (error) throw error;
    databaseReset = (data || {}) as Record<string, unknown>;
  } catch (error) {
    console.error("factory_reset_database_failed", String((error as Error)?.message || error));
    return json(500, {
      error: "factory_reset_database_failed",
      storage_already_emptied: emptiedBuckets,
    });
  }

  const deletedAuthUsers: string[] = [];
  try {
    const users = await listAllUsers(admin);
    const protectedIds = new Set([baseline.root_user_id, baseline.operator_user_id]);
    for (const user of users) {
      const userId = String(user.id || "");
      if (!validUuid(userId) || protectedIds.has(userId)) continue;
      const { error } = await admin.auth.admin.deleteUser(userId, false);
      if (error) throw new Error(`auth_delete_failed:${userId}:${error.message}`);
      deletedAuthUsers.push(userId);
    }
  } catch (error) {
    console.error("factory_reset_auth_cleanup_failed", String((error as Error)?.message || error));
    return json(500, {
      error: "factory_reset_auth_cleanup_partial",
      database_reset: databaseReset,
      storage_emptied: emptiedBuckets,
      deleted_auth_user_count: deletedAuthUsers.length,
    });
  }

  try {
    const remainingUsers = await listAllUsers(admin);
    const remainingIds = new Set(remainingUsers.map(user => String(user.id || "")));
    const expectedIds = new Set([baseline.root_user_id, baseline.operator_user_id]);
    const exactProtectedUsersRemain =
      remainingUsers.length === 2 &&
      [...expectedIds].every(userId => remainingIds.has(userId));

    if (!exactProtectedUsersRemain) {
      return json(500, {
        error: "factory_reset_postcondition_failed",
        remaining_auth_user_count: remainingUsers.length,
        deleted_auth_user_count: deletedAuthUsers.length,
      });
    }

    return json(200, {
      ok: true,
      status: "completed",
      database_reset: databaseReset,
      storage_buckets_emptied: emptiedBuckets,
      deleted_auth_user_count: deletedAuthUsers.length,
      remaining_auth_user_count: remainingUsers.length,
      preserved_root_user_id: baseline.root_user_id,
      preserved_operator_user_id: baseline.operator_user_id,
      reset_receipt_preserved: true,
    });
  } catch (error) {
    console.error("factory_reset_postcondition_check_failed", String((error as Error)?.message || error));
    return json(500, { error: "factory_reset_postcondition_check_failed" });
  }
});
