import { supabase, getCurrentUser } from "./supabase-client.js";

const pageMode = new URLSearchParams(window.location.search).get("mode");

const message = document.getElementById("cameraMessage");
const params = new URLSearchParams(window.location.search);

function uuidLike(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value || "");
}

function captureContext() {
  const patternId = params.get("pattern_id");
  const roomId = params.get("room_id");
  const sourceType = params.get("source_type") || "manual";
  const sourceId = params.get("source_id");

  if (!uuidLike(patternId)) return null;
  if (roomId && !uuidLike(roomId)) return null;
  if (!["manual","cleaning_task","random_request"].includes(sourceType)) return null;
  if (sourceType !== "manual" && !uuidLike(sourceId)) return null;
  if (sourceType === "manual" && sourceId) return null;

  return {
    patternId,
    roomId: roomId || null,
    sourceType,
    sourceId: sourceId || null
  };
}

function setMessage(text) {
  if (message) message.textContent = text;
}

async function persistCapture(detail) {
  const context = captureContext();
  if (!context) {
    setMessage("Fotografía capturada localmente. Falta un patrón real para guardarla.");
    return;
  }

  const user = await getCurrentUser();

  const { data: pattern, error: patternError } = await supabase
    .from("photo_patterns_v2")
    .select("id,organization_id,property_id,active")
    .eq("id", context.patternId)
    .maybeSingle();

  if (patternError) throw patternError;
  if (!pattern || !pattern.active) throw new Error("pattern_not_available");

  const { data: run, error: runError } = await supabase
    .from("photo_verification_runs_v2")
    .insert({
      organization_id: pattern.organization_id,
      property_id: pattern.property_id,
      room_id: context.roomId,
      actor_user_id: user.id,
      source_type: context.sourceType,
      source_id: context.sourceId,
      verification_mode: "manual",
      status: "capturing"
    })
    .select("id,organization_id,property_id,status")
    .single();

  if (runError) throw runError;

  const itemId = crypto.randomUUID();
  const storagePath = `${run.organization_id}/${run.id}/${itemId}.jpg`;
  const alignmentScore = Number.isFinite(detail.alignmentScore)
    ? Math.max(0, Math.min(1, detail.alignmentScore))
    : null;

  const alignmentMeta = {
    algorithm: "local-edge-v2",
    zones: Array.isArray(detail.alignmentZones) ? detail.alignmentZones : null,
    texture_penalty: Number.isFinite(detail.texturePenalty) ? detail.texturePenalty : null,
    width: detail.width || null,
    height: detail.height || null
  };

  const { error: itemError } = await supabase
    .from("photo_verification_items_v2")
    .insert({
      id: itemId,
      run_id: run.id,
      pattern_id: pattern.id,
      storage_path: storagePath,
      alignment_score: alignmentScore,
      alignment_meta: alignmentMeta
    });

  if (itemError) throw itemError;

  const { error: uploadError } = await supabase.storage
    .from("photo-verification")
    .upload(storagePath, detail.blob, {
      contentType: "image/jpeg",
      cacheControl: "3600",
      upsert: false
    });

  if (uploadError) throw uploadError;

  const { data: submitted, error: submitError } = await supabase.functions.invoke(
    "submit-photo-verification",
    { body: { run_id: run.id, item_id: itemId } }
  );

  if (submitError) throw submitError;
  if (!submitted?.ok) throw new Error("submit_failed");

  setMessage("Fotoverificación enviada correctamente.");
  window.__allaisoLastPhotoRun = {
    runId: run.id,
    itemId,
    storagePath,
    alignmentScore
  };
}

window.addEventListener("allaiso:photo-captured", event => {
  if (pageMode === "pattern") return;
  const detail = event.detail;
  if (!detail?.blob) return;

  queueMicrotask(async () => {
    try {
      setMessage("Guardando fotoverificación…");
      await persistCapture(detail);
    } catch (error) {
      console.error("photo persistence failed", error);
      setMessage("La foto no se pudo enviar. No se marcó como completada.");
    }
  });
});
