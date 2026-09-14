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

function toBase64(bytes: Uint8Array) {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function interactionText(payload: any) {
  const chunks: string[] = [];
  for (const step of Array.isArray(payload?.steps) ? payload.steps : []) {
    if (step?.type !== "model_output") continue;
    for (const part of Array.isArray(step?.content) ? step.content : []) {
      if (part?.type === "text" && typeof part.text === "string") chunks.push(part.text);
    }
  }
  return chunks.join("\n").trim();
}

function validMask(item: any) {
  return !!item &&
    typeof item.label === "string" &&
    Array.isArray(item.box_2d) &&
    item.box_2d.length === 4 &&
    item.box_2d.every((v: unknown) => Number.isFinite(Number(v))) &&
    Array.isArray(item.mask) &&
    item.mask.length >= 3 &&
    item.mask.every((p: unknown) =>
      Array.isArray(p) &&
      p.length === 2 &&
      Number.isFinite(Number(p[0])) &&
      Number.isFinite(Number(p[1]))
    );
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const geminiKey = Deno.env.get("CONTORNO_GEMINI_API_KEY");
  if (!geminiKey) return json(503, { error: "gemini_secret_missing" });

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

  const role = String(user.app_metadata?.role || "");
  if (role !== "root" && role !== "admin") {
    return json(403, { error: "insufficient_role" });
  }

  let body: { pattern_id?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const patternId = body.pattern_id?.trim();
  if (!patternId) return json(400, { error: "pattern_id_required" });

  const { data: pattern, error: patternError } = await userClient
    .from("photo_patterns_v2")
    .select("id,name,target_key,reference_storage_path,active,organization_id")
    .eq("id", patternId)
    .maybeSingle();

  if (patternError) return json(500, { error: "pattern_lookup_failed" });
  if (!pattern?.active || !pattern.reference_storage_path) {
    return json(404, { error: "pattern_not_available" });
  }

  const { data: blob, error: downloadError } = await admin.storage
    .from("photo-verification")
    .download(pattern.reference_storage_path);

  if (downloadError || !blob) return json(500, { error: "reference_download_failed" });
  if (blob.size > 5_000_000) return json(413, { error: "reference_too_large" });

  const bytes = new Uint8Array(await blob.arrayBuffer());
  const imageBase64 = toBase64(bytes);
  const mimeType = blob.type || "image/jpeg";

  const prompt = [
    "Create a clean visual alignment guide for retaking this room photograph from the same viewpoint.",
    "Segment only stable, visually distinctive structures and large recognizable objects that define the scene geometry.",
    "Prefer doors, windows, cabinets, countertops, large appliances, tables, fixed shelving, bed or sofa outlines, ceiling fans or large fans, and other dominant objects.",
    "Ignore shadows, reflections, highlights, light gradients, wall or floor texture, grout lines, decorative patterns, small clutter, cables, people, clothing, plants and tiny objects.",
    "Return 3 to 8 landmarks maximum.",
    "Each chosen landmark must remain recognizable from its silhouette and be useful for camera alignment.",
    "Preserve distinctive object silhouettes such as fan blades rather than reducing them to a coarse blob.",
    "Use short Spanish labels."
  ].join(" ");

  const response = await fetch("https://generativelanguage.googleapis.com/v1beta/interactions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": geminiKey,
    },
    body: JSON.stringify({
      model: "gemini-3.6-flash",
      input: [
        { type: "text", text: prompt },
        { type: "image", mime_type: mimeType, data: imageBase64 }
      ],
      response_format: {
        type: "text",
        mime_type: "application/json",
        schema: {
          type: "object",
          properties: {
            boxes: {
              type: "array",
              minItems: 1,
              maxItems: 8,
              items: {
                type: "object",
                properties: {
                  box_2d: {
                    type: "array",
                    minItems: 4,
                    maxItems: 4,
                    items: { type: "integer", minimum: 0, maximum: 1000 }
                  },
                  mask: {
                    type: "array",
                    minItems: 3,
                    items: {
                      type: "array",
                      minItems: 2,
                      maxItems: 2,
                      items: { type: "integer", minimum: 0, maximum: 1000 }
                    }
                  },
                  label: { type: "string" }
                },
                required: ["box_2d", "mask", "label"],
                additionalProperties: false
              }
            }
          },
          required: ["boxes"],
          additionalProperties: false
        }
      },
      generation_config: {
        thinking_level: "minimal"
      }
    }),
  });

  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    console.error("Gemini request failed", response.status, payload);
    return json(502, { error: "gemini_request_failed", status: response.status });
  }

  const text = interactionText(payload);
  if (!text) return json(502, { error: "gemini_empty_response" });

  let parsed: any;
  try {
    parsed = JSON.parse(text);
  } catch {
    return json(502, { error: "gemini_invalid_json" });
  }

  const boxes = Array.isArray(parsed?.boxes)
    ? parsed.boxes.filter(validMask).slice(0, 8)
    : [];

  if (!boxes.length) return json(422, { error: "gemini_no_structural_landmarks" });

  return json(200, {
    ok: true,
    model: "gemini-3.6-flash",
    pattern: {
      id: pattern.id,
      name: pattern.name,
      zone: pattern.target_key,
      reference_storage_path: pattern.reference_storage_path,
    },
    boxes,
  });
});
