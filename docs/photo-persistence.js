import { supabase, getCurrentUser } from "./supabase-client.js";

const params = new URLSearchParams(window.location.search);
const pageMode = params.get("mode");
const workflowResourceId = params.get("workflow_resource_id");
const message = document.getElementById("cameraMessage");

function uuidLike(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value || "");
}

function setMessage(text) {
  if (message) message.textContent = text;
}

function configureWorkflowCameraUi() {
  if (!workflowResourceId) return;
  const back = document.querySelector(".topbar a.ghost");
  const title = document.querySelector("h1");
  const heroTitle = document.querySelector(".hero h2");
  const heroText = document.querySelector(".hero p");

  if (back) {
    back.href = "./workflow-tasks.html";
    back.textContent = "Volver a Tareas";
  }
  if (title) title.textContent = "Evidencia fotográfica";
  if (heroTitle) heroTitle.textContent = "Completa la fotografía requerida por la tarea.";
  if (heroText) heroText.textContent = "La guía corresponde a la versión congelada al crear la ejecución. Enviar la captura actualizará la tarea y la ejecución en servidor.";
}

function captureContext() {
  const patternId = params.get("pattern_id");
  const roomId = params.get("room_id");
  const sourceType = params.get("source_type") || "manual";
  const sourceId = params.get("source_id");
  const purpose = params.get("purpose") || (sourceType === "cleaning_task" ? "cleaning" : "general");

  if (!uuidLike(patternId)) return null;

  if (workflowResourceId) {
    if (!uuidLike(workflowResourceId)) return null;
    if (sourceType !== "workflow_execution" || !uuidLike(sourceId)) return null;
    return {
      patternId,
      roomId: null,
      sourceType: "workflow_execution",
      sourceId,
      purpose: "general",
      cleaningTaskId: null,
      workflowResourceId
    };
  }

  if (roomId && !uuidLike(roomId)) return null;
  if (!["manual","cleaning_task","random_request"].includes(sourceType)) return null;
  if (sourceType !== "manual" && !uuidLike(sourceId)) return null;
  if (sourceType === "manual" && sourceId) return null;
  if (!["general","cleaning","maintenance","state"].includes(purpose)) return null;
  if (purpose === "cleaning" && sourceType !== "cleaning_task") return null;
  if (sourceType === "cleaning_task" && purpose !== "cleaning") return null;

  return {
    patternId,
    roomId: roomId || null,
    sourceType,
    sourceId: sourceId || null,
    purpose,
    cleaningTaskId: purpose === "cleaning" ? sourceId : null,
    workflowResourceId: null
  };
}

function workflowSubmitKey(resourceId, runId) {
  const storageKey = "workflow-photo-submit:" + resourceId + ":" + runId;
  let key = sessionStorage.getItem(storageKey);
  if (!key) {
    key = globalThis.crypto?.randomUUID?.() || ("photo-" + Date.now() + "-" + Math.random().toString(36).slice(2));
    sessionStorage.setItem(storageKey, key);
  }
  return { storageKey, key };
}

async function startWorkflowRun(context) {
  const { data, error } = await supabase.rpc("start_workflow_photo_verification_v1", {
    p_execution_photo_resource_id: context.workflowResourceId
  });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : null;
  if (!row?.run_id || row.pattern_id !== context.patternId) throw new Error("workflow_photo_start_invalid");
  return {
    id: row.run_id,
    organization_id: row.organization_id,
    property_id: row.property_id,
    room_id: row.room_id,
    pattern_id: row.pattern_id
  };
}

async function startLegacyRun(context, user) {
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
      purpose: context.purpose,
      cleaning_task_id: context.cleaningTaskId,
      status: "capturing"
    })
    .select("id,organization_id,property_id,room_id,status")
    .single();

  if (runError) throw runError;
  return { ...run, pattern_id: pattern.id };
}

async function submitWorkflowRun(context, run, itemId) {
  const { storageKey, key } = workflowSubmitKey(context.workflowResourceId, run.id);
  const { data, error } = await supabase.rpc("submit_workflow_photo_verification_v1", {
    p_run_id: run.id,
    p_item_id: itemId,
    p_request_key: key
  });

  if (error) throw error;
  sessionStorage.removeItem(storageKey);

  const result = Array.isArray(data) ? data[0] : null;
  if (!result) throw new Error("workflow_photo_submit_invalid");
  return result;
}

async function persistCapture(detail) {
  const context = captureContext();
  if (!context) {
    setMessage("Fotografía capturada localmente. Falta un contexto válido para guardarla.");
    return;
  }

  const user = await getCurrentUser();
  const run = context.workflowResourceId
    ? await startWorkflowRun(context)
    : await startLegacyRun(context, user);

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
      pattern_id: run.pattern_id || context.patternId,
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

  let workflowResult = null;

  if (context.workflowResourceId) {
    workflowResult = await submitWorkflowRun(context, run, itemId);
  } else {
    const { data: submitted, error: submitError } = await supabase.functions.invoke(
      "submit-photo-verification",
      { body: { run_id: run.id, item_id: itemId } }
    );

    if (submitError) throw submitError;
    if (!submitted?.ok) throw new Error("submit_failed");
  }

  if (context.workflowResourceId) {
    const status = workflowResult?.execution_status;
    if (status === "completed") {
      setMessage("Foto enviada. Tarea y ejecución completadas.");
    } else if (status === "waiting_review") {
      setMessage("Foto enviada. La ejecución queda pendiente de revisión.");
    } else if (workflowResult?.all_photos_complete) {
      setMessage("Foto enviada. Quedan otros pasos de la receta pendientes.");
    } else {
      setMessage("Foto enviada. Quedan fotografías pendientes en esta tarea.");
    }
  } else {
    setMessage(context.purpose === "cleaning"
      ? "Foto de limpieza enviada correctamente."
      : "Fotoverificación enviada correctamente.");
  }

  window.__allaisoLastPhotoRun = {
    runId: run.id,
    itemId,
    storagePath,
    alignmentScore,
    workflowResourceId: context.workflowResourceId || null,
    workflowResult
  };
}

configureWorkflowCameraUi();

window.addEventListener("allaiso:photo-captured", event => {
  if (pageMode === "pattern") return;
  const detail = event.detail;
  if (!detail?.blob) return;

  queueMicrotask(async () => {
    try {
      setMessage(workflowResourceId ? "Guardando evidencia del flujo…" : "Guardando fotoverificación…");
      await persistCapture(detail);
    } catch (error) {
      console.error("photo persistence failed", error);
      const code = String(error?.message || "");
      if (code.includes("workflow_photo_accept_required")) {
        setMessage("Debes aceptar primero la tarea antes de realizar esta fotografía.");
      } else if (code.includes("workflow_photo_already_submitted")) {
        setMessage("Esta fotografía ya fue enviada. Vuelve a Tareas.");
      } else if (code.includes("workflow_photo_actor_forbidden")) {
        setMessage("Esta evidencia solo puede realizarla la persona asignada.");
      } else {
        setMessage("La foto no se pudo enviar. No se marcó como completada.");
      }
    }
  });
});
