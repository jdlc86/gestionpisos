import { supabase } from "./supabase-client.js";

const list=document.getElementById("workflowTasks");
const statusBox=document.getElementById("tasksStatus");
const filter=document.getElementById("taskFilter");
const topbar=document.getElementById("tasksTopbar");
const normalHeader=document.getElementById("tasksNormalHeader");
const selectionHeader=document.getElementById("tasksSelectionHeader");
const selectionToggle=document.getElementById("taskSelectionToggle");
const selectionClose=document.getElementById("taskSelectionClose");
const selectionSummary=document.getElementById("taskSelectionSummary");
const selectionMenuToggle=document.getElementById("taskSelectionMenuToggle");
const selectionMenu=document.getElementById("taskSelectionMenu");
const selectVisible=document.getElementById("taskSelectVisible");
const deselectVisible=document.getElementById("taskDeselectVisible");
const bulkDock=document.getElementById("taskBulkDock");
const bulkDelete=document.getElementById("taskBulkDelete");
const bulkDeleteCount=document.getElementById("taskBulkDeleteCount");

let currentUser=null;
let tasks=[];
let properties=new Map();
let rooms=new Map();
let profiles=new Map();
let actionsByTask=new Map();
let managerOrganizationIds=new Set();
let rootManager=false;
let photoResourcesByExecution=new Map();
let documentsByExecution=new Map();
let workflowExecutionsById=new Map();
let selectionMode=false;
const selectedTaskIds=new Set();

const TERMINAL_TASK_STATUSES=new Set(["completed","cancelled","failed","rejected","refunded","held"]);
const TERMINAL_EXECUTION_STATUSES=new Set(["completed","cancelled","failed","rejected"]);

const ACTION_KEY_PREFIX="workflow-task-action:";
const CHECKLIST_KEY_PREFIX="workflow-checklist-action:";
const DOCUMENT_KEY_PREFIX="workflow-document-upload:";
const DOCUMENT_BUCKET="workflow-documents-v2";
const DOCUMENT_TYPES=new Set(["application/pdf","image/jpeg","image/png","image/webp"]);
const DOCUMENT_MAX_BYTES=10*1024*1024;
const statusLabels={
  pending:"Pendiente",active:"En curso",waiting_review:"Esperando revisión",
  accepted:"Aceptada",in_progress:"En curso",waiting_info:"Esperando información",
  submitted:"Enviada",completed:"Completada",cancelled:"Cancelada",failed:"Fallida",rejected:"Rechazada",
  requested:"Solicitada",scheduled:"Programada",open:"Abierta",assigned:"Asignada",
  draft:"Borrador",claimed:"Reclamada",disputed:"En disputa",received:"Recibida",
  under_review:"En revisión",refunded:"Devuelta",partially_held:"Retención parcial",held:"Retenida"
};

function setStatus(message,error=false){
  const span=statusBox?.querySelector("span:last-child");
  if(span)span.textContent=message;
  statusBox?.classList.toggle("error",error);
}
function fmtDate(value){
  if(!value)return "—";
  try{return new Intl.DateTimeFormat("es-ES",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value))}catch{return value}
}
function fmtBytes(value){
  const bytes=Number(value||0);
  if(!Number.isFinite(bytes)||bytes<=0)return "—";
  if(bytes<1024)return bytes+" B";
  if(bytes<1024*1024)return (bytes/1024).toFixed(bytes<10*1024?1:0)+" KB";
  return (bytes/(1024*1024)).toFixed(bytes<10*1024*1024?1:0)+" MB";
}
function meta(label,value){
  const box=document.createElement("div");box.className="task-meta-item";
  const strong=document.createElement("strong");strong.textContent=label;
  const span=document.createElement("span");span.textContent=value||"—";
  box.append(strong,span);return box;
}
function scopeLabel(task){
  const property=task.property_id?properties.get(task.property_id):null;
  const room=task.room_id?rooms.get(task.room_id):null;
  if(room)return (property?.name||"Piso")+" · "+room.label;
  if(property)return property.name||property.address_line||"Piso";
  if(task.tenant_id)return "Inquilino";
  return "Organización";
}
function assigneeLabel(task){
  if(!task.assigned_user_id)return "Sin asignar";
  if(task.assigned_user_id===currentUser?.id)return "Tú";
  const profile=profiles.get(task.assigned_user_id);
  return profile?.display_name||profile?.email||"Usuario asignado";
}
function visibleTasks(){
  if(filter.value==="all")return tasks;
  if(filter.value==="mine")return tasks.filter(task=>task.assigned_user_id===currentUser?.id);
  return tasks.filter(task=>!["completed","cancelled","rejected","refunded","held"].includes(task.status));
}

function selectedTasks(){
  return tasks.filter(task=>selectedTaskIds.has(task.id));
}
function canDeleteTask(task){
  if(!task||!canManageTask(task)||!TERMINAL_TASK_STATUSES.has(task.status))return false;
  if(task.source_kind==="workflow_execution"){
    const execution=executionForTask(task);
    return Boolean(execution&&TERMINAL_EXECUTION_STATUSES.has(execution.status));
  }
  return true;
}
function selectedDeletableTasks(){
  return selectedTasks().filter(canDeleteTask);
}
function closeSelectionMenu(){
  if(!selectionMenu||!selectionMenuToggle)return;
  selectionMenu.hidden=true;
  selectionMenuToggle.setAttribute("aria-expanded","false");
}
function setHeaderMode(mode){
  if(normalHeader)normalHeader.hidden=mode!=="normal";
  if(selectionHeader)selectionHeader.hidden=mode!=="selection";
  topbar?.classList.toggle("is-selecting",mode==="selection");
  if(mode!=="selection")closeSelectionMenu();
}
function syncSelectionAvailability(){
  if(!selectionToggle)return;
  const manager=rootManager||managerOrganizationIds.size>0;
  selectionToggle.hidden=selectionMode||!manager||tasks.length===0;
}
function setSelectionMode(enabled,{selectId=null}={}){
  selectionMode=enabled;
  document.body.classList.toggle("tasks-selection-active",enabled);
  list.classList.toggle("is-selecting",enabled);
  if(enabled){
    if(selectId)selectedTaskIds.add(selectId);
    setHeaderMode("selection");
  }else{
    selectedTaskIds.clear();
    setHeaderMode("normal");
  }
  render();
}
function updateBulkState(){
  const selected=selectedTasks();
  const deletable=selected.filter(canDeleteTask);
  if(selectionSummary){
    selectionSummary.textContent=selected.length+" seleccionada"+(selected.length===1?"":"s");
  }
  if(bulkDock)bulkDock.hidden=!selectionMode||selected.length===0;
  if(bulkDelete)bulkDelete.disabled=deletable.length===0;
  if(bulkDeleteCount)bulkDeleteCount.textContent=String(deletable.length);

  const visibleIds=visibleTasks().map(task=>task.id);
  const selectedVisible=visibleIds.filter(id=>selectedTaskIds.has(id)).length;
  if(selectVisible)selectVisible.disabled=visibleIds.length===0||selectedVisible===visibleIds.length;
  if(deselectVisible)deselectVisible.disabled=selectedVisible===0;
  syncSelectionAvailability();
}
function toggleTaskSelection(task,article,force){
  const next=typeof force==="boolean"?force:!selectedTaskIds.has(task.id);
  if(next)selectedTaskIds.add(task.id);else selectedTaskIds.delete(task.id);
  article?.classList.toggle("is-selected",next);
  const indicator=article?.querySelector(".task-select-indicator");
  if(indicator){
    indicator.setAttribute("aria-pressed",String(next));
    indicator.setAttribute("aria-label",(next?"Deseleccionar ":"Seleccionar ")+(task.title||"tarea"));
  }
  updateBulkState();
}
function bindTaskLongPress(article,task){
  let timer=null;
  let startX=0;
  let startY=0;
  let longPressed=false;

  const clear=()=>{
    if(timer)clearTimeout(timer);
    timer=null;
  };

  article.addEventListener("pointerdown",event=>{
    if(selectionMode||event.button!==0||!canManageTask(task))return;
    if(event.target.closest("a,button,input,select,textarea,label,summary"))return;
    longPressed=false;
    startX=event.clientX;
    startY=event.clientY;
    timer=setTimeout(()=>{
      longPressed=true;
      article.dataset.longPressed="1";
      setSelectionMode(true,{selectId:task.id});
    },520);
  });
  article.addEventListener("pointermove",event=>{
    if(!timer)return;
    if(Math.abs(event.clientX-startX)>10||Math.abs(event.clientY-startY)>10)clear();
  });
  article.addEventListener("pointerup",clear);
  article.addEventListener("pointercancel",clear);
  article.addEventListener("pointerleave",clear);
  article.addEventListener("contextmenu",event=>{
    if(longPressed||article.dataset.longPressed==="1"){
      event.preventDefault();
      article.dataset.longPressed="";
    }
  });
}
function clearSelection(){
  setSelectionMode(false);
}
function errorText(error){
  const message=String(error?.message||"");
  if(message.includes("task_delete_forbidden"))return "No tienes permiso para eliminar esta tarjeta.";
  if(message.includes("task_delete_requires_terminal"))return "Solo se pueden eliminar de Tareas las tarjetas que ya están cerradas.";
  if(message.includes("task_delete_execution_not_terminal"))return "La ejecución asociada sigue abierta y no se puede retirar de Tareas.";
  if(message.includes("task_delete_execution_missing"))return "La tarea perdió la referencia a su ejecución. No se eliminó nada.";
  if(message.includes("task_not_found"))return "La tarea ya no existe.";
  if(message.includes("workflow_action_actor_forbidden"))return "Esta acción solo puede realizarla la persona asignada.";
  if(message.includes("workflow_action_not_allowed"))return "La acción ya no está disponible para el estado actual.";
  if(message.includes("workflow_task_execution_state_mismatch"))return "Tarea y ejecución no están sincronizadas. No se ha aplicado ningún cambio.";
  if(message.includes("workflow_action_request_key_conflict"))return "El identificador de reintento pertenece a otra acción. Recarga la pantalla.";
  if(message.includes("workflow_action_note_required"))return "Esta acción requiere una nota.";
  if(message.includes("workflow_review_actor_forbidden"))return "Solo un gestor autorizado puede revisar este workflow.";
  if(message.includes("workflow_photo_review_requires_photo_review_flow"))return "Este workflow debe revisarse desde Fotoverificaciones.";
  if(message.includes("workflow_review_action_not_supported"))return "La revisión ya no está disponible para el estado actual.";
  if(message.includes("workflow_checklist_actor_forbidden"))return "Solo la persona asignada puede completar este checklist.";
  if(message.includes("workflow_checklist_accept_required"))return "Primero debes aceptar la tarea.";
  if(message.includes("workflow_checklist_not_actionable"))return "El checklist ya no se puede modificar en el estado actual.";
  if(message.includes("workflow_checklist_item_not_found"))return "El elemento ya no existe en esta ejecución. Recarga la pantalla.";
  if(message.includes("workflow_checklist_request_key_conflict"))return "El reintento pertenece a otro cambio del checklist. Recarga la pantalla.";
  if(message.includes("workflow_document_actor_forbidden"))return "Solo la persona asignada puede adjuntar documentos a esta tarea.";
  if(message.includes("workflow_document_accept_required"))return "Primero debes aceptar la tarea.";
  if(message.includes("workflow_document_not_actionable"))return "El documento ya no se puede adjuntar en el estado actual.";
  if(message.includes("workflow_document_not_configured"))return "Esta tarea no tiene un paso Documento configurado.";
  if(message.includes("workflow_document_filename_invalid"))return "El nombre del archivo no es válido.";
  if(message.includes("workflow_document_size_invalid"))return "El archivo debe tener un tamaño máximo de 10 MB.";
  if(message.includes("workflow_document_mime_invalid"))return "Solo se admiten PDF, JPG, PNG o WebP.";
  if(message.includes("workflow_document_object_missing"))return "La carga del archivo no llegó a completarse. Selecciona el archivo de nuevo para reintentar.";
  if(message.includes("workflow_document_request_key_conflict"))return "El reintento pertenece a otro documento. Selecciona el archivo de nuevo.";
  if(message.includes("workflow_document_not_found"))return "El documento ya no está disponible. Recarga la tarea.";
  if(message.includes("workflow_action_not_supported")||message.includes("workflow_action_close_rule_not_supported"))return "Esta transición todavía no está habilitada para esta receta.";
  return "No se pudo aplicar la acción. No se ha confirmado ningún cambio.";
}
function requestKey(task,action){
  const storageKey=ACTION_KEY_PREFIX+task.id+":"+action.action_key+":"+action.from_status;
  let key=sessionStorage.getItem(storageKey);
  if(!key){
    key=globalThis.crypto?.randomUUID?.()||("action-"+Date.now()+"-"+Math.random().toString(36).slice(2));
    sessionStorage.setItem(storageKey,key);
  }
  return {storageKey,key};
}
function checklistRequestKey(task,itemKey,completed){
  const storageKey=CHECKLIST_KEY_PREFIX+task.id+":"+itemKey+":"+(completed?"1":"0");
  let key=sessionStorage.getItem(storageKey);
  if(!key){
    key=globalThis.crypto?.randomUUID?.()||("checklist-"+Date.now()+"-"+Math.random().toString(36).slice(2));
    sessionStorage.setItem(storageKey,key);
  }
  return {storageKey,key};
}
function documentRequestKey(task,file){
  const fingerprint=[
    task.id,
    file.name,
    file.size,
    file.lastModified,
    file.type
  ].join(":");
  const storageKey=DOCUMENT_KEY_PREFIX+fingerprint;
  let key=sessionStorage.getItem(storageKey);
  if(!key){
    key=globalThis.crypto?.randomUUID?.()||("document-"+Date.now()+"-"+Math.random().toString(36).slice(2));
    sessionStorage.setItem(storageKey,key);
  }
  return {storageKey,key};
}
function executionForTask(task){
  return task.source_kind==="workflow_execution"&&task.source_id
    ?workflowExecutionsById.get(task.source_id)||null
    :null;
}
function actionNote(task){
  if(task.status==="completed")return "Tarea y ejecución completadas de forma sincronizada.";
  if(task.status==="waiting_review")return "La ejecución está esperando una decisión de revisión humana.";
  if(task.status==="active")return "La tarea está activa. Quedan pasos de la receta que todavía deben completarse.";
  if(task.status==="rejected")return "La persona asignada rechazó la tarea. El motivo queda registrado en el histórico.";
  return "No hay una acción operativa habilitada para esta receta en el estado actual.";
}
function photoResourceLabel(resource){
  const snapshot=resource.pattern_snapshot||{};
  return snapshot.name||snapshot.target_key||"Fotografía";
}
function workflowPhotoReviewUrl(task){
  const url=new URL("./photo-verifications.html",window.location.href);
  url.searchParams.set("workflow_execution_id",task.source_id);
  if(task.property_id)url.searchParams.set("property_id",task.property_id);
  url.searchParams.set("status","submitted");
  return url.href;
}
function canManageTask(task){
  return rootManager||managerOrganizationIds.has(task.organization_id);
}
function canRenderWorkflowAction(task,action){
  if(action.actor==="assignee")return task.assigned_user_id===currentUser?.id;
  if(action.actor==="agency")return canManageTask(task);
  return false;
}
function workflowPhotoUrl(task,resource){
  const url=new URL("./photo-camera.html",window.location.href);
  url.searchParams.set("mode","verify");
  url.searchParams.set("pattern_id",resource.pattern_id);
  url.searchParams.set("workflow_resource_id",resource.id);
  url.searchParams.set("source_type","workflow_execution");
  url.searchParams.set("source_id",task.source_id);
  return url.href;
}
function renderPhotoResources(task,article){
  if(task.source_kind!=="workflow_execution"||!task.source_id)return;
  const resources=(photoResourcesByExecution.get(task.source_id)||[])
    .slice()
    .sort((a,b)=>a.sort_order-b.sort_order);
  if(!resources.length)return;

  const box=document.createElement("div");
  box.className="task-photo-resources";
  const heading=document.createElement("strong");
  heading.textContent="Evidencia fotográfica";
  box.append(heading);

  resources.forEach(resource=>{
    const row=document.createElement("div");
    row.className="task-photo-resource";
    const info=document.createElement("div");
    const title=document.createElement("span");
    title.textContent=photoResourceLabel(resource);
    const state=document.createElement("small");
    state.textContent=resource.status==="submitted"
      ?"Enviada"
      :resource.status==="capturing"
        ?"Captura iniciada"
        :"Pendiente";
    info.append(title,state);
    row.append(info);

    const canCapture=resource.status!=="submitted"&&(
      task.status==="active"
      || (task.status==="pending"&&!resource.requires_accept)
    );

    if(canCapture){
      const link=document.createElement("a");
      link.className="primary task-photo-button";
      link.href=workflowPhotoUrl(task,resource);
      link.textContent=resource.status==="capturing"?"Continuar foto":"Hacer foto";
      row.append(link);
    }else if(resource.status!=="submitted"&&resource.requires_accept&&task.status==="pending"){
      const note=document.createElement("span");
      note.className="task-photo-wait";
      note.textContent="Acepta la tarea primero";
      row.append(note);
    }

    box.append(row);
  });

  if(task.status==="waiting_review"&&canManageTask(task)){
    const reviewLink=document.createElement("a");
    reviewLink.className="primary task-photo-button";
    reviewLink.href=workflowPhotoReviewUrl(task);
    reviewLink.textContent="Revisar evidencias";
    box.append(reviewLink);
  }

  article.append(box);
}

async function applyChecklistItem(task,item,completed,checkbox){
  const previous=!completed;
  const {storageKey,key}=checklistRequestKey(task,item.key,completed);
  checkbox.disabled=true;
  setStatus("Guardando checklist y comprobando el cierre del flujo…");

  const {data,error}=await supabase.rpc("set_workflow_checklist_item_v1",{
    p_task_id:task.id,
    p_item_key:item.key,
    p_completed:completed,
    p_request_key:key
  });

  if(error){
    checkbox.checked=previous;
    checkbox.disabled=false;
    const message=String(error.message||"");
    if(message.includes("workflow_")&&!message.includes("network"))sessionStorage.removeItem(storageKey);
    setStatus(errorText(error),true);
    return;
  }

  sessionStorage.removeItem(storageKey);
  const result=Array.isArray(data)?data[0]:null;
  if(result?.applied_new===false){
    setStatus("El reintento recuperó el cambio ya aplicado; no se duplicó el histórico.");
  }else if(result?.execution_status==="completed"){
    setStatus("Checklist completado. Tarea y ejecución cerradas.");
  }else if(result?.execution_status==="waiting_review"){
    setStatus("Checklist completado. La ejecución queda esperando revisión humana.");
  }else{
    setStatus("Checklist actualizado.");
  }
  await load(true);
}

function renderChecklist(task,article){
  const execution=executionForTask(task);
  if(!execution||execution.spec_snapshot?.steps?.checklist!==true)return;
  const items=Array.isArray(execution.checklist_state)?execution.checklist_state:[];
  if(!items.length)return;

  const required=items.filter(item=>item.required!==false);
  const completedRequired=required.filter(item=>item.completed===true).length;
  const box=document.createElement("section");
  box.className="task-checklist";

  const head=document.createElement("div");
  head.className="task-checklist-head";
  const headingBox=document.createElement("div");
  const heading=document.createElement("strong");
  heading.textContent="Checklist";
  const progress=document.createElement("span");
  progress.className="task-checklist-progress";
  progress.textContent=completedRequired+" de "+required.length+" obligatorios completados";
  headingBox.append(heading,progress);
  head.append(headingBox);
  box.append(head);

  const itemBox=document.createElement("div");
  itemBox.className="task-checklist-items";
  const requiresAccept=execution.spec_snapshot?.steps?.accept===true;
  const assignee=task.assigned_user_id===currentUser?.id;
  const actionable=["pending","active"].includes(task.status);
  const blockedByAccept=requiresAccept&&task.status==="pending";

  items.forEach(item=>{
    const label=document.createElement("label");
    label.className="task-checklist-item"+(item.completed?" is-complete":"");
    const checkbox=document.createElement("input");
    checkbox.type="checkbox";
    checkbox.checked=item.completed===true;
    checkbox.disabled=!assignee||!actionable||blockedByAccept;
    checkbox.setAttribute("aria-label",(item.completed?"Desmarcar ":"Marcar ")+String(item.text||"elemento"));
    checkbox.addEventListener("change",()=>applyChecklistItem(task,item,checkbox.checked,checkbox));

    const textBox=document.createElement("span");
    textBox.className="task-checklist-item-text";
    const text=document.createElement("span");
    text.textContent=item.text||"Elemento";
    const kind=document.createElement("small");
    kind.textContent=item.required===false?"Opcional":"Obligatorio";
    textBox.append(text,kind);
    label.append(checkbox,textBox);
    itemBox.append(label);
  });
  box.append(itemBox);

  if(blockedByAccept&&assignee){
    const note=document.createElement("p");
    note.className="task-checklist-wait";
    note.textContent="Acepta la tarea antes de completar el checklist.";
    box.append(note);
  }else if(!assignee){
    const note=document.createElement("p");
    note.className="task-checklist-wait";
    note.textContent="Solo la persona asignada puede modificar este checklist.";
    box.append(note);
  }
  article.append(box);
}

async function openWorkflowDocument(documentRow,button){
  const original=button.textContent;
  button.disabled=true;
  button.textContent="Abriendo…";

  const preview=window.open("about:blank","_blank");
  if(preview)preview.opener=null;

  const {data,error}=await supabase.storage
    .from(DOCUMENT_BUCKET)
    .createSignedUrl(documentRow.storage_path,300);

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

async function uploadWorkflowDocument(task,file,button,input){
  if(!DOCUMENT_TYPES.has(file.type)){
    input.value="";
    setStatus("Solo se admiten PDF, JPG, PNG o WebP.",true);
    return;
  }
  if(file.size<1||file.size>DOCUMENT_MAX_BYTES){
    input.value="";
    setStatus("El archivo debe tener un tamaño máximo de 10 MB.",true);
    return;
  }

  const {storageKey,key}=documentRequestKey(task,file);
  const original=button.textContent;
  button.disabled=true;
  button.textContent="Preparando…";
  setStatus("Preparando el documento privado…");

  const {data:prepared,error:prepareError}=await supabase.rpc("prepare_workflow_document_upload_v1",{
    p_task_id:task.id,
    p_original_filename:file.name,
    p_mime_type:file.type,
    p_size_bytes:file.size,
    p_request_key:key
  });

  const preparation=Array.isArray(prepared)?prepared[0]:null;
  if(prepareError||!preparation?.document_id||!preparation?.storage_path){
    button.disabled=false;
    button.textContent=original;
    input.value="";
    const message=String(prepareError?.message||"");
    if(message.includes("workflow_")&&!message.includes("network"))sessionStorage.removeItem(storageKey);
    setStatus(errorText(prepareError),true);
    return;
  }

  button.textContent="Subiendo…";
  setStatus("Subiendo "+file.name+" de forma privada…");

  const {error:uploadError}=await supabase.storage
    .from(DOCUMENT_BUCKET)
    .upload(preparation.storage_path,file,{
      contentType:file.type,
      cacheControl:"3600",
      upsert:false
    });

  button.textContent="Confirmando…";

  const {data:submitted,error:submitError}=await supabase.rpc("submit_workflow_document_v1",{
    p_document_id:preparation.document_id,
    p_request_key:key
  });

  button.textContent=original;
  input.value="";

  if(submitError){
    button.disabled=false;
    const missing=String(submitError.message||"").includes("workflow_document_object_missing");
    if(!missing&&String(submitError.message||"").includes("workflow_"))sessionStorage.removeItem(storageKey);
    if(uploadError&&missing){
      setStatus("No se pudo completar la carga. Selecciona el mismo archivo para reintentar.",true);
    }else{
      setStatus(errorText(submitError),true);
    }
    return;
  }

  sessionStorage.removeItem(storageKey);
  const result=Array.isArray(submitted)?submitted[0]:null;

  if(result?.applied_new===false){
    setStatus("El documento ya estaba confirmado; no se duplicó la evidencia.");
  }else if(result?.execution_status==="completed"){
    setStatus("Documento adjuntado. Tarea y ejecución cerradas.");
  }else if(result?.execution_status==="waiting_review"){
    setStatus("Documento adjuntado. La ejecución queda esperando revisión humana.");
  }else{
    setStatus("Documento adjuntado. El flujo sigue activo porque quedan otros pasos.");
  }

  await load(true);
}

function renderDocuments(task,article){
  const execution=executionForTask(task);
  if(!execution||execution.spec_snapshot?.steps?.document!==true)return;

  const documents=(documentsByExecution.get(task.source_id)||[])
    .slice()
    .sort((a,b)=>new Date(a.created_at)-new Date(b.created_at));
  const submitted=documents.filter(item=>item.status==="submitted");
  const uploading=documents.filter(item=>item.status==="uploading");

  const box=document.createElement("section");
  box.className="task-documents";

  const head=document.createElement("div");
  head.className="task-documents-head";
  const headingBox=document.createElement("div");
  const heading=document.createElement("strong");
  heading.textContent="Documento";
  const progress=document.createElement("span");
  progress.className="task-documents-progress";
  progress.textContent=submitted.length
    ?submitted.length+" adjunto"+(submitted.length===1?"":"s")
    :"Pendiente";
  headingBox.append(heading,progress);
  head.append(headingBox);
  box.append(head);

  if(submitted.length){
    const rows=document.createElement("div");
    rows.className="task-document-list";
    submitted.forEach(documentRow=>{
      const row=document.createElement("div");
      row.className="task-document-row";

      const info=document.createElement("div");
      info.className="task-document-info";
      const name=document.createElement("span");
      name.textContent=documentRow.original_filename;
      const metaLine=document.createElement("small");
      metaLine.textContent=fmtBytes(documentRow.size_bytes)+" · "+fmtDate(documentRow.submitted_at||documentRow.created_at);
      info.append(name,metaLine);

      const open=document.createElement("button");
      open.type="button";
      open.className="secondary task-document-open";
      open.textContent="Abrir";
      open.addEventListener("click",()=>openWorkflowDocument(documentRow,open));

      row.append(info,open);
      rows.append(row);
    });
    box.append(rows);
  }

  const requiresAccept=execution.spec_snapshot?.steps?.accept===true;
  const assignee=task.assigned_user_id===currentUser?.id;
  const actionable=["pending","active"].includes(task.status);
  const blockedByAccept=requiresAccept&&task.status==="pending";

  if(assignee&&actionable&&!blockedByAccept){
    const input=document.createElement("input");
    input.type="file";
    input.hidden=true;
    input.accept="application/pdf,image/jpeg,image/png,image/webp";
    input.setAttribute("aria-label","Seleccionar documento");

    const add=document.createElement("button");
    add.type="button";
    add.className="primary task-document-add";
    add.textContent=submitted.length?"Adjuntar otro":"Adjuntar documento";
    add.addEventListener("click",()=>input.click());
    input.addEventListener("change",()=>{
      const file=input.files?.[0];
      if(file)uploadWorkflowDocument(task,file,add,input);
    });

    box.append(input,add);
  }else if(blockedByAccept&&assignee){
    const note=document.createElement("p");
    note.className="task-document-wait";
    note.textContent="Acepta la tarea antes de adjuntar el documento.";
    box.append(note);
  }else if(!assignee&&!submitted.length){
    const note=document.createElement("p");
    note.className="task-document-wait";
    note.textContent="El documento debe adjuntarlo la persona asignada.";
    box.append(note);
  }

  if(uploading.length&&assignee&&actionable){
    const note=document.createElement("p");
    note.className="task-document-wait";
    note.textContent="Hay una carga sin confirmar. Si fue interrumpida, selecciona el mismo archivo para reintentar.";
    box.append(note);
  }

  article.append(box);
}

function renderActions(task,article){
  if(task.source_kind!=="workflow_execution")return;

  const available=(actionsByTask.get(task.id)||[])
    .filter(action=>action.active&&action.from_status===task.status&&canRenderWorkflowAction(task,action))
    .sort((a,b)=>(a.sort_order||0)-(b.sort_order||0));

  if(!available.length){
    const note=document.createElement("div");note.className="task-note";
    note.textContent=actionNote(task);
    article.append(note);
    return;
  }

  const box=document.createElement("div");box.className="task-actions";
  const heading=document.createElement("strong");heading.textContent="Acciones";
  box.append(heading);

  available.forEach(action=>{
    const button=document.createElement("button");
    button.type="button";
    button.className=["reject","review_reject"].includes(action.action_key)?"secondary task-action--reject":"primary";
    button.textContent=action.label;
    button.addEventListener("click",()=>applyWorkflowAction(task,action,button));
    box.append(button);

    if(action.action_key==="review_approve"){
      const note=document.createElement("span");note.className="task-action-note";
      note.textContent="Aprobar cerrará la tarea y la ejecución.";
      box.append(note);
    }else if(action.action_key==="review_reject"){
      const note=document.createElement("span");note.className="task-action-note";
      note.textContent="Rechazar requiere un motivo y deja el workflow en estado Rechazado.";
      box.append(note);
    }else if(action.to_status==="completed"){
      const note=document.createElement("span");note.className="task-action-note";
      note.textContent="Esta es la única etapa pendiente; al aceptar se cerrarán tarea y ejecución.";
      box.append(note);
    }else if(action.to_status==="waiting_review"){
      const note=document.createElement("span");note.className="task-action-note";
      note.textContent="Después de aceptar quedará pendiente la revisión humana.";
      box.append(note);
    }
  });

  article.append(box);
}
function render(){
  list.replaceChildren();
  const rows=visibleTasks();
  if(!rows.length){
    const empty=document.createElement("article");empty.className="task-empty";
    empty.textContent=filter.value==="mine"?"No tienes tareas asignadas en este filtro.":"No hay tareas visibles con este filtro.";
    list.append(empty);
    updateBulkState();
    return;
  }

  rows.forEach(task=>{
    const article=document.createElement("article");article.className="task-card";
    article.dataset.taskId=task.id;
    if(selectedTaskIds.has(task.id))article.classList.add("is-selected");

    const selector=document.createElement("button");
    selector.type="button";
    selector.className="task-select-indicator";
    selector.setAttribute("aria-pressed",String(selectedTaskIds.has(task.id)));
    selector.setAttribute("aria-label",(selectedTaskIds.has(task.id)?"Deseleccionar ":"Seleccionar ")+(task.title||"tarea"));
    selector.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6.5 12.5 3.2 3.2L17.8 8"/></svg>';
    selector.addEventListener("click",event=>{
      event.stopPropagation();
      toggleTaskSelection(task,article);
    });
    article.append(selector);

    const head=document.createElement("div");head.className="task-head";
    const title=document.createElement("h2");title.textContent=task.title;
    const badges=document.createElement("div");badges.className="task-badges";
    if(task.source_kind==="workflow_execution"){
      const source=document.createElement("span");source.className="task-badge task-badge--workflow";source.textContent="Workflow";
      badges.append(source);
    }
    const state=document.createElement("span");state.className="task-badge";state.textContent=statusLabels[task.status]||task.status;
    badges.append(state);
    head.append(title,badges);

    article.append(head);

    if(task.description){
      const description=document.createElement("p");description.className="task-description";description.textContent=task.description;
      article.append(description);
    }

    const details=document.createElement("div");details.className="task-meta";
    details.append(
      meta("Ámbito",scopeLabel(task)),
      meta("Asignada a",assigneeLabel(task)),
      meta("Creada",fmtDate(task.created_at)),
      meta("Origen",task.source_kind==="workflow_execution"?"Ejecución de flujo":task.origin==="automatic"?"Automática":"Manual")
    );
    article.append(details);

    renderPhotoResources(task,article);
    renderChecklist(task,article);
    renderDocuments(task,article);
    renderActions(task,article);

    article.addEventListener("click",event=>{
      if(!selectionMode)return;
      if(event.target.closest(".task-select-indicator"))return;
      event.preventDefault();
      toggleTaskSelection(task,article);
    });
    bindTaskLongPress(article,task);
    list.append(article);
  });
  updateBulkState();
}

async function applyWorkflowAction(task,action,button){
  let note=null;
  if(action.requires_note){
    note=window.prompt(["reject","review_reject"].includes(action.action_key)?"Indica el motivo del rechazo:":"Añade la nota obligatoria para esta acción:");
    if(note===null)return;
    if(!note.trim()){
      setStatus("Esta acción requiere una nota.",true);
      return;
    }
  }

  const {storageKey,key}=requestKey(task,action);
  const original=button.textContent;
  button.disabled=true;
  button.textContent="Aplicando…";
  setStatus("Aplicando la acción sobre tarea y ejecución en una única transacción…");

  const {data,error}=await supabase.rpc("apply_workflow_task_action_v1",{
    p_task_id:task.id,
    p_action_key:action.action_key,
    p_request_key:key,
    p_note:note
  });

  button.textContent=original;

  if(error){
    button.disabled=false;
    const message=String(error.message||"");
    if(message.includes("workflow_")&&!message.includes("network"))sessionStorage.removeItem(storageKey);
    setStatus(errorText(error),true);
    return;
  }

  sessionStorage.removeItem(storageKey);
  const result=Array.isArray(data)?data[0]:null;
  const label=statusLabels[result?.task_status]||result?.task_status||"actualizado";

  if(result?.applied_new===false){
    setStatus("El reintento recuperó la transición ya aplicada; no se duplicó el histórico.");
  }else if(action.action_key==="review_approve"){
    setStatus("Revisión aprobada. Tarea y ejecución completadas.");
  }else if(action.action_key==="review_reject"){
    setStatus("Revisión rechazada. El motivo quedó registrado.");
  }else{
    setStatus("Tarea y ejecución actualizadas juntas: "+label+".");
  }

  await load(true);
}

async function loadManagerAccess(){
  managerOrganizationIds=new Set();
  rootManager=false;
  if(!currentUser?.id)return;

  const {data,error}=await supabase
    .from("user_roles")
    .select("role,organization_id,revoked_at")
    .eq("user_id",currentUser.id)
    .is("revoked_at",null);

  if(error)throw error;

  (data||[]).forEach(row=>{
    if(row.role==="root")rootManager=true;
    if(row.role==="admin"&&row.organization_id)managerOrganizationIds.add(row.organization_id);
  });
}

async function loadRelated(){
  properties=new Map();
  rooms=new Map();
  profiles=new Map();

  const propertyIds=[...new Set(tasks.map(task=>task.property_id).filter(Boolean))];
  if(propertyIds.length){
    const {data}=await supabase.from("properties_v2").select("id,name,address_line").in("id",propertyIds);
    (data||[]).forEach(item=>properties.set(item.id,item));
  }

  const roomIds=[...new Set(tasks.map(task=>task.room_id).filter(Boolean))];
  if(roomIds.length){
    const {data}=await supabase.from("rooms_v2").select("id,property_id,label").in("id",roomIds);
    (data||[]).forEach(item=>rooms.set(item.id,item));
  }

  const userIds=[...new Set(tasks.map(task=>task.assigned_user_id).filter(Boolean))];
  if(userIds.length){
    const {data}=await supabase.from("profiles").select("user_id,display_name,email").in("user_id",userIds);
    (data||[]).forEach(item=>profiles.set(item.user_id,item));
  }
}

async function loadWorkflowExecutions(){
  workflowExecutionsById=new Map();
  const executionIds=[...new Set(tasks
    .filter(task=>task.source_kind==="workflow_execution"&&task.source_id)
    .map(task=>task.source_id))];
  if(!executionIds.length)return;

  const {data,error}=await supabase
    .from("workflow_executions_v2")
    .select("id,status,spec_snapshot,checklist_state")
    .in("id",executionIds);

  if(error)throw error;
  (data||[]).forEach(execution=>workflowExecutionsById.set(execution.id,execution));
}

async function loadPhotoResources(){
  photoResourcesByExecution=new Map();
  const executionIds=[...new Set(tasks
    .filter(task=>task.source_kind==="workflow_execution"&&task.source_id)
    .map(task=>task.source_id))];
  if(!executionIds.length)return;

  const {data,error}=await supabase
    .from("workflow_execution_photo_resources_v2")
    .select("id,execution_id,pattern_id,pattern_version,pattern_snapshot,sort_order,requires_accept,status,photo_run_id")
    .in("execution_id",executionIds)
    .order("sort_order");

  if(error)throw error;

  (data||[]).forEach(resource=>{
    const bucket=photoResourcesByExecution.get(resource.execution_id)||[];
    bucket.push(resource);
    photoResourcesByExecution.set(resource.execution_id,bucket);
  });
}

async function loadDocuments(){
  documentsByExecution=new Map();
  const executionIds=[...new Set(tasks
    .filter(task=>task.source_kind==="workflow_execution"&&task.source_id)
    .map(task=>task.source_id))];
  if(!executionIds.length)return;

  const {data,error}=await supabase
    .from("workflow_execution_documents_v2")
    .select("id,execution_id,task_id,organization_id,uploaded_by,original_filename,mime_type,size_bytes,storage_path,status,created_at,submitted_at")
    .in("execution_id",executionIds)
    .order("created_at");

  if(error){
    const message=String(error.message||"");
    if(message.includes("workflow_execution_documents_v2")&&message.toLowerCase().includes("does not exist"))return;
    throw error;
  }

  (data||[]).forEach(documentRow=>{
    const bucket=documentsByExecution.get(documentRow.execution_id)||[];
    bucket.push(documentRow);
    documentsByExecution.set(documentRow.execution_id,bucket);
  });
}

async function loadActions(){
  actionsByTask=new Map();
  const workflowIds=tasks
    .filter(task=>task.source_kind==="workflow_execution")
    .map(task=>task.id);
  if(!workflowIds.length)return;

  const {data,error}=await supabase
    .from("tenant_task_actions_v2")
    .select("id,task_id,action_key,label,from_status,to_status,requires_note,sort_order,active,actor")
    .in("task_id",workflowIds)
    .eq("active",true)
    .order("sort_order");

  if(error)throw error;

  (data||[]).forEach(action=>{
    const bucket=actionsByTask.get(action.task_id)||[];
    bucket.push(action);
    actionsByTask.set(action.task_id,bucket);
  });
}

async function load(preserveStatus=false){
  const {data:userData,error:userError}=await supabase.auth.getUser();
  if(userError||!userData?.user){
    list.replaceChildren();
    setStatus("No se pudo validar la sesión.",true);
    return;
  }
  currentUser=userData.user;

  const {data,error}=await supabase
    .from("tenant_tasks_v2")
    .select("id,organization_id,tenant_id,property_id,room_id,task_type,origin,title,description,status,due_at,assigned_user_id,source_kind,source_id,created_at,removed_at")
    .is("removed_at",null)
    .order("created_at",{ascending:false})
    .limit(100);

  if(error){
    list.replaceChildren();
    const empty=document.createElement("article");empty.className="task-empty";
    empty.textContent="No se pudieron cargar las tareas autorizadas.";
    list.append(empty);
    setStatus("La consulta fue rechazada o el servicio no está disponible.",true);
    return;
  }

  tasks=data||[];

  try{
    await Promise.all([loadManagerAccess(),loadRelated(),loadActions(),loadWorkflowExecutions(),loadPhotoResources(),loadDocuments()]);
  }catch{
    list.replaceChildren();
    const empty=document.createElement("article");empty.className="task-empty";
    empty.textContent="No se pudieron cargar todos los datos operativos de las tareas.";
    list.append(empty);
    setStatus("La tarea existe, pero sus datos relacionados no pudieron consultarse.",true);
    return;
  }

  render();

  const workflowCount=tasks.filter(task=>task.source_kind==="workflow_execution").length;
  if(!preserveStatus){
    setStatus(tasks.length+" tarea"+(tasks.length===1?"":"s")+" visible"+(tasks.length===1?"":"s")+(workflowCount?" · "+workflowCount+" generada"+(workflowCount===1?"":"s")+" por workflow.":"."));
  }
}

async function bulkDeleteSelected(){
  const selected=selectedTasks();
  const eligible=selectedDeletableTasks();
  const skipped=selected.length-eligible.length;
  if(!eligible.length){
    setStatus("Las tareas seleccionadas siguen abiertas o no pueden ser gestionadas por tu usuario.",true);
    return;
  }

  const message="Se eliminarán de Tareas "+eligible.length+" tarjeta"+(eligible.length===1?"":"s")+" ya cerrada"+(eligible.length===1?"":"s")+". "
    +"El historial, la ejecución y sus evidencias se conservarán."
    +(skipped?" "+skipped+" seleccionada"+(skipped===1?" se omitirá":"s se omitirán")+" porque sigue abierta o no es gestionable.":"")
    +" ¿Continuar?";
  if(!window.confirm(message))return;

  bulkDelete.disabled=true;
  setStatus("Eliminando "+eligible.length+" tarjeta"+(eligible.length===1?"":"s")+"…");

  let ok=0;
  const failures=[];
  for(const task of eligible){
    const {error}=await supabase.rpc("delete_task_card_v1",{p_task_id:task.id});
    if(error)failures.push({task,error});
    else{
      ok++;
      selectedTaskIds.delete(task.id);
    }
  }

  await load(true);
  if(!selectedTaskIds.size)setSelectionMode(false);

  if(failures.length){
    setStatus(ok+" eliminada"+(ok===1?"":"s")+" · "+failures.length+" no se pudieron eliminar. "+errorText(failures[0].error),true);
  }else{
    setStatus(ok+" tarjeta"+(ok===1?" eliminada.":"s eliminadas."));
  }
}

selectionToggle?.addEventListener("click",()=>setSelectionMode(true));
selectionClose?.addEventListener("click",clearSelection);
selectionMenuToggle?.addEventListener("click",event=>{
  event.stopPropagation();
  const open=selectionMenu.hidden;
  selectionMenu.hidden=!open;
  selectionMenuToggle.setAttribute("aria-expanded",String(open));
});
selectionMenu?.addEventListener("click",event=>event.stopPropagation());
selectVisible?.addEventListener("click",()=>{
  visibleTasks().forEach(task=>selectedTaskIds.add(task.id));
  closeSelectionMenu();
  render();
});
deselectVisible?.addEventListener("click",()=>{
  visibleTasks().forEach(task=>selectedTaskIds.delete(task.id));
  closeSelectionMenu();
  render();
});
document.addEventListener("click",event=>{
  if(!selectionMenu?.hidden&&!event.target.closest(".tasks-selection-menu-wrap"))closeSelectionMenu();
});
document.addEventListener("keydown",event=>{
  if(event.key!=="Escape")return;
  if(selectionMenu&&!selectionMenu.hidden){
    closeSelectionMenu();
    selectionMenuToggle?.focus();
    return;
  }
  if(selectionMode)clearSelection();
});
bulkDelete?.addEventListener("click",bulkDeleteSelected);

filter.addEventListener("change",()=>{
  if(selectionMode)selectedTaskIds.clear();
  render();
});
load();
