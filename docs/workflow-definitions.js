import { supabase } from "./supabase-client.js";

const list=document.getElementById("workflowDefinitions");
const status=document.getElementById("definitionsStatus");

const topbar=document.getElementById("definitionsTopbar");
const normalHeader=document.getElementById("definitionsNormalHeader");
const searchHeader=document.getElementById("definitionsSearchHeader");
const selectionHeader=document.getElementById("definitionsSelectionHeader");

const searchToggle=document.getElementById("workflowSearchToggle");
const searchInput=document.getElementById("workflowSearch");
const searchClose=document.getElementById("workflowSearchClose");
const searchClear=document.getElementById("workflowSearchClear");
const activeFilter=document.getElementById("workflowActiveFilter");
const activeFilterText=document.getElementById("workflowActiveFilterText");

const selectionToggle=document.getElementById("workflowSelectionToggle");
const selectionClose=document.getElementById("workflowSelectionClose");
const selectionSummary=document.getElementById("workflowSelectionSummary");
const selectionMenuToggle=document.getElementById("workflowSelectionMenuToggle");
const selectionMenu=document.getElementById("workflowSelectionMenu");
const selectVisible=document.getElementById("workflowSelectVisible");
const deselectVisible=document.getElementById("workflowDeselectVisible");

const bulkDock=document.getElementById("workflowBulkDock");
const bulkExecute=document.getElementById("workflowBulkExecute");
const bulkDelete=document.getElementById("workflowBulkDelete");
const bulkArchive=document.getElementById("workflowBulkArchive");
const bulkExecuteCount=document.getElementById("workflowBulkExecuteCount");
const bulkDeleteCount=document.getElementById("workflowBulkDeleteCount");
const bulkArchiveCount=document.getElementById("workflowBulkArchiveCount");

const params=new URLSearchParams(window.location.search);
const highlightedDefinition=params.get("published")||"";

let versionsByDefinition=new Map();
let revisionDraftByDefinition=new Map();
let applicationsByDefinition=new Map();
let executionsByDefinition=new Map();
let schedulesByApplication=new Map();
let propertyById=new Map();
let roomById=new Map();
let occupancyById=new Map();
let publishedRows=[];
let filteredRows=[];
let selectionMode=false;
let searchMode=false;
const selectedIds=new Set();

const BATCH_EXECUTION_PREFIX="workflow-batch-execution:";

const labels={
  flowType:{cleaning:"Limpieza",inspection:"Inspección",maintenance:"Mantenimiento",checkin:"Check-in",checkout:"Check-out",custom:"Personalizado"},
  scopeType:{property:"Un piso",organization:"Toda la organización",room:"Una habitación",occupancy:"Una ocupación / inquilino"},
  triggerType:{manual:"Manual",recurring:"Recurrente",scheduled_once:"Fecha concreta",event:"Por evento"},
  recurrence:{weekly:"Cada semana",biweekly:"Cada 2 semanas",monthly:"Cada mes",custom:"Personalizada"},
  customUnit:{day:"día(s)",week:"semana(s)",month:"mes(es)"},
  assignmentType:{property_responsible:"Responsable operativo del piso",active_occupants_rotation:"Ocupantes activos en rotación",fixed_person:"Persona fija",role:"Rol o capacidad",manual:"Se decide al iniciar"}
};

function text(group,key){return labels[group]?.[key]||key||"Pendiente"}
function setStatus(message,error=false){
  const span=status?.querySelector("span:last-child");
  if(span)span.textContent=message;
  status?.classList.toggle("error",error);
}
function dateTime(value){
  if(!value)return "Nunca";
  try{return new Intl.DateTimeFormat("es-ES",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value))}catch{return value}
}
function scheduledDateTime(spec){
  const utc=String(spec?.scheduledAtUtc||"").trim();
  const timezone=String(spec?.scheduledTimezone||"").trim();
  if(utc&&timezone){
    try{
      return new Intl.DateTimeFormat("es-ES",{
        dateStyle:"medium",
        timeStyle:"short",
        timeZone:timezone
      }).format(new Date(utc))+" · "+timezone;
    }catch{}
  }
  return String(spec?.scheduledAt||"").trim()||"Pendiente";
}
function isScheduledAutomatic(row){
  return ["scheduled_once","recurring"].includes(String(publishedSpec(row).triggerType||""));
}
function latestVersion(row){return versionsByDefinition.get(row.id)?.[0]||null}
function publishedSpec(row){return latestVersion(row)?.spec||{}}
function applicationsFor(row){return applicationsByDefinition.get(row.id)||[]}
function executionsFor(row){return executionsByDefinition.get(row.id)||[]}
function latestExecution(row){return executionsFor(row)[0]||null}
function hasHistory(row){return executionsFor(row).length>0}
function currentApplication(row){
  const latest=latestVersion(row);
  const apps=applicationsFor(row);
  return apps.find(app=>app.status==="configured"&&app.definition_version_id===latest?.id)
    || apps.find(app=>app.status==="configured")
    || null;
}
function scheduleFor(row){
  const app=currentApplication(row);
  return app?schedulesByApplication.get(app.id)||null:null;
}
function scheduleStatusText(row){
  const schedule=scheduleFor(row);
  if(!schedule)return null;
  if(schedule.status==="blocked")return "Programación bloqueada";
  if(schedule.status==="cancelled")return "Programación cancelada";
  if(schedule.status==="completed")return "Programación completada";
  if(schedule.status==="active"){
    const next=dateTime(schedule.next_run_at);
    return schedule.schedule_kind==="recurring"
      ?"Próxima · "+next
      :"Programada · "+next;
  }
  return null;
}
function activationText(row){
  const spec=publishedSpec(row);
  const trigger=String(spec.triggerType||"");
  const base=text("triggerType",trigger);
  if(trigger==="recurring"){
    const recurrence=String(spec.recurrence||"");
    const first=scheduledDateTime(spec);
    if(!recurrence)return base+" · desde "+first;
    if(recurrence==="custom"){
      const every=String(spec.customEvery||"").trim();
      const unit=String(spec.customUnit||"");
      return every&&unit
        ?base+" · Cada "+every+" "+text("customUnit",unit)+" · desde "+first
        :base+" · "+text("recurrence",recurrence)+" · desde "+first;
    }
    return base+" · "+text("recurrence",recurrence)+" · desde "+first;
  }
  if(trigger==="scheduled_once"){
    return base+" · "+scheduledDateTime(spec);
  }
  return base;
}
function meta(label,value,{className=""}={}){
  const box=document.createElement("div");
  box.className="definition-meta-item"+(className?" "+className:"");
  const strong=document.createElement("strong");strong.textContent=label;
  const span=document.createElement("span");span.textContent=value||"—";
  box.append(strong,span);return box;
}
function executionMeta(row){
  const count=executionsFor(row).length;
  const latest=latestExecution(row);
  const box=document.createElement("div");
  box.className="definition-meta-item";
  const strong=document.createElement("strong");strong.textContent="Ejecuciones";
  const value=document.createElement("span");
  value.className="definition-execution-value";
  value.textContent=String(count)+" · "+(latest?"última "+dateTime(latest.created_at):"nunca ejecutado");
  box.append(strong,value);
  return box;
}
function targetText(app){
  if(!app)return "Sin destino configurado";
  if(app.scope_type==="organization")return "Toda la organización";
  const property=propertyById.get(app.property_id);
  if(app.scope_type==="property")return property?.name||"Piso";
  if(app.scope_type==="room"){
    const room=roomById.get(app.room_id);
    return [property?.name,room?.label||"Habitación"].filter(Boolean).join(" · ");
  }
  if(app.scope_type==="occupancy"){
    const occupancy=occupancyById.get(app.occupancy_id);
    const person=occupancy?.tenants_v2?.full_name||occupancy?.occupant_email||"Ocupación";
    return [property?.name,person].filter(Boolean).join(" · ");
  }
  return "Destino";
}
function errorText(error){
  const message=String(error?.message||"");
  if(message.includes("aal2_required"))return "Esta operación requiere MFA (sesión AAL2).";
  if(message.includes("workflow_definition_has_history"))return "Este flujo ya tiene historial y no puede eliminarse.";
  if(message.includes("workflow_unexecuted_delete_instead"))return "Este flujo nunca se ha ejecutado; elimínalo en lugar de archivarlo.";
  if(message.includes("workflow_definition_delete_forbidden")||message.includes("workflow_definition_archive_forbidden"))return "No tienes permiso para realizar esta operación.";
  if(message.includes("workflow_revision_requires_published_definition"))return "Este flujo ya no está disponible para edición.";
  if(message.includes("workflow_author_role_required"))return "Tu sesión no tiene autorización para editar flujos.";
  return "No se pudo completar la operación.";
}

async function startRevision(row,button){
  button.disabled=true;
  const original=button.textContent;
  button.textContent="Preparando…";
  setStatus("Preparando la edición sin alterar el historial actual…");
  const {data,error}=await supabase.rpc("start_workflow_definition_revision_v1",{p_definition_id:row.id});
  if(error){
    button.disabled=false;
    button.textContent=original;
    setStatus(errorText(error),true);
    return;
  }
  const result=Array.isArray(data)?data[0]:null;
  window.location.href="./workflow-builder.html?id="+encodeURIComponent(row.id)+"&revision=1&base="+encodeURIComponent(result?.base_version||"");
}

async function deleteDefinition(row,button){
  if(!window.confirm("Este flujo nunca se ha ejecutado. Eliminarlo lo quitará definitivamente de Mis Flujos y no se conservará como historial. ¿Eliminar?"))return;
  button.disabled=true;
  const original=button.textContent;
  button.textContent="Eliminando…";
  setStatus("Eliminando flujo sin ejecuciones…");
  const {error}=await supabase.rpc("delete_unexecuted_workflow_v1",{p_definition_id:row.id});
  if(error){
    button.disabled=false;
    button.textContent=original;
    setStatus(errorText(error),true);
    return;
  }
  setStatus("Flujo eliminado. No existían tareas ni ejecuciones que conservar.");
  await load();
}

async function archiveDefinition(row,button){
  if(!window.confirm("Este flujo ya tiene historial. Se conservarán sus versiones, ejecuciones y tareas, pero dejará de estar disponible para nuevas ejecuciones. ¿Archivar?"))return;
  button.disabled=true;
  const original=button.textContent;
  button.textContent="Archivando…";
  setStatus("Archivando flujo y conservando su historial…");
  const {error}=await supabase.rpc("archive_workflow_definition_v1",{p_definition_id:row.id});
  if(error){
    button.disabled=false;
    button.textContent=original;
    setStatus(errorText(error),true);
    return;
  }
  setStatus("Flujo archivado. Su historial permanece intacto.");
  await load();
}

function rowSearchText(row){
  const spec=publishedSpec(row);
  const app=currentApplication(row);
  return [
    spec.flowName,row.name,
    text("flowType",String(spec.flowType||"")),
    targetText(app),
    activationText(row),
    text("assignmentType",String(spec.assignmentType||"")),
    "v"+(latestVersion(row)?.version||"")
  ].filter(Boolean).join(" ").toLocaleLowerCase("es");
}
function rowMatchesSearch(row){
  const query=String(searchInput?.value||"").trim().toLocaleLowerCase("es");
  return !query||rowSearchText(row).includes(query);
}
function selectedRows(){
  return publishedRows.filter(row=>selectedIds.has(row.id));
}
function selectedDeletableRows(){
  return selectedRows().filter(row=>!hasHistory(row));
}
function selectedArchivableRows(){
  return selectedRows().filter(row=>hasHistory(row));
}

function closeSelectionMenu(){
  if(!selectionMenu||!selectionMenuToggle)return;
  selectionMenu.hidden=true;
  selectionMenuToggle.setAttribute("aria-expanded","false");
}

function setHeaderMode(mode){
  searchMode=mode==="search";
  normalHeader.hidden=mode!=="normal";
  searchHeader.hidden=mode!=="search";
  selectionHeader.hidden=mode!=="selection";
  topbar?.classList.toggle("is-searching",mode==="search");
  topbar?.classList.toggle("is-selecting",mode==="selection");
  if(mode!=="selection")closeSelectionMenu();
}

function syncFilterChip(){
  const query=String(searchInput?.value||"").trim();
  if(activeFilterText)activeFilterText.textContent=query;
  if(activeFilter)activeFilter.hidden=!query||searchMode;
}

function openSearch(){
  if(selectionMode)return;
  setHeaderMode("search");
  syncFilterChip();
  requestAnimationFrame(()=>{
    searchInput?.focus({preventScroll:true});
    searchInput?.select();
  });
}

function closeSearch({clear=false}={}){
  if(clear&&searchInput){
    searchInput.value="";
    renderDefinitions();
  }
  setHeaderMode(selectionMode?"selection":"normal");
  syncFilterChip();
}

function setSelectionMode(enabled,{selectId=null}={}){
  selectionMode=enabled;
  document.body.classList.toggle("definitions-selection-active",enabled);
  list.classList.toggle("is-selecting",enabled);

  if(enabled){
    searchMode=false;
    if(selectId)selectedIds.add(selectId);
    setHeaderMode("selection");
  }else{
    selectedIds.clear();
    setHeaderMode("normal");
  }

  renderDefinitions();
}

function updateBulkState(){
  const selected=selectedRows();
  const deletable=selected.filter(row=>!hasHistory(row));
  const archivable=selected.filter(row=>hasHistory(row));
  const executable=selected.filter(row=>!isScheduledAutomatic(row));

  if(selectionSummary){
    selectionSummary.textContent=selected.length
      +" seleccionado"+(selected.length===1?"":"s");
  }

  if(bulkDock)bulkDock.hidden=!selectionMode||selected.length===0;
  bulkExecute.disabled=executable.length===0;
  bulkDelete.disabled=deletable.length===0;
  bulkArchive.disabled=archivable.length===0;

  if(bulkExecuteCount)bulkExecuteCount.textContent=String(executable.length);
  if(bulkDeleteCount)bulkDeleteCount.textContent=String(deletable.length);
  if(bulkArchiveCount)bulkArchiveCount.textContent=String(archivable.length);

  const visibleIds=filteredRows.map(row=>row.id);
  const selectedVisible=visibleIds.filter(id=>selectedIds.has(id)).length;
  if(selectVisible)selectVisible.disabled=visibleIds.length===0||selectedVisible===visibleIds.length;
  if(deselectVisible)deselectVisible.disabled=selectedVisible===0;

  syncFilterChip();
}

function toggleRowSelection(row,article,force){
  const next=typeof force==="boolean"?force:!selectedIds.has(row.id);
  if(next)selectedIds.add(row.id);else selectedIds.delete(row.id);

  article?.classList.toggle("is-selected",next);
  const indicator=article?.querySelector(".definition-select-indicator");
  if(indicator){
    indicator.setAttribute("aria-pressed",String(next));
    indicator.setAttribute("aria-label",(next?"Deseleccionar ":"Seleccionar ")+(publishedSpec(row).flowName||row.name||"flujo"));
  }
  updateBulkState();
}

function bindLongPress(article,row){
  let timer=null;
  let startX=0;
  let startY=0;
  let longPressed=false;

  const clear=()=>{
    if(timer)clearTimeout(timer);
    timer=null;
  };

  article.addEventListener("pointerdown",event=>{
    if(selectionMode||event.button!==0)return;
    if(event.target.closest("a,button,input,select,textarea,label,summary"))return;

    longPressed=false;
    startX=event.clientX;
    startY=event.clientY;
    timer=setTimeout(()=>{
      longPressed=true;
      article.dataset.longPressed="1";
      setSelectionMode(true,{selectId:row.id});
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

function card(row){
  const version=latestVersion(row);
  const spec=publishedSpec(row);
  const draft=revisionDraftByDefinition.get(row.id)||null;
  const app=currentApplication(row);
  const history=hasHistory(row);

  const article=document.createElement("article");
  article.className="definition-card";
  if(row.id===highlightedDefinition)article.classList.add("is-highlighted");
  if(selectedIds.has(row.id))article.classList.add("is-selected");

  const selector=document.createElement("button");
  selector.type="button";
  selector.className="definition-select-indicator";
  selector.setAttribute("aria-pressed",String(selectedIds.has(row.id)));
  selector.setAttribute("aria-label",(selectedIds.has(row.id)?"Deseleccionar ":"Seleccionar ")+String(spec.flowName||row.name||"flujo"));
  selector.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6.5 12.5 3.2 3.2L17.8 8"/></svg>';
  selector.addEventListener("click",event=>{
    event.stopPropagation();
    toggleRowSelection(row,article);
  });
  article.append(selector);

  const head=document.createElement("div");head.className="definition-card-head";
  const headMain=document.createElement("div");headMain.className="definition-card-head-main";
  const title=document.createElement("h3");title.textContent=String(spec.flowName||row.name||"Flujo");
  headMain.append(title);

  const badge=document.createElement("span");
  badge.className="definition-badge "+(history?"definition-badge--complete":"definition-badge--incomplete");
  badge.textContent=history?"Con historial":"Sin ejecuciones";
  head.append(headMain,badge);

  const details=document.createElement("div");details.className="definition-meta";
  details.append(
    meta("Tipo",text("flowType",String(spec.flowType||""))),
    meta("Destino",targetText(app)),
    meta("Activación",activationText(row)),
    meta("Asignación",text("assignmentType",String(spec.assignmentType||""))),
    meta("Versión actual","v"+(version?.version||"?")),
    executionMeta(row)
  );
  const scheduleStatus=scheduleStatusText(row);
  if(scheduleStatus){
    details.append(meta("Programación",scheduleStatus,{
      className:scheduleFor(row)?.status==="blocked"?"definition-meta-item--warning":""
    }));
  }

  article.append(head,details);

  if(history&&draft){
    const note=document.createElement("div");note.className="definition-draft-note";
    note.textContent="Edición en curso. La configuración publicada y su historial siguen intactos.";
    article.append(note);
  }

  const actions=document.createElement("div");actions.className="definition-actions";

  if(!isScheduledAutomatic(row)){
    const execute=document.createElement("a");
    execute.className="primary";
    execute.textContent="Ejecutar";
    execute.href="./workflow-applications.html?definition="+encodeURIComponent(row.id)
      +"&setup=1&intent=execute&from=mis-flujos"
      +(app?"&application="+encodeURIComponent(app.id):"");
    actions.append(execute);
  }else{
    const automatic=document.createElement("span");
    automatic.className="definition-action-note";
    automatic.textContent="Ejecución automática";
    actions.append(automatic);
  }

  if(history){
    if(draft){
      const edit=document.createElement("a");
      edit.className="secondary";
      edit.href="./workflow-builder.html?id="+encodeURIComponent(row.id)+"&revision=1";
      edit.textContent="Editar";
      actions.append(edit);
    }else{
      const edit=document.createElement("button");
      edit.type="button";
      edit.className="secondary";
      edit.textContent="Editar";
      edit.addEventListener("click",()=>startRevision(row,edit));
      actions.append(edit);
    }

    const archive=document.createElement("button");
    archive.type="button";
    archive.className="danger-soft";
    archive.textContent="Archivar";
    archive.addEventListener("click",()=>archiveDefinition(row,archive));
    actions.append(archive);
  }else{
    const edit=document.createElement("a");
    edit.className="secondary";
    edit.href="./workflow-builder.html?id="+encodeURIComponent(row.id)+"&edit=1";
    edit.textContent="Editar";
    actions.append(edit);

    const remove=document.createElement("button");
    remove.type="button";
    remove.className="danger-soft";
    remove.textContent="Eliminar";
    remove.addEventListener("click",()=>deleteDefinition(row,remove));
    actions.append(remove);
  }

  article.append(actions);

  article.addEventListener("click",event=>{
    if(!selectionMode)return;
    if(event.target.closest(".definition-select-indicator"))return;
    event.preventDefault();
    toggleRowSelection(row,article);
  });
  bindLongPress(article,row);

  return article;
}

function emptyState(message="Todavía no hay flujos"){
  const article=document.createElement("article");article.className="definitions-empty";
  const h=document.createElement("h3");h.textContent=message;
  const p=document.createElement("p");
  p.textContent=publishedRows.length
    ?"Prueba con otro término de búsqueda."
    :"Los flujos aparecen aquí cuando completas el Creador y eliges Publicar o Ejecutar.";
  article.append(h,p);
  if(!publishedRows.length){
    const link=document.createElement("a");link.className="primary definitions-create";link.href="./workflow-builder.html";link.textContent="Crear flujo";
    article.append(link);
  }
  return article;
}

function renderDefinitions(){
  filteredRows=publishedRows.filter(rowMatchesSearch);
  list.replaceChildren();

  if(!filteredRows.length){
    list.append(emptyState(publishedRows.length?"No hay coincidencias":"Todavía no hay flujos"));
    updateBulkState();
    return;
  }

  filteredRows.forEach(row=>list.append(card(row)));
  updateBulkState();
}

async function bulkDeleteSelected(){
  const eligible=selectedDeletableRows();
  const skipped=selectedRows().length-eligible.length;
  if(!eligible.length)return;

  const message="Se eliminarán definitivamente "+eligible.length+" flujo"+(eligible.length===1?"":"s")+" sin historial."
    +(skipped?" "+skipped+" seleccionado"+(skipped===1?" tiene":"s tienen")+" historial y no se eliminará"+(skipped===1?"":"n")+".":"")
    +" ¿Continuar?";
  if(!window.confirm(message))return;

  bulkDelete.disabled=true;
  bulkArchive.disabled=true;
  bulkExecute.disabled=true;
  setStatus("Eliminando "+eligible.length+" flujo"+(eligible.length===1?"":"s")+"…");

  let ok=0;
  const failures=[];
  for(const row of eligible){
    const {error}=await supabase.rpc("delete_unexecuted_workflow_v1",{p_definition_id:row.id});
    if(error)failures.push({row,error});
    else{ok++;selectedIds.delete(row.id)}
  }

  await load({preserveSelection:true});
  if(!selectedIds.size)setSelectionMode(false);
  if(failures.length){
    setStatus(ok+" eliminado"+(ok===1?"":"s")+" · "+failures.length+" no se pudieron eliminar. "+errorText(failures[0].error),true);
  }else{
    setStatus(ok+" flujo"+(ok===1?" eliminado.":"s eliminados."));
  }
}

async function bulkArchiveSelected(){
  const eligible=selectedArchivableRows();
  const skipped=selectedRows().length-eligible.length;
  if(!eligible.length)return;

  const message="Se archivarán "+eligible.length+" flujo"+(eligible.length===1?"":"s")+" con historial. Sus tareas y ejecuciones se conservarán."
    +(skipped?" "+skipped+" seleccionado"+(skipped===1?" no tiene":"s no tienen")+" historial y no se archivará"+(skipped===1?"":"n")+".":"")
    +" ¿Continuar?";
  if(!window.confirm(message))return;

  bulkDelete.disabled=true;
  bulkArchive.disabled=true;
  bulkExecute.disabled=true;
  setStatus("Archivando "+eligible.length+" flujo"+(eligible.length===1?"":"s")+"…");

  let ok=0;
  const failures=[];
  for(const row of eligible){
    const {error}=await supabase.rpc("archive_workflow_definition_v1",{p_definition_id:row.id});
    if(error)failures.push({row,error});
    else{ok++;selectedIds.delete(row.id)}
  }

  await load({preserveSelection:true});
  if(!selectedIds.size)setSelectionMode(false);
  if(failures.length){
    setStatus(ok+" archivado"+(ok===1?"":"s")+" · "+failures.length+" no se pudieron archivar. "+errorText(failures[0].error),true);
  }else{
    setStatus(ok+" flujo"+(ok===1?" archivado.":"s archivados."));
  }
}

function startBulkExecution(){
  const allSelected=selectedRows();
  const selected=allSelected.filter(row=>!isScheduledAutomatic(row));
  const skipped=allSelected.length-selected.length;
  if(!selected.length){
    setStatus("Los flujos seleccionados de Fecha concreta se ejecutarán automáticamente en su programación.");
    return;
  }

  const confirmed=window.confirm(
    "Se prepararán "+selected.length+" flujo"+(selected.length===1?"":"s")+" para ejecución. "
    +(skipped?skipped+" flujo"+(skipped===1?" programado se omitirá. ":"s programados se omitirán. "):"")
    +"Si alguno necesita datos, el sistema te mostrará solo lo que falta antes de crear su tarea. ¿Continuar?"
  );
  if(!confirmed)return;

  const token=globalThis.crypto?.randomUUID?.()||("batch-"+Date.now()+"-"+Math.random().toString(36).slice(2));
  const queue={
    createdAt:Date.now(),
    index:0,
    items:selected.map(row=>({
      definitionId:row.id,
      applicationId:currentApplication(row)?.id||null,
      name:String(publishedSpec(row).flowName||row.name||"Flujo")
    }))
  };

  try{
    sessionStorage.setItem(BATCH_EXECUTION_PREFIX+token,JSON.stringify(queue));
  }catch{
    setStatus("No se pudo preparar la cola de ejecución en esta sesión.",true);
    return;
  }

  const first=queue.items[0];
  const url=new URL("./workflow-applications.html",window.location.href);
  url.searchParams.set("definition",first.definitionId);
  url.searchParams.set("setup","1");
  url.searchParams.set("intent","execute");
  url.searchParams.set("from","mis-flujos");
  url.searchParams.set("batch",token);
  url.searchParams.set("batch_index","0");
  if(first.applicationId)url.searchParams.set("application",first.applicationId);
  window.location.href=url.href;
}

searchToggle?.addEventListener("click",openSearch);
searchInput?.addEventListener("input",()=>{
  renderDefinitions();
  syncFilterChip();
});
searchClose?.addEventListener("click",()=>closeSearch({clear:false}));
searchClear?.addEventListener("click",()=>closeSearch({clear:true}));
activeFilter?.addEventListener("click",()=>{
  if(searchInput)searchInput.value="";
  renderDefinitions();
  syncFilterChip();
});

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
  filteredRows.forEach(row=>selectedIds.add(row.id));
  closeSelectionMenu();
  renderDefinitions();
});
deselectVisible?.addEventListener("click",()=>{
  filteredRows.forEach(row=>selectedIds.delete(row.id));
  closeSelectionMenu();
  renderDefinitions();
});

document.addEventListener("click",event=>{
  if(!selectionMenu?.hidden&&!event.target.closest(".definitions-selection-menu-wrap"))closeSelectionMenu();
});
document.addEventListener("keydown",event=>{
  if(event.key!=="Escape")return;
  if(selectionMenu&&!selectionMenu.hidden){
    closeSelectionMenu();
    selectionMenuToggle?.focus();
    return;
  }
  if(selectionMode){
    clearSelection();
    return;
  }
  if(searchMode)closeSearch({clear:false});
});

bulkExecute?.addEventListener("click",startBulkExecution);
bulkDelete?.addEventListener("click",bulkDeleteSelected);
bulkArchive?.addEventListener("click",bulkArchiveSelected);

async function load({preserveSelection=false}={}){
  const {data:userData,error:userError}=await supabase.auth.getUser();
  if(userError||!userData?.user){
    list.replaceChildren();
    setStatus("No se pudo validar la sesión.",true);
    return;
  }

  const {data:roleRows,error:roleError}=await supabase
    .from("user_roles")
    .select("role,organization_id,revoked_at")
    .eq("user_id",userData.user.id)
    .is("revoked_at",null);
  if(roleError||!(roleRows||[]).some(row=>["root","admin"].includes(row.role))){
    list.replaceChildren();
    const article=document.createElement("article");article.className="definitions-empty";
    article.textContent="Mis Flujos requiere acceso ROOT o ADMIN autorizado.";
    list.append(article);
    setStatus("Acceso administrativo requerido.",true);
    return;
  }

  const {data,error}=await supabase
    .from("workflow_definitions_v2")
    .select("id,name,status,organization_id,revision,updated_at")
    .eq("status","published")
    .order("updated_at",{ascending:false});

  if(error){
    list.replaceChildren();
    setStatus("Error al consultar Mis Flujos.",true);
    return;
  }

  const rows=data||[];
  versionsByDefinition=new Map();
  revisionDraftByDefinition=new Map();
  applicationsByDefinition=new Map();
  executionsByDefinition=new Map();
  schedulesByApplication=new Map();
  propertyById=new Map();
  roomById=new Map();
  occupancyById=new Map();

  if(rows.length){
    const ids=rows.map(row=>row.id);
    const [versionResult,draftResult,applicationResult]=await Promise.all([
      supabase
        .from("workflow_definition_versions_v2")
        .select("id,definition_id,version,spec,published_at")
        .in("definition_id",ids)
        .order("version",{ascending:false}),
      supabase
        .from("workflow_definition_revision_drafts_v2")
        .select("definition_id,base_version,revision,authoring_complete,updated_at,published_at")
        .in("definition_id",ids)
        .is("published_at",null),
      supabase
        .from("workflow_applications_v2")
        .select("id,definition_id,definition_version_id,scope_type,property_id,room_id,occupancy_id,status,created_at")
        .in("definition_id",ids)
        .order("created_at",{ascending:false})
    ]);

    if(versionResult.error||draftResult.error||applicationResult.error){
      setStatus("No se pudieron consultar las versiones, ediciones o destinos.",true);
      return;
    }

    (versionResult.data||[]).forEach(version=>{
      const bucket=versionsByDefinition.get(version.definition_id)||[];
      bucket.push(version);
      versionsByDefinition.set(version.definition_id,bucket);
    });
    (draftResult.data||[]).forEach(draft=>revisionDraftByDefinition.set(draft.definition_id,draft));
    (applicationResult.data||[]).forEach(app=>{
      const bucket=applicationsByDefinition.get(app.definition_id)||[];
      bucket.push(app);
      applicationsByDefinition.set(app.definition_id,bucket);
    });

    const applications=applicationResult.data||[];
    const applicationIds=applications.map(app=>app.id);
    const appToDefinition=new Map(applications.map(app=>[app.id,app.definition_id]));

    if(applicationIds.length){
      const [executionResult,scheduleResult]=await Promise.all([
        supabase
          .from("workflow_executions_v2")
          .select("id,application_id,status,created_at")
          .in("application_id",applicationIds)
          .order("created_at",{ascending:false}),
        supabase
          .from("workflow_application_schedules_v2")
          .select("application_id,schedule_kind,status,next_run_at,next_occurrence_index,execution_count,last_scheduled_for,last_error_at")
          .in("application_id",applicationIds)
      ]);
      if(executionResult.error||scheduleResult.error){
        setStatus("No se pudo comprobar el historial o la programación automática.",true);
        return;
      }
      (executionResult.data||[]).forEach(execution=>{
        const definitionId=appToDefinition.get(execution.application_id);
        if(!definitionId)return;
        const bucket=executionsByDefinition.get(definitionId)||[];
        bucket.push(execution);
        executionsByDefinition.set(definitionId,bucket);
      });
      (scheduleResult.data||[]).forEach(schedule=>{
        schedulesByApplication.set(schedule.application_id,schedule);
      });
    }

    const propertyIds=[...new Set(applications.map(app=>app.property_id).filter(Boolean))];
    const roomIds=[...new Set(applications.map(app=>app.room_id).filter(Boolean))];
    const occupancyIds=[...new Set(applications.map(app=>app.occupancy_id).filter(Boolean))];

    const [propertyResult,roomResult,occupancyResult]=await Promise.all([
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
    if(propertyResult.error||roomResult.error||occupancyResult.error){
      setStatus("No se pudieron resolver algunos destinos.",true);
      return;
    }
    (propertyResult.data||[]).forEach(item=>propertyById.set(item.id,item));
    (roomResult.data||[]).forEach(item=>roomById.set(item.id,item));
    (occupancyResult.data||[]).forEach(item=>occupancyById.set(item.id,item));
  }

  publishedRows=rows.filter(row=>latestVersion(row));

  if(!preserveSelection){
    selectedIds.clear();
  }else{
    const existing=new Set(publishedRows.map(row=>row.id));
    [...selectedIds].forEach(id=>{if(!existing.has(id))selectedIds.delete(id)});
  }

  renderDefinitions();

  if(!publishedRows.length){
    setStatus("No hay flujos publicados en tu ámbito.");
    return;
  }

  const withHistory=publishedRows.filter(hasHistory).length;
  const withoutHistory=publishedRows.length-withHistory;
  setStatus(
    publishedRows.length+" flujo"+(publishedRows.length===1?"":"s")
    +" · "+withoutHistory+" sin ejecutar"
    +" · "+withHistory+" con historial."
  );
}

load();
