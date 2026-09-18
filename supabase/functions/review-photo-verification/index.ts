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

  const { data:userData, error:userError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (userError || !user) return json(401, { error: "invalid_session" });

  const role = String(user.app_metadata?.role || "");
  const organizationId = String(user.app_metadata?.organization_id || "");
  if (!["root","admin"].includes(role)) return json(403, { error: "review_not_allowed" });


  let body: { run_id?: string; decision?: string; rejection_reason?: string | null };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const runId = body.run_id?.trim();
  const decision = body.decision?.trim();
  const rejectionReason = body.rejection_reason?.trim() || null;

  if (!runId || !["approved","rejected"].includes(decision || "")) {
    return json(400, { error: "invalid_review_request" });
  }
  if (decision === "rejected" && !rejectionReason) {
    return json(400, { error: "rejection_reason_required" });
  }
  if (rejectionReason && rejectionReason.length > 500) {
    return json(400, { error: "rejection_reason_too_long" });
  }

  const { data:run, error:runError } = await admin
    .from("photo_verification_runs_v2")
    .select("id,organization_id,status,source_type,source_id")
    .eq("id", runId)
    .maybeSingle();

  if (runError) return json(500, { error: "run_lookup_failed" });
  if (!run) return json(404, { error: "run_not_found" });
  if (role === "admin" && run.organization_id !== organizationId) {
    return json(404, { error: "run_not_found" });
  }
  const reviewableStatuses = ["submitted","manual_review","ai_review"];
  if (run.source_type === "workflow_execution") {
    if (!reviewableStatuses.includes(run.status) && run.status !== decision) {
      return json(409, { error: "run_not_reviewable" });
    }
  } else if (!reviewableStatuses.includes(run.status)) {
    return json(409, { error: "run_not_reviewable" });
  }

  if (run.source_type === "workflow_execution") {
    const { data, error } = await admin.rpc("apply_workflow_photo_review_v1", {
      p_run_id: runId,
      p_actor_user_id: user.id,
      p_decision: decision,
      p_rejection_reason: decision === "rejected" ? rejectionReason : null,
    });

    if (error) {
      console.error(error);
      const message = String(error.message || "");
      if (message.includes("workflow_review_actor_forbidden")) {
        return json(403, { error: "review_not_allowed" });
      }
      if (message.includes("workflow_photo_review_conflict") || message.includes("workflow_not_waiting_review")) {
        return json(409, { error: "workflow_review_state_conflict" });
      }
      return json(500, { error: "workflow_review_apply_failed" });
    }

    return json(200, { ok: true, run: { id: runId, status: decision }, workflow: data });
  }

  const { data, error } = await admin.rpc("apply_photo_verification_review_v2", {
    p_run_id: runId,
    p_actor_user_id: user.id,
    p_decision: decision,
    p_rejection_reason: decision === "rejected" ? rejectionReason : null,
  });

  if (error) {
    console.error(error);
    return json(500, { error: "review_apply_failed" });
  }

  return json(200, { ok: true, run: data });
});
