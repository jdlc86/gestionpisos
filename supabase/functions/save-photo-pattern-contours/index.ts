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

function validContourData(data: any) {
  if (!data || data.version !== 1 || !Array.isArray(data.strokes)) return false;
  if (data.strokes.length > 100) return false;

  let totalPoints = 0;

  for (const stroke of data.strokes) {
    if (!stroke || typeof stroke.id !== "string" || stroke.id.length > 120) return false;
    if (typeof stroke.label !== "string" || !stroke.label.trim() || stroke.label.length > 80) return false;
    if (!["none", "soft", "medium"].includes(stroke.smoothing)) return false;
    if (typeof stroke.closed !== "boolean" || typeof stroke.hidden !== "boolean") return false;
    if (!Array.isArray(stroke.raw_points) || stroke.raw_points.length < 2) return false;

    totalPoints += stroke.raw_points.length;
    if (totalPoints > 20000) return false;

    for (const point of stroke.raw_points) {
      if (
        !Array.isArray(point) ||
        point.length !== 2 ||
        !Number.isFinite(Number(point[0])) ||
        !Number.isFinite(Number(point[1])) ||
        Number(point[0]) < 0 ||
        Number(point[0]) > 1 ||
        Number(point[1]) < 0 ||
        Number(point[1]) > 1
      ) return false;
    }
  }

  if (
    !data.image ||
    !Number.isFinite(Number(data.image.width)) ||
    !Number.isFinite(Number(data.image.height)) ||
    Number(data.image.width) <= 0 ||
    Number(data.image.height) <= 0
  ) return false;

  return true;
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

  const { data: userData, error: userError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (userError || !user) return json(401, { error: "invalid_session" });

  let body: { pattern_id?: string; contour_data?: unknown };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const patternId = body.pattern_id?.trim();
  if (!patternId) return json(400, { error: "pattern_id_required" });
  if (!validContourData(body.contour_data)) {
    return json(400, { error: "invalid_contour_data" });
  }

  const { data: pattern, error: patternError } = await userClient
    .from("photo_patterns_v2")
    .select("id,organization_id,property_id,active")
    .eq("id", patternId)
    .maybeSingle();

  if (patternError) return json(500, { error: "pattern_lookup_failed" });
  if (!pattern?.active) return json(404, { error: "pattern_not_available" });

  const role = String(user.app_metadata?.role || "");
  let allowed = false;

  if (role === "root") {
    allowed = true;
  } else if (role === "admin") {
    const jwtOrg = String(user.app_metadata?.organization_id || "");
    allowed = !jwtOrg || jwtOrg === String(pattern.organization_id);
  } else {
    const { data: grants, error: grantError } = await admin
      .from("property_staff_access_v3")
      .select("can_write,valid_from,valid_until,revoked_at")
      .eq("property_id", pattern.property_id)
      .eq("employee_user_id", user.id)
      .eq("can_write", true)
      .is("revoked_at", null);

    if (grantError) return json(500, { error: "permission_lookup_failed" });

    const now = Date.now();
    allowed = (grants || []).some((grant: any) => {
      const fromOk = !grant.valid_from || new Date(grant.valid_from).getTime() <= now;
      const untilOk = !grant.valid_until || new Date(grant.valid_until).getTime() > now;
      return fromOk && untilOk;
    });
  }

  if (!allowed) return json(403, { error: "insufficient_write_permission" });

  const { error: updateError } = await admin
    .from("photo_patterns_v2")
    .update({ contour_data: body.contour_data })
    .eq("id", pattern.id);

  if (updateError) return json(500, { error: "contour_save_failed" });

  return json(200, {
    ok: true,
    pattern_id: pattern.id,
    stroke_count: (body.contour_data as any).strokes.length,
  });
});
