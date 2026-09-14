import { supabase, getCurrentUser } from "./supabase-client.js";

const list = document.getElementById("reviewList");
const message = document.getElementById("reviewMessage");
const filter = document.getElementById("statusFilter");
const refreshBtn = document.getElementById("refreshBtn");
const dialog = document.getElementById("reviewDialog");
const image = document.getElementById("reviewImage");
const details = document.getElementById("reviewDetails");
const reason = document.getElementById("rejectionReason");
const reasonWrap = document.getElementById("reasonWrap");
const approveBtn = document.getElementById("approveBtn");
const rejectBtn = document.getElementById("rejectBtn");
const closeDialogBtn = document.getElementById("closeDialogBtn");

let currentRun = null;
let currentItem = null;
let busy = false;

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

async function load() {
  list.innerHTML = "";
  message.textContent = "Cargando fotoverificaciones…";
  refreshBtn.disabled = true;
  try {
    const user = await getCurrentUser();
    const role = user?.app_metadata?.role;
    if (!["root","admin"].includes(role)) {
      message.textContent = "Esta pantalla está reservada a administradores.";
      list.innerHTML = '<div class="review-empty">No tienes permisos de revisión.</div>';
      return;
    }

    let query = supabase
      .from("photo_verification_runs_v2")
      .select("id,property_id,status,started_at,submitted_at,reviewed_at,rejection_reason")
      .order("started_at", { ascending:false })
      .limit(50);

    const wanted = filter.value;
    if (wanted) query = query.eq("status", wanted);

    const { data:runs, error:runError } = await query;
    if (runError) throw runError;
    if (!runs?.length) {
      message.textContent = "";
      list.innerHTML = '<div class="review-empty">No hay fotoverificaciones con este estado.</div>';
      return;
    }

    const runIds = runs.map(r => r.id);
    const propertyIds = [...new Set(runs.map(r => r.property_id))];

    const [{ data:items, error:itemError }, { data:properties, error:propertyError }] = await Promise.all([
      supabase
        .from("photo_verification_items_v2")
        .select("id,run_id,pattern_id,storage_path,captured_at,alignment_score,alignment_meta,manual_result")
        .in("run_id", runIds)
        .order("captured_at", { ascending:true }),
      supabase
        .from("properties_v2")
        .select("id,name,address_line")
        .in("id", propertyIds)
    ]);

    if (itemError) throw itemError;
    if (propertyError) throw propertyError;

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
    const propertyMap = new Map((properties || []).map(p => [p.id,p]));
    const patternMap = new Map((patterns || []).map(p => [p.id,p]));

    message.textContent = runs.length + (runs.length === 1 ? " resultado" : " resultados");
    list.innerHTML = runs.map(run => {
      const property = propertyMap.get(run.property_id);
      const runItems = byRun.get(run.id) || [];
      const first = runItems[0];
      const pattern = first ? patternMap.get(first.pattern_id) : null;
      const score = first?.alignment_score == null ? "—" : Math.round(Number(first.alignment_score) * 100) + "%";
      return `<article class="review-card">
        <div class="review-card__top">
          <div><h3>${esc(property?.name || "Piso")}</h3><p>${esc(pattern?.name || pattern?.target_key || "Fotoverificación")} · ${esc(fmtDate(run.submitted_at || run.started_at))}</p></div>
          <span class="review-status">${esc(statusLabel(run.status))}</span>
        </div>
        <div class="review-card__meta">
          <div class="review-chip">Alineación <strong>${esc(score)}</strong></div>
          <div class="review-chip">Capturas <strong>${runItems.length}</strong></div>
        </div>
        <button class="review-open" data-run="${esc(run.id)}" type="button">Ver revisión</button>
      </article>`;
    }).join("");

    list.querySelectorAll(".review-open").forEach(button => {
      button.addEventListener("click", () => openRun(
        runs.find(r => r.id === button.dataset.run),
        byRun.get(button.dataset.run) || [],
        propertyMap,
        patternMap
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

async function openRun(run, items, propertyMap, patternMap) {
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

  details.innerHTML = `
    <div class="review-chip">Piso <strong>${esc(property?.name || "—")}</strong></div>
    <div class="review-chip">Patrón <strong>${esc(pattern?.name || "—")}</strong></div>
    <div class="review-chip">Alineación <strong>${esc(score)}</strong></div>
    <div class="review-chip">Zonas activas <strong>${activeZones}</strong></div>
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
    message.textContent = decision === "approved" ? "Fotoverificación aprobada." : "Fotoverificación rechazada.";
    await load();
  } catch (error) {
    console.error(error);
    message.textContent = "No se pudo guardar la revisión.";
    approveBtn.disabled = false;
    rejectBtn.disabled = false;
  } finally {
    busy = false;
  }
}

filter.addEventListener("change", load);
refreshBtn.addEventListener("click", load);
closeDialogBtn.addEventListener("click", () => dialog.close());
approveBtn.addEventListener("click", () => decide("approved"));
rejectBtn.addEventListener("click", () => decide("rejected"));

load();
