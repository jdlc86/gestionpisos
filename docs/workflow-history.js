import { supabase } from "./supabase-client.js";

const list=document.getElementById("workflowHistory");
const statusBox=document.getElementById("historyStatus");
const topbar=document.getElementById("historyTopbar");
const normalHeader=document.getElementById("historyNormalHeader");
const searchHeader=document.getElementById("historySearchHeader");
const searchToggle=document.getElementById("historySearchToggle");
const searchClose=document.getElementById("historySearchClose");
const searchClear=document.getElementById("historySearchClear");
const searchInput=document.getElementById("historySearch");
const searchChip=document.getElementById("historyActiveSearch");
const searchChipText=document.getElementById("historyActiveSearchText");
const filterButtons=[...document.querySelectorAll("[data-history-filter]")];

const DOCUMENT_BUCKET="workflow-documents-v2";
const OPEN_STATUSES=new Set(["pending","active","waiting_review"]);
const statusLabels={
  pending:"Pendiente",
  active:"En curso",
  waiting_review:"Esperando revisión",
  completed:"Completada",
  rejected:"Rechazada",
  cancelled:"Cancelada",
  failed:"Fallida"
};
const triggerLabels={manual_now:"Manual"};
const assignmentLabels={
  manual:"Decidida al ejecutar",
  property_responsible:"Responsable operativo"
};

let currentUser=null;
let executions=[];
let tasksByExecution=new Map();
let eventsByExecution=new Map();
let documentsByExecution=new Map();
let photoResourcesByExecution=new Map();
let photoRunsById=new Map();
let taskHistoryByTask=new Map();
let properties=new Map();
let rooms=new Map();
let occupancies=new Map();
let profiles=new Map();
let versions=new Map();
let activeFilter="all";
let searchMode=false;

function setStatus(message,error=false){
  const span=statusBox?.querySelector("span:last-child");
  if(span)span.textContent=message;
  statusBox?.classList.toggle("error",error);
}
function fmtDate(value){
  if(!value)return "—";
  try{return new Intl.DateTimeFormat("es-ES",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value))}catch{return value}
}
function fmtShortDate(value){
  if(!value)return "—";
  try{return new Intl.DateTimeFormat("es-ES",{day:"2-digit",month:"short",hour:"2-digit",minute:"2-digit"}).format(new Date(value))}catch{return value}
}
function fmtBytes(value){
  const bytes=Number(value||0);
  if(!Number.isFinite(bytes)||bytes<=0)return "—";
  if(bytes<1024)return bytes+" B";
  if(bytes<1024*1024)return (bytes/1024).toFixed(bytes<10240?1:0)+" KB";
  return (bytes/(1024*1024)).toFixed(bytes<10*1024*1024?1:0)+" MB";
}
function profileLabel(userId){
  if(!userId)return "Sistema";
  if(userId===currentUser?.id)return "Tú";
  const profile=profiles.get(userId);
  return profile?.display_name||profile?.email||"Usuario";
}
function targetLabel(execution){
  if(execution.scope_type==="organization")return "Toda la organización";
  const property=execution.property_id?properties.get(execution.property_id):null;
  if(execution.scope_type==="property")return property?.name||property?.address_line||"Piso";
  if(execution.scope_type==="room"){
    const room=execution.room_id?rooms.get(execution.room_id):null;
    return [property?.name,room?.label||"Habitación"].filter(Boolean).join(" · ");
  }
  if(execution.scope_type==="occupancy"){
    const occupancy=execution.occupancy_id?occupancies.get(execution.occupancy_id):null;
    const person=occupancy?.tenants_v2?.full_name||occupancy?.occupant_email||"Ocupación";
    return [property?.name,person].filter(Boolean).join(" · ");
  }
  return property?.name||"Destino";
}
function versionLabel(execution){
  const version=versions.get(execution.definition_version_id);
  if(version?.version)return "v"+version.version;
  const snapshot=execution.spec_snapshot||{};
  if(snapshot.baseVersion)return "v"+snapshot.baseVersion;
  return "Versión publicada";
}
function taskFor(execution){
  return tasksByExecution.get(execution.id)||null;
}
function filteredExecutions(){
  const query=String(searchInput?.value||"").trim().toLocaleLowerCase("es");
  return executions.filter(execution=>{
    if(activeFilter==="open"&&!OPEN_STATUSES.has(execution.status))return false;
    if(activeFilter==="completed"&&execution.status!=="completed")return false;
    if(activeFilter==="rejected"&&execution.status!=="rejected")return false;
    if(!query)return true;
    const task=taskFor(execution);
    const haystack=[
      execution.spec_snapshot?.flowName,
      execution.spec_snapshot?.flowType,
      targetLabel(execution),
      profileLabel(execution.assigned_user_id),
      statusLabels[execution.status],
      task?.title,
      versionLabel(execution)
    ].filter(Boolean).join(" ").toLocaleLowerCase("es");
    return haystack.includes(query);
  });
}
function setHeaderMode(mode){
  searchMode=mode==="search";
  normalHeader.hidden=searchMode;
  searchHeader.hidden=!searchMode;
  topbar?.classList.toggle("is-searching",searchMode);
}
function syncSearchChip(){
  const query=String(searchInput?.value||"").trim();
  if(searchChipText)searchChipText.textContent=query;
  if(searchChip)searchChip.hidden=!query||searchMode;
}
function openSearch(){
  setHeaderMode("search");
  syncSearchChip();
  requestAnimationFrame(()=>{
    searchInput?.focus({preventScroll:true});
    searchInput?.select();
  });
}
function closeSearch({clear=false}={}){
  if(clear&&searchInput)searchInput.value="";
  setHeaderMode("normal");
  syncSearchChip();
  render();
}
function meta(label,value){
  const box=document.createElement("div");
  box.className="history-meta-item";
  const strong=document.createElement("strong");strong.textContent=label;
  const span=document.createElement("span");span.textContent=value||"—";
  box.append(strong,span);
  return box;
}
function evidenceItem(label,value,complete){
  const box=document.createElement("div");
  box.className="history-evidence-item "+(complete?"is-complete":"is-pending");
  const strong=document.createElement("strong");strong.textContent=label;
  const span=document.createElement("span");span.textContent=value;
  box.append(strong,span);
  return box;
}
function taskHistoryNote(taskId,actionKey,createdAt){
  const rows=taskHistoryByTask.get(taskId)||[];
  const targetTime=new Date(createdAt).getTime();
  let best=null;
  let delta=Infinity;
  rows.forEach(row=>{
    if(actionKey&&row.action_key!==actionKey)return;
    const d=Math.abs(new Date(row.created_at).getTime()-targetTime);
    if(d<delta){delta=d;best=row}
  });
  return delta<=5000?best?.note||null:null;
}
function reviewRunForEvent(event){
  const runId=event.details?.trigger_run_id||event.details?.photo_run_id;
  return runId?photoRunsById.get(runId)||null:null;
}
function eventTitle(event){
  const d=event.details||{};
  switch(event.event_type){
    case "created": return "Ejecución creada";
    case "task_materialized": return "Tarea creada";
    case "event_subject_bound": return "Ocupación vinculada";
    case "task_action_applied": return d.action_label||"Acción aplicada";
    case "wf04_domain_action": return ({
      accept:"Tarea aceptada",reject:"Tarea rechazada",
      key_pickup:"Recogida de llaves confirmada",key_delivery:"Entrega de llaves confirmada",
      check_in:"Entrada confirmada",check_out:"Salida confirmada"
    })[d.action_key]||"Acción de entrada o salida";
    case "photo_step_started": return "Evidencia fotográfica iniciada";
    case "photo_capture_started": return "Captura fotográfica iniciada";
    case "photo_evidence_submitted": return d.all_photos_complete?"Fotografías completadas":"Fotografía enviada";
    case "checklist_item_changed": return d.completed?"Checklist completado":"Checklist reabierto";
    case "document_step_started": return "Documento iniciado";
    case "document_upload_prepared": return "Carga de documento preparada";
    case "document_evidence_submitted": return "Documento adjuntado";
    case "workflow_review_applied": return Number(d.rejected_photo_count||0)>0?"Revisión rechazada":"Revisión aprobada";
    default: return String(event.event_type||"Evento").replaceAll("_"," ");
  }
}
function eventDetail(event){
  const d=event.details||{};
  if(event.event_type==="created"){
    return [
      triggerLabels[d.trigger_kind]||d.trigger_kind,
      assignmentLabels[d.assignment_type]||d.assignment_type
    ].filter(Boolean).join(" · ");
  }
  if(event.event_type==="task_action_applied"){
    const note=taskHistoryNote(d.task_id,d.action_key,event.created_at);
    return note||"Decisión registrada sobre la tarea.";
  }
  if(event.event_type==="event_subject_bound"){
    return "La ejecución quedó vinculada a la ocupación y al evento de origen.";
  }
  if(event.event_type==="wf04_domain_action"){
    return taskHistoryNote(d.task_id,d.action_key,event.created_at)
      ||"Hito registrado sobre la ocupación vinculada.";
  }
  if(event.event_type==="checklist_item_changed"){
    return d.item_text||"Elemento de checklist";
  }
  if(event.event_type==="photo_evidence_submitted"){
    return d.all_photos_complete?"Todas las fotografías requeridas quedaron enviadas.":"Evidencia fotográfica registrada.";
  }
  if(event.event_type==="workflow_review_applied"){
    const rejected=Number(d.rejected_photo_count||0)>0;
    const historyNote=taskHistoryNote(
      d.task_id,
      rejected?"review_reject":"review_approve",
      event.created_at
    );
    if(historyNote)return historyNote;

    const run=reviewRunForEvent(event);
    if(run?.rejection_reason)return run.rejection_reason;

    return rejected
      ?"La revisión contiene evidencia rechazada."
      :"La revisión fue aprobada.";
  }
  if(event.event_type==="document_evidence_submitted"){
    return "Evidencia documental confirmada.";
  }
  return "";
}
function transitionLabel(event){
  if(!event.from_status||!event.to_status||event.from_status===event.to_status)return "";
  return (statusLabels[event.from_status]||event.from_status)+" → "+(statusLabels[event.to_status]||event.to_status);
}
function renderTimeline(execution,container){
  const events=(eventsByExecution.get(execution.id)||[]).slice().sort((a,b)=>new Date(a.created_at)-new Date(b.created_at));
  const section=document.createElement("section");
  section.className="history-timeline";
  const h=document.createElement("h3");
  h.className="history-timeline-title";
  h.textContent="Línea temporal";
  section.append(h);

  if(!events.length){
    const empty=document.createElement("p");
    empty.className="history-event-detail";
    empty.textContent="No hay eventos visibles para esta ejecución.";
    section.append(empty);
    container.append(section);
    return;
  }

  events.forEach(event=>{
    const row=document.createElement("div");
    row.className="history-event";
    const dot=document.createElement("span");dot.className="history-event-dot";
    const content=document.createElement("div");content.className="history-event-content";
    const head=document.createElement("div");head.className="history-event-head";
    const title=document.createElement("strong");title.textContent=eventTitle(event);
    const time=document.createElement("time");time.dateTime=event.created_at;time.textContent=fmtShortDate(event.created_at);
    head.append(title,time);
    content.append(head);

    const detailText=eventDetail(event);
    if(detailText){
      const detail=document.createElement("p");detail.className="history-event-detail";
      detail.textContent=detailText;
      content.append(detail);
    }

    const actor=document.createElement("p");
    actor.className="history-event-detail";
    actor.textContent="Por "+profileLabel(event.actor_user_id);
    content.append(actor);

    const transition=transitionLabel(event);
    if(transition){
      const badge=document.createElement("span");badge.className="history-event-transition";badge.textContent=transition;
      content.append(badge);
    }
    row.append(dot,content);
    section.append(row);
  });

  container.append(section);
}
async function openDocument(documentRow,button){
  const original=button.textContent;
  button.disabled=true;
  button.textContent="Abriendo…";
  const preview=window.open("about:blank","_blank");
  if(preview)preview.opener=null;

  const {data,error}=await supabase.storage.from(DOCUMENT_BUCKET).createSignedUrl(documentRow.storage_path,300);
  button.disabled=false;
  button.textContent=original;
  if(error||!data?.signedUrl){
    if(preview)preview.close();
    setStatus("No se pudo abrir el documento privado.",true);
    return;
  }
  if(preview)preview.location.href=data.signedUrl;
  else window.location.href=data.signedUrl;
}
function renderDocuments(execution,container){
  const docs=(documentsByExecution.get(execution.id)||[]).filter(row=>row.status==="submitted");
  if(!docs.length)return;
  const section=document.createElement("section");
  section.className="history-documents";
  docs.forEach(documentRow=>{
    const row=document.createElement("div");row.className="history-document-row";
    const info=document.createElement("div");
    const name=document.createElement("span");name.textContent=documentRow.original_filename;
    const small=document.createElement("small");small.textContent=fmtBytes(documentRow.size_bytes)+" · "+fmtDate(documentRow.submitted_at||documentRow.created_at);
    info.append(name,small);
    const open=document.createElement("button");open.type="button";open.className="secondary history-document-open";open.textContent="Abrir documento";
    open.addEventListener("click",()=>openDocument(documentRow,open));
    row.append(info,open);
    section.append(row);
  });
  container.append(section);
}
function renderEvidence(execution,container){
  const steps=execution.spec_snapshot?.steps||{};
  const items=Array.isArray(execution.checklist_state)?execution.checklist_state:[];
  const required=items.filter(item=>item.required!==false);
  const completedRequired=required.filter(item=>item.completed===true).length;
  const photos=photoResourcesByExecution.get(execution.id)||[];
  const photoSubmitted=photos.filter(item=>item.status==="submitted").length;
  const docs=(documentsByExecution.get(execution.id)||[]).filter(item=>item.status==="submitted");

  const section=document.createElement("section");
  section.className="history-evidence";

  if(steps.photo===true){
    section.append(evidenceItem(
      "Fotografías",
      photoSubmitted+" de "+photos.length+" enviadas",
      photos.length>0&&photoSubmitted===photos.length
    ));
  }
  if(steps.checklist===true){
    section.append(evidenceItem(
      "Checklist",
      completedRequired+" de "+required.length+" obligatorios",
      required.length>0&&completedRequired===required.length
    ));
  }
  if(steps.document===true){
    section.append(evidenceItem(
      "Documento",
      docs.length?docs.length+" adjunto"+(docs.length===1?"":"s"):"Pendiente",
      docs.length>0
    ));
  }

  if(section.children.length)container.append(section);
}
function renderCard(execution){
  const task=taskFor(execution);
  const details=document.createElement("details");
  details.className="history-card";

  const summary=document.createElement("summary");
  const main=document.createElement("div");main.className="history-summary-main";
  const title=document.createElement("h2");
  title.textContent=execution.spec_snapshot?.flowName||task?.title||"Flujo";
  const sub=document.createElement("div");sub.className="history-summary-sub";
  sub.textContent=targetLabel(execution)+" · "+fmtDate(execution.created_at);
  main.append(title,sub);

  const side=document.createElement("div");side.className="history-summary-side";
  const badge=document.createElement("span");badge.className="history-status-badge";badge.dataset.status=execution.status;
  badge.textContent=statusLabels[execution.status]||execution.status;
  const chevron=document.createElementNS("http://www.w3.org/2000/svg","svg");
  chevron.setAttribute("viewBox","0 0 24 24");chevron.setAttribute("aria-hidden","true");chevron.classList.add("history-chevron");
  chevron.innerHTML='<path d="m7 9 5 5 5-5"/>';
  side.append(badge,chevron);
  summary.append(main,side);

  const body=document.createElement("div");body.className="history-body";
  const metaBox=document.createElement("div");metaBox.className="history-meta";
  metaBox.append(
    meta("Versión",versionLabel(execution)),
    meta("Asignación",assignmentLabels[execution.assignment_type]||execution.assignment_type),
    meta("Asignada a",profileLabel(execution.assigned_user_id)),
    meta("Tarea",task?(statusLabels[task.status]||task.status):"No visible")
  );
  body.append(metaBox);
  renderEvidence(execution,body);
  renderDocuments(execution,body);
  renderTimeline(execution,body);

  details.append(summary,body);
  return details;
}
function render(){
  const rows=filteredExecutions();
  list.replaceChildren();

  if(!rows.length){
    const empty=document.createElement("article");
    empty.className="history-empty";
    empty.textContent=executions.length
      ?"No hay ejecuciones que coincidan con este filtro."
      :"Todavía no hay ejecuciones visibles.";
    list.append(empty);
  }else{
    rows.forEach(execution=>list.append(renderCard(execution)));
  }
  syncSearchChip();
}
function mapBy(rows,key){
  const map=new Map();
  (rows||[]).forEach(row=>map.set(row[key],row));
  return map;
}
function groupBy(rows,key){
  const map=new Map();
  (rows||[]).forEach(row=>{
    const value=row[key];
    const bucket=map.get(value)||[];
    bucket.push(row);
    map.set(value,bucket);
  });
  return map;
}

async function loadRelated(){
  const executionIds=executions.map(row=>row.id);
  const propertyIds=[...new Set(executions.map(row=>row.property_id).filter(Boolean))];
  const roomIds=[...new Set(executions.map(row=>row.room_id).filter(Boolean))];
  const occupancyIds=[...new Set(executions.map(row=>row.occupancy_id).filter(Boolean))];
  const versionIds=[...new Set(executions.map(row=>row.definition_version_id).filter(Boolean))];
  const userIds=new Set(executions.map(row=>row.assigned_user_id).filter(Boolean));

  const [taskResult,eventResult,photoResult,documentResult,propertyResult,roomResult,occupancyResult]=await Promise.all([
    executionIds.length
      ?supabase.from("tenant_tasks_v2").select("id,source_id,title,status,assigned_user_id,created_at,updated_at").eq("source_kind","workflow_execution").in("source_id",executionIds)
      :Promise.resolve({data:[],error:null}),
    executionIds.length
      ?supabase.from("workflow_execution_events_v2").select("id,execution_id,event_type,from_status,to_status,actor_user_id,details,created_at").in("execution_id",executionIds).order("created_at")
      :Promise.resolve({data:[],error:null}),
    executionIds.length
      ?supabase.from("workflow_execution_photo_resources_v2").select("id,execution_id,status,photo_run_id,pattern_snapshot,sort_order,completed_at").in("execution_id",executionIds).order("sort_order")
      :Promise.resolve({data:[],error:null}),
    executionIds.length
      ?supabase.from("workflow_execution_documents_v2").select("id,execution_id,original_filename,mime_type,size_bytes,storage_path,status,uploaded_by,created_at,submitted_at").in("execution_id",executionIds).order("created_at")
      :Promise.resolve({data:[],error:null}),
    propertyIds.length
      ?supabase.from("properties_v2").select("id,name,address_line").in("id",propertyIds)
      :Promise.resolve({data:[],error:null}),
    roomIds.length
      ?supabase.from("rooms_v2").select("id,property_id,label").in("id",roomIds)
      :Promise.resolve({data:[],error:null}),
    occupancyIds.length
      ?supabase.from("occupancies_v2").select("id,property_id,occupant_email,tenants_v2(full_name,email)").in("id",occupancyIds)
      :Promise.resolve({data:[],error:null})
  ]);

  const critical=[taskResult,eventResult,photoResult,documentResult];
  if(critical.some(result=>result.error))throw critical.find(result=>result.error).error;

  tasksByExecution=mapBy(taskResult.data||[],"source_id");
  eventsByExecution=groupBy(eventResult.data||[],"execution_id");
  photoResourcesByExecution=groupBy(photoResult.data||[],"execution_id");
  documentsByExecution=groupBy(documentResult.data||[],"execution_id");
  properties=mapBy(propertyResult.data||[],"id");
  rooms=mapBy(roomResult.data||[],"id");
  occupancies=mapBy(occupancyResult.data||[],"id");

  (eventResult.data||[]).forEach(row=>{if(row.actor_user_id)userIds.add(row.actor_user_id)});
  (documentResult.data||[]).forEach(row=>{if(row.uploaded_by)userIds.add(row.uploaded_by)});

  const taskIds=(taskResult.data||[]).map(row=>row.id);
  const runIds=[...new Set((photoResult.data||[]).map(row=>row.photo_run_id).filter(Boolean))];

  const [historyResult,runResult,profileResult,versionResult]=await Promise.all([
    taskIds.length
      ?supabase.from("tenant_task_history_v2").select("id,task_id,action_key,action_label,from_status,to_status,note,actor_user_id,created_at").in("task_id",taskIds).order("created_at")
      :Promise.resolve({data:[],error:null}),
    runIds.length
      ?supabase.from("photo_verification_runs_v2").select("id,status,reviewed_at,reviewed_by,rejection_reason").in("id",runIds)
      :Promise.resolve({data:[],error:null}),
    userIds.size
      ?supabase.from("profiles").select("user_id,display_name,email").in("user_id",[...userIds])
      :Promise.resolve({data:[],error:null}),
    versionIds.length
      ?supabase.from("workflow_definition_versions_v2").select("id,version").in("id",versionIds)
      :Promise.resolve({data:[],error:null})
  ]);

  taskHistoryByTask=groupBy(historyResult.data||[],"task_id");
  photoRunsById=mapBy(runResult.data||[],"id");
  profiles=mapBy(profileResult.data||[],"user_id");
  versions=mapBy(versionResult.data||[],"id");

  (runResult.data||[]).forEach(row=>{if(row.reviewed_by)userIds.add(row.reviewed_by)});
  const missingReviewers=[...userIds].filter(id=>!profiles.has(id));
  if(missingReviewers.length){
    const {data}=await supabase.from("profiles").select("user_id,display_name,email").in("user_id",missingReviewers);
    (data||[]).forEach(row=>profiles.set(row.user_id,row));
  }
}

async function load(){
  const {data:userData,error:userError}=await supabase.auth.getUser();
  if(userError||!userData?.user){
    list.replaceChildren();
    setStatus("No se pudo validar la sesión.",true);
    return;
  }
  currentUser=userData.user;

  const {data,error}=await supabase
    .from("workflow_executions_v2")
    .select("id,definition_id,definition_version_id,organization_id,scope_type,property_id,room_id,occupancy_id,trigger_kind,assignment_type,assigned_user_id,status,spec_snapshot,checklist_state,created_at,started_at,completed_at")
    .order("created_at",{ascending:false})
    .limit(100);

  if(error){
    list.replaceChildren();
    setStatus("No se pudo consultar el historial autorizado.",true);
    return;
  }

  executions=data||[];
  try{
    await loadRelated();
  }catch(error){
    list.replaceChildren();
    setStatus("Las ejecuciones existen, pero no se pudieron reconstruir todos sus eventos.",true);
    return;
  }

  render();
  const closed=executions.filter(row=>["completed","rejected","cancelled","failed"].includes(row.status)).length;
  setStatus(executions.length+" ejecución"+(executions.length===1?"":"es")+" visible"+(executions.length===1?"":"s")+" · "+closed+" cerrada"+(closed===1?"":"s")+".");
}

searchToggle?.addEventListener("click",openSearch);
searchClose?.addEventListener("click",()=>closeSearch({clear:false}));
searchClear?.addEventListener("click",()=>closeSearch({clear:true}));
searchInput?.addEventListener("input",render);
searchChip?.addEventListener("click",()=>{
  if(searchInput)searchInput.value="";
  render();
});
filterButtons.forEach(button=>button.addEventListener("click",()=>{
  activeFilter=button.dataset.historyFilter||"all";
  filterButtons.forEach(item=>{
    const active=item===button;
    item.classList.toggle("is-active",active);
    item.setAttribute("aria-pressed",String(active));
  });
  render();
}));
document.addEventListener("keydown",event=>{
  if(event.key==="Escape"&&searchMode)closeSearch({clear:false});
});

load();
