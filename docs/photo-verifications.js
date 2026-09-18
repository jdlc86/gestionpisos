import { supabase, getCurrentUser } from "./supabase-client.js";

const list = document.getElementById("reviewList");
const message = document.getElementById("reviewMessage");
const filter = document.getElementById("statusFilter");
const propertyFilter = document.getElementById("propertyFilter");
const refreshBtn = document.getElementById("refreshBtn");
const evolutionBtn = document.getElementById("evolutionBtn");
const dialog = document.getElementById("reviewDialog");
const image = document.getElementById("reviewImage");
const details = document.getElementById("reviewDetails");
const reason = document.getElementById("rejectionReason");
const reasonWrap = document.getElementById("reasonWrap");
const approveBtn = document.getElementById("approveBtn");
const rejectBtn = document.getElementById("rejectBtn");
const closeDialogBtn = document.getElementById("closeDialogBtn");
const dialogTitle = document.getElementById("dialogTitle");
const toast = document.getElementById("reviewToast");
const backLink = document.getElementById("reviewBackLink");
const initialParams = new URLSearchParams(window.location.search);
if (backLink && initialParams.get("workflow_execution_id")) {
  backLink.href = "./workflow-tasks.html";
  backLink.textContent = "Volver a Tareas";
}

let currentRun = null;
let currentItem = null;
let busy = false;
let toastTimer = null;
let lastHistory = null;

function showToast(text, { error = false } = {}) {
  if (!toast) return;
  if (toastTimer) window.clearTimeout(toastTimer);
  toast.textContent = text;
  toast.classList.toggle("is-error", error);
  toast.classList.add("is-visible");
  toastTimer = window.setTimeout(() => {
    toast.classList.remove("is-visible");
    toastTimer = null;
  }, 2500);
}

function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, c => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
  })[c]);
}

function fmtDate(value) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("es-ES", {
    dateStyle:"medium", timeStyle:"short"
  }).format(new Date(value));
}

function statusLabel(status) {
  return ({
    submitted:"Pendiente",
    manual_review:"En revisión",
    approved:"Aprobada",
    rejected:"Rechazada",
    ai_review:"Revisión IA",
    cancelled:"Cancelada",
    capturing:"Capturando"
  })[status] || status;
}

async function load(options = {}) {
  const preservedMessage = options.preserveMessage || "";
  list.innerHTML = "";
  if (!preservedMessage) message.textContent = "Cargando fotoverificaciones…";
  refreshBtn.disabled = true;
  try {
    const user = await getCurrentUser();
    const role = user?.app_metadata?.role;
    if (!["root","admin"].includes(role)) {
      message.textContent = "Esta pantalla está reservada a administradores.";
      list.innerHTML = '<div class="review-empty">No tienes permisos de revisión.</div>';
      return;
    }

    const { data:visibleProperties, error:visiblePropertiesError } = await supabase
      .from("properties_v2")
      .select("id,name,address_line")
      .order("name", { ascending:true });
    if (visiblePropertiesError) throw visiblePropertiesError;

    const requestedProperty = new URLSearchParams(window.location.search).get("property_id") || "";
    const selectedProperty = propertyFilter.value || requestedProperty;
    propertyFilter.innerHTML = '<option value="">Todos los pisos</option>' + (visibleProperties || []).map(property =>
      `<option value="${esc(property.id)}">${esc(property.name || property.address_line || "Piso")}</option>`
    ).join("");
    propertyFilter.value = (visibleProperties || []).some(property => property.id === selectedProperty) ? selectedProperty : "";

    let query = supabase
      .from("photo_verification_runs_v2")
      .select("id,property_id,source_type,source_id,status,started_at,submitted_at,reviewed_at,reviewed_by,rejection_reason")
      .order("started_at", { ascending:false })
      .limit(100);

    const params = new URLSearchParams(window.location.search);
    const workflowExecutionId = params.get("workflow_execution_id") || "";
    const requestedStatus = params.get("status") || "";
    if (requestedStatus && !filter.value) filter.value = requestedStatus;

    const wanted = filter.value;
    if (wanted) query = query.eq("status", wanted);
    if (selectedProperty) query = query.eq("property_id", selectedProperty);
    if (workflowExecutionId) {
      query = query.eq("source_type","workflow_execution").eq("source_id",workflowExecutionId);
    }

    const { data:runs, error:runError } = await query;
    if (runError) throw runError;
    if (!runs?.length) {
      message.textContent = "";
      list.innerHTML = '<div class="review-empty">No hay fotoverificaciones pendientes con este filtro.</div>';
      return;
    }

    const runIds = runs.map(r => r.id);
    const reviewerIds = [...new Set(runs.map(r => r.reviewed_by).filter(Boolean))];

    const { data:items, error:itemError } = await supabase
      .from("photo_verification_items_v2")
      .select("id,run_id,pattern_id,storage_path,captured_at,alignment_score,alignment_meta,manual_result")
      .in("run_id", runIds)
      .order("captured_at", { ascending:true });

    if (itemError) throw itemError;

    let reviewers = [];
    if (reviewerIds.length) {
      const { data:profileRows, error:profileError } = await supabase
        .from("profiles")
        .select("user_id,display_name,email")
        .in("user_id", reviewerIds);
      if (!profileError) reviewers = profileRows || [];
    }

    const patternIds = [...new Set((items || []).map(i => i.pattern_id))];
    const { data:patterns, error:patternError } = patternIds.length
      ? await supabase.from("photo_patterns_v2").select("id,name,target_key").in("id", patternIds)
      : { data:[], error:null };
    if (patternError) throw patternError;

    const byRun = new Map();
    for (const item of items || []) {
      if (!byRun.has(item.run_id)) byRun.set(item.run_id, []);
      byRun.get(item.run_id).push(item);
    }
    const propertyMap = new Map((visibleProperties || []).map(p => [p.id,p]));
    const patternMap = new Map((patterns || []).map(p => [p.id,p]));
    const reviewerMap = new Map((reviewers || []).map(p => [p.user_id,p]));
    lastHistory = { runs, byRun, propertyMap, patternMap };

    if (preservedMessage) {
      message.textContent = preservedMessage;
      window.setTimeout(() => {
        message.textContent = runs.length + (runs.length === 1 ? " resultado" : " resultados");
      }, 2500);
    } else {
      message.textContent = runs.length + (runs.length === 1 ? " resultado" : " resultados");
    }
    list.innerHTML = runs.map(run => {
      const property = propertyMap.get(run.property_id);
      const runItems = byRun.get(run.id) || [];
      const first = runItems[0];
      const pattern = first ? patternMap.get(first.pattern_id) : null;
      const score = first?.alignment_score == null ? "—" : Math.round(Number(first.alignment_score) * 100) + "%";
      const reviewer = run.reviewed_by ? reviewerMap.get(run.reviewed_by) : null;
      const reviewerName = reviewer?.display_name || reviewer?.email || (run.reviewed_by ? "Usuario revisor" : "—");
      const reviewDate = run.reviewed_at ? fmtDate(run.reviewed_at) : "—";
      const rejection = run.rejection_reason || "—";
      return `<article class="review-card">
        <div class="review-card__top">
          <div><h3>${esc(property?.name || "Piso")}</h3><p>${esc(pattern?.name || pattern?.target_key || "Fotoverificación")} · ${esc(fmtDate(run.submitted_at || run.started_at))}</p></div>
          <span class="review-status">${esc(statusLabel(run.status))}</span>
        </div>
        <div class="review-card__meta">
          <div class="review-chip">Alineación <strong>${esc(score)}</strong></div>
          <div class="review-chip">Capturas <strong>${runItems.length}</strong></div>
          <div class="review-chip">Revisor <strong>${esc(reviewerName)}</strong></div>
          <div class="review-chip">Revisada <strong>${esc(reviewDate)}</strong></div>
        </div>
        ${run.status === "rejected" ? `<div class="review-reason">Motivo: ${esc(rejection)}</div>` : ""}
        <button class="review-open" data-run="${esc(run.id)}" type="button">Ver revisión</button>
      </article>`;
    }).join("");

    list.querySelectorAll(".review-open").forEach(button => {
      button.addEventListener("click", () => openRun(
        runs.find(r => r.id === button.dataset.run),
        byRun.get(button.dataset.run) || [],
        propertyMap,
        patternMap,
        reviewerMap
      ));
    });
  } catch (error) {
    console.error(error);
    message.textContent = "No se pudo cargar el historial.";
    list.innerHTML = '<div class="review-empty">Comprueba la sesión e inténtalo de nuevo.</div>';
  } finally {
    refreshBtn.disabled = false;
  }
}

async function openRun(run, items, propertyMap, patternMap, reviewerMap) {
  dialogTitle.textContent = "Revisar fotoverificación";
  currentRun = run;
  currentItem = items[0] || null;
  reason.value = "";
  reasonWrap.hidden = false;
  image.removeAttribute("src");

  if (!currentItem) {
    message.textContent = "La verificación no contiene capturas.";
    return;
  }

  const property = propertyMap.get(run.property_id);
  const pattern = patternMap.get(currentItem.pattern_id);
  const score = currentItem.alignment_score == null
    ? "—"
    : Math.round(Number(currentItem.alignment_score) * 100) + "%";
  const zones = currentItem.alignment_meta?.zones;
  const activeZones = Array.isArray(zones) ? zones.filter(v => Number(v) > 0).length : 0;
  const reviewer = run.reviewed_by ? reviewerMap.get(run.reviewed_by) : null;
  const reviewerName = reviewer?.display_name || reviewer?.email || (run.reviewed_by ? "Usuario revisor" : "—");

  details.innerHTML = `
    <div class="review-chip">Piso <strong>${esc(property?.name || "—")}</strong></div>
    <div class="review-chip">Patrón <strong>${esc(pattern?.name || "—")}</strong></div>
    <div class="review-chip">Alineación <strong>${esc(score)}</strong></div>
    <div class="review-chip">Zonas activas <strong>${activeZones}</strong></div>
    <div class="review-chip">Estado <strong>${esc(statusLabel(run.status))}</strong></div>
    <div class="review-chip">Revisor <strong>${esc(reviewerName)}</strong></div>
    <div class="review-chip">Revisada <strong>${esc(fmtDate(run.reviewed_at))}</strong></div>
    <div class="review-chip review-chip--wide">Motivo <strong>${esc(run.rejection_reason || "—")}</strong></div>
  `;

  const finalStatus = ["approved","rejected"].includes(run.status);
  approveBtn.disabled = finalStatus;
  rejectBtn.disabled = finalStatus;
  reasonWrap.hidden = finalStatus;
  if (run.rejection_reason) reason.value = run.rejection_reason;

  dialog.showModal();

  const { data, error } = await supabase.storage
    .from("photo-verification")
    .createSignedUrl(currentItem.storage_path, 120);

  if (error || !data?.signedUrl) {
    image.alt = "No se pudo cargar la imagen. La revisión de fotografías requiere sesión administrativa reforzada.";
    return;
  }
  image.src = data.signedUrl;
}

async function decide(decision) {
  if (busy || !currentRun) return;
  const rejectionReason = reason.value.trim();
  if (decision === "rejected" && !rejectionReason) {
    reason.focus();
    reason.setCustomValidity("Indica el motivo del rechazo.");
    reason.reportValidity();
    reason.setCustomValidity("");
    return;
  }

  busy = true;
  approveBtn.disabled = true;
  rejectBtn.disabled = true;
  try {
    const { data, error } = await supabase.functions.invoke("review-photo-verification", {
      body: {
        run_id: currentRun.id,
        decision,
        rejection_reason: decision === "rejected" ? rejectionReason : null
      }
    });
    if (error) throw error;
    if (!data?.ok) throw new Error(data?.error || "review_failed");
    dialog.close();
    let successMessage = decision === "approved"
      ? "Fotoverificación aprobada correctamente."
      : "Fotoverificación rechazada correctamente.";

    if (data?.workflow?.execution_status === "completed") {
      successMessage += " Workflow completado.";
    } else if (data?.workflow?.execution_status === "rejected") {
      successMessage += " Workflow rechazado.";
    } else if (data?.workflow?.execution_status === "waiting_review") {
      successMessage += " Quedan evidencias del workflow por revisar.";
    }

    showToast("✓ " + successMessage);
    message.textContent = successMessage;
    await load();
  } catch (error) {
    console.error(error);
    const errorMessage = "No se pudo guardar la revisión.";
    showToast(errorMessage, { error: true });
    message.textContent = errorMessage;
    approveBtn.disabled = false;
    rejectBtn.disabled = false;
  } finally {
    busy = false;
  }
}

filter.addEventListener("change", load);
propertyFilter.addEventListener("change", load);
refreshBtn.addEventListener("click", load);
evolutionBtn.addEventListener("click", showEvolution);
closeDialogBtn.addEventListener("click", () => dialog.close());
approveBtn.addEventListener("click", () => decide("approved"));
rejectBtn.addEventListener("click", () => decide("rejected"));

let lastEvolutionGroups = [];

async function signedEvolutionUrl(entry) {
  const { data, error } = await supabase.storage.from("photo-verification").createSignedUrl(entry.item.storage_path, 120);
  return error ? null : data?.signedUrl;
}
function evolutionOption(entry, index, disabledIndex = -1) {
  const score = entry.item.alignment_score == null ? "—" : Math.round(Number(entry.item.alignment_score) * 100) + "%";
  return `<option value="${index}" ${index === disabledIndex ? "disabled" : ""}>${esc(fmtDate(entry.item.captured_at))} · ${esc(score)} · ${esc(statusLabel(entry.run.status))}</option>`;
}
async function renderEvolutionComparison(group, leftIndex, rightIndex) {
  const pattern = lastHistory.patternMap.get(group.patternId);
  const left = group.entries[leftIndex], right = group.entries[rightIndex];
  const signed = await Promise.all([signedEvolutionUrl(left), signedEvolutionUrl(right)]);
  if (!signed[0] || !signed[1]) { showToast("No se pudieron cargar las imágenes de evolución.", { error:true }); return; }
  const score = entry => entry.item.alignment_score == null ? "—" : Math.round(Number(entry.item.alignment_score) * 100) + "%";
  details.innerHTML = `
    <div class="evolution-picker">
      <label>Patrón<select id="evolutionPattern">${lastEvolutionGroups.map((candidate,index) => {
        const p = lastHistory.patternMap.get(candidate.patternId);
        return `<option value="${index}" ${candidate === group ? "selected" : ""}>${esc(p?.name || p?.target_key || "Fotoverificación")} (${candidate.entries.length})</option>`;
      }).join("")}</select></label>
      <label>Comparar desde<select id="evolutionFrom">${group.entries.map((entry,index) => evolutionOption(entry,index,rightIndex)).join("")}</select></label>
      <label>Comparar con<select id="evolutionTo">${group.entries.map((entry,index) => evolutionOption(entry,index,leftIndex)).join("")}</select></label>
    </div>
    <div class="evolution-grid">
      <figure><img src="${esc(signed[0])}" alt="Verificación inicial"><figcaption>${esc(fmtDate(left.item.captured_at))} · ${esc(score(left))} · ${esc(statusLabel(left.run.status))}</figcaption></figure>
      <figure><img src="${esc(signed[1])}" alt="Verificación comparada"><figcaption>${esc(fmtDate(right.item.captured_at))} · ${esc(score(right))} · ${esc(statusLabel(right.run.status))}</figcaption></figure>
    </div>
    <div class="review-chip review-chip--wide">Patrón <strong>${esc(pattern?.name || pattern?.target_key || "Fotoverificación")}</strong> · ${group.entries.length} verificaciones</div>`;
  const patternSelect=document.getElementById("evolutionPattern"), fromSelect=document.getElementById("evolutionFrom"), toSelect=document.getElementById("evolutionTo");
  fromSelect.value=String(leftIndex); toSelect.value=String(rightIndex);
  patternSelect.addEventListener("change",()=>{ const next=lastEvolutionGroups[Number(patternSelect.value)]; renderEvolutionComparison(next,0,next.entries.length-1); });
  fromSelect.addEventListener("change",()=>renderEvolutionComparison(group,Number(fromSelect.value),Number(toSelect.value)));
  toSelect.addEventListener("change",()=>renderEvolutionComparison(group,Number(fromSelect.value),Number(toSelect.value)));
}
async function showEvolution() {
  dialogTitle.textContent = "Evolución de fotoverificaciones";
  if (!lastHistory?.runs?.length) { showToast("No hay verificaciones para comparar.", { error:true }); return; }
  const groups=new Map();
  for (const run of lastHistory.runs) for (const item of lastHistory.byRun.get(run.id)||[]) {
    const key=item.pattern_id||"unknown"; if(!groups.has(key)) groups.set(key,[]); groups.get(key).push({run,item});
  }
  lastEvolutionGroups=[...groups.entries()].map(([patternId,entries])=>({patternId,entries:entries.sort((a,b)=>new Date(a.item.captured_at)-new Date(b.item.captured_at))})).filter(group=>group.entries.length>=2);
  if(!lastEvolutionGroups.length){ showToast("Aún no hay dos verificaciones del mismo patrón para mostrar evolución.",{error:true}); return; }
  image.removeAttribute("src"); image.style.display="none"; reasonWrap.hidden=true; approveBtn.hidden=true; rejectBtn.hidden=true;
  dialog.addEventListener("close",()=>{image.style.display="";approveBtn.hidden=false;rejectBtn.hidden=false;dialogTitle.textContent="Revisar fotoverificación";},{once:true});
  dialog.showModal();
  await renderEvolutionComparison(lastEvolutionGroups[0],0,lastEvolutionGroups[0].entries.length-1);
}

load();
