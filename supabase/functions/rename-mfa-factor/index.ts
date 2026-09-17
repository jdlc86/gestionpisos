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

function normalizeName(value: unknown) {
  return String(value ?? "").trim().replace(/\s+/g, " ").slice(0, 50);
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

function adminAuthHeaders(serviceKey: string) {
  return {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get(["SUPABASE", "SERVICE", "ROLE", "KEY"].join("_"));
  const authorization = req.headers.get("Authorization") || "";
  if (!supabaseUrl || !anonKey || !serviceKey || !authorization) {
    return json(401, { error: "authentication_required" });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  const actor = userData?.user;
  if (userError || !actor) return json(401, { error: "invalid_session" });

  const role = String(actor.app_metadata?.role || "").toLowerCase();
  if (role !== "root" && role !== "admin") return json(403, { error: "privileged_role_required" });

  const payload = jwtPayload(bearerToken(authorization));
  if (String(payload?.aal || "") !== "aal2") return json(403, { error: "aal2_required" });

  let body: { factor_id?: string; friendly_name?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const factorId = String(body.factor_id || "").trim();
  const friendlyName = normalizeName(body.friendly_name);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(factorId)) {
    return json(400, { error: "invalid_factor_id" });
  }
  if (!friendlyName) return json(400, { error: "friendly_name_required" });

  const headers = adminAuthHeaders(serviceKey);
  const listResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users/${actor.id}/factors`, { headers });
  if (!listResponse.ok) {
    console.error("mfa_factor_list_failed", listResponse.status);
    return json(502, { error: "factor_lookup_failed" });
  }

  const factors = await listResponse.json();
  const list = Array.isArray(factors) ? factors : [];
  const factor = list.find((item: Record<string, unknown>) => item?.id === factorId);
  if (!factor || factor.status !== "verified") return json(404, { error: "verified_factor_not_found" });

  const duplicate = list.some((item: Record<string, unknown>) =>
    item?.id !== factorId &&
    String(item?.friendly_name || "").trim().toLowerCase() === friendlyName.toLowerCase()
  );
  if (duplicate) return json(409, { error: "friendly_name_conflict" });

  const updateResponse = await fetch(`${supabaseUrl}/auth/v1/admin/users/${actor.id}/factors/${factorId}`, {
    method: "PUT",
    headers,
    body: JSON.stringify({ friendly_name: friendlyName }),
  });

  if (!updateResponse.ok) {
    const text = await updateResponse.text();
    console.error("mfa_factor_update_failed", updateResponse.status, text.slice(0, 300));
    if (updateResponse.status === 409 || updateResponse.status === 422) {
      return json(409, { error: "friendly_name_conflict" });
    }
    return json(502, { error: "factor_update_failed" });
  }

  return json(200, { ok: true, factor_id: factorId, friendly_name: friendlyName });
});
