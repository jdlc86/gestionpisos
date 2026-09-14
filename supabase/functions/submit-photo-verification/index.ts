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
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
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

  let body: { run_id?: string; item_id?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const runId = body.run_id?.trim();
  const itemId = body.item_id?.trim();
  if (!runId || !itemId) return json(400, { error: "run_id_and_item_id_required" });

  const { data: run, error: runError } = await admin
    .from("photo_verification_runs_v2")
    .select("id,organization_id,actor_user_id,status")
    .eq("id", runId)
    .maybeSingle();

  if (runError) return json(500, { error: "run_lookup_failed" });
  if (!run || run.actor_user_id !== user.id) return json(404, { error: "run_not_found" });
  if (run.status !== "capturing") return json(409, { error: "run_not_capturing" });

  const { data: item, error: itemError } = await admin
    .from("photo_verification_items_v2")
    .select("id,run_id,storage_path")
    .eq("id", itemId)
    .eq("run_id", runId)
    .maybeSingle();

  if (itemError) return json(500, { error: "item_lookup_failed" });
  if (!item) return json(404, { error: "item_not_found" });

  const expectedPath = `${run.organization_id}/${run.id}/${item.id}.jpg`;
  if (item.storage_path !== expectedPath) {
    return json(409, { error: "invalid_storage_path" });
  }

  const folder = `${run.organization_id}/${run.id}`;
  const filename = `${item.id}.jpg`;
  const { data: objects, error: storageError } = await admin.storage
    .from("photo-verification")
    .list(folder, { limit: 2, search: filename });

  if (storageError) return json(500, { error: "storage_lookup_failed" });
  const object = objects?.find((entry) => entry.name === filename);
  if (!object) return json(409, { error: "photo_object_missing" });

  const submittedAt = new Date().toISOString();
  const { data: updated, error: updateError } = await admin
    .from("photo_verification_runs_v2")
    .update({ status: "submitted", submitted_at: submittedAt })
    .eq("id", runId)
    .eq("actor_user_id", user.id)
    .eq("status", "capturing")
    .select("id,status,submitted_at")
    .maybeSingle();

  if (updateError) return json(500, { error: "submit_failed" });
  if (!updated) return json(409, { error: "run_changed" });

  await admin.from("audit_log_v2").insert({
    organization_id: run.organization_id,
    actor_user_id: user.id,
    action: "submit_photo_verification",
    entity_type: "photo_verification_run",
    entity_id: run.id,
    result: "success",
    details: { item_id: item.id },
  });

  return json(200, { ok: true, run: updated });
});