import { supabase } from "./supabase-client.js";

const definitionBox=document.getElementById("applicationDefinition");
const formCard=document.getElementById("applicationFormCard");
const form=document.getElementById("workflowApplicationForm");
const versionSelect=document.getElementById("applicationVersion");
const scopeText=document.getElementById("applicationScope");
const propertyRow=document.getElementById("applicationPropertyRow");
const roomRow=document.getElementById("applicationRoomRow");
const occupancyRow=document.getElementById("applicationOccupancyRow");
const propertySelect=document.getElementById("applicationProperty");
const roomSelect=document.getElementById("applicationRoom");
const occupancySelect=document.getElementById("applicationOccupancy");
const photoRow=document.getElementById("applicationPhotoRow");
const photoNote=document.getElementById("applicationPhotoNote");
const photoPatternsBox=document.getElementById("applicationPhotoPatterns");
const targetNote=document.getElementById("applicationTargetNote");
const createButton=document.getElementById("applicationCreate");
const applicationsList=document.getElementById("workflowApplications");
const status=document.getElementById("applicationsStatus");
const pageTitle=document.getElementById("applicationsPageTitle");
const setupJourney=document.getElementById("workflowSetupJourney");
const formEyebrow=document.getElementById("applicationFormEyebrow");
const formTitle=document.getElementById("applicationFormTitle");
const formDescription=document.getElementById("applicationFormDescription");
const versionRow=document.getElementById("applicationVersionRow");
const applicationsSection=document.getElementById("applicationsSection");
const applicationsEyebrow=document.getElementById("applicationsEyebrow");
const applicationsTitle=document.getElementById("applicationsTitle");
const contextBackLink=document.querySelector(".context-back");

const params=new URLSearchParams(window.location.search);
const definitionId=params.get("definition")||"";
const guidedSetup=params.get("setup")==="1";
const handoffToken=params.get("handoff")||"";
const transientSetup=guidedSetup&&Boolean(handoffToken);
const executionIntent=guidedSetup&&params.get("intent")==="execute";
const executionFromFlows=executionIntent&&params.get("from")==="mis-flujos";
const batchToken=params.get("batch")||"";
const batchIndex=Math.max(0,Number(params.get("batch_index")||0)||0);
const revisionPublished=params.get("published")==="1";
const setupVersionNumber=Number(params.get("version")||0);
let guidedApplicationId=params.get("application")||null;
let guidedExecutionId=params.get("execution")||null;
let definition=null;
let versions=[];
let properties=[];
let rooms=[];
let occupancies=[];
let applications=[];
let executions=[];
let applicationPhotoResources=[];
let photoPatterns=[];
let photoPatternById=new Map();
let permissionContext=null;
let currentUser=null;
let transientPayload=null;
let transientTarget=null;
let transientFinalized=false;
let authorOrganizationId=null;
let executionMissingFocusDone=false;
let batchQueue=null;

const EXECUTION_KEY_PREFIX="workflow-execute-now:";
const HANDOFF_KEY_PREFIX="gestionpisos.workflow-builder.handoff.";
const BATCH_EXECUTION_PREFIX="workflow-batch-execution:";
const scopeLabels={organization:"Toda la organización",property:"Un piso",room:"Una habitación",occupancy:"Una ocupación / inquilino"};
const executionStatusLabels={pending:"Pendiente",active:"Activa",waiting_review:"Esperando revisión",completed:"Completada",cancelled:"Cancelada",failed:"Fallida"};
const assignmentLabels={
  manual:"Se decide al iniciar",
  property_responsible:"Responsable operativo del piso",
  active_occupants_rotation:"Ocupantes activos en rotación",
  fixed_person:"Persona fija",
  role:"Rol o capacidad"
};

function loadBatchQueue(){
  if(!batchToken)return null;
  let raw=null;
  try{raw=sessionStorage.getItem(BATCH_EXECUTION_PREFIX+batchToken)}catch{}
  if(!raw)return null;
  try{
    const parsed=JSON.parse(raw);
    if(!parsed||!Array.isArray(parsed.items)||!parsed.items.length)return null;
    if(parsed.createdAt&&Date.now()-Number(parsed.createdAt)>2*60*60*1000){
      sessionStorage.removeItem(BATCH_EXECUTION_PREFIX+batchToken);
      return null;
    }
    const item=parsed.items[batchIndex]||null;
    if(!item||item.definitionId!==definitionId)return null;
    parsed.index=batchIndex;
    return parsed;
  }catch{
    return null;
  }
}
function clearBatchQueue(){
  if(!batchToken)return;
  try{sessionStorage.removeItem(BATCH_EXECUTION_PREFIX+batchToken)}catch{}
}
function batchProgressLabel(){
  if(!batchQueue)return "";
  return "Flujo "+(batchIndex+1)+" de "+batchQueue.items.length;
}
function batchNextItem(){
  if(!batchQueue)return null;
  return batchQueue.items[batchIndex+1]||null;
}
function batchNextUrl(){
  const next=batchNextItem();
  if(!next)return null;
  const url=new URL("./workflow-applications.html",window.location.href);
  url.search="";
  url.searchParams.set("definition",next.definitionId);
  url.searchParams.set("setup","1");
  url.searchParams.set("intent","execute");
  url.searchParams.set("from","mis-flujos");
  url.searchParams.set("batch",batchToken);
  url.searchParams.set("batch_index",String(batchIndex+1));
  if(next.applicationId)url.searchParams.set("application",next.applicationId);
  return url.href;
}

function setStatus(message,error=false){
  const span=status?.querySelector("span:last-child");
  if(span)span.textContent=message;
  status?.classList.toggle("error",error);
}
function option(value,label){const node=document.createElement("option");node.value=value;node.textContent=label;return node}
function fmtDate(value){if(!value)return "—";try{return new Intl.DateTimeFormat("es-ES",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value))}catch{return value}}
function activeVersion(){return versions.find(item=>item.id===versionSelect.value)||versions[0]||null}
function versionScope(){return String(activeVersion()?.spec?.scopeType||definition?.scope_type||"")}
function versionNeedsPhoto(version=activeVersion()){return version?.spec?.steps?.photo===true}
function selectedPhotoPatternIds(){
  return [...photoPatternsBox.querySelectorAll('input[type="checkbox"]:checked')].map(node=>node.value);
}
function hasManualContour(pattern){
  const strokes=pattern?.contour_data?.strokes;
  return Array.isArray(strokes)&&strokes.length>0;
}
function targetLabel(app){
  if(app.scope_type==="organization")return "Toda la organización";
  if(app.scope_type==="property"){
    const p=properties.find(item=>item.id===app.property_id);
    return p?.name||"Piso "+String(app.property_id||"").slice(0,8);
  }
  if(app.scope_type==="room"){
    const p=properties.find(item=>item.id===app.property_id);
    const r=rooms.find(item=>item.id===app.room_id);
    return [p?.name,r?.label||"Habitación"].filter(Boolean).join(" · ");
  }
  if(app.scope_type==="occupancy"){
    const p=properties.find(item=>item.id===app.property_id);
    const o=occupancies.find(item=>item.id===app.occupancy_id);
    const person=o?.tenants_v2?.full_name||o?.occupant_email||"Ocupación";
    return [p?.name,person].filter(Boolean).join(" · ");
  }
  return "Destino";
}
function errorText(error){
  const message=String(error?.message||"");
  if(message.includes("aal2_required"))return "Para publicar o aplicar flujos debes completar MFA (sesión AAL2).";
  if(message.includes("workflow_property_not_available"))return "El piso seleccionado ya no está disponible.";
  if(message.includes("workflow_room_not_available"))return "La habitación seleccionada ya no está disponible o no pertenece al piso.";
  if(message.includes("workflow_occupancy_not_available"))return "La ocupación ya no está vigente o no pertenece al piso.";
  if(message.includes("workflow_application_version_conflict"))return "Este flujo ya está preparado para ese destino con otra versión. Archiva primero el destino existente.";
  if(message.includes("workflow_application_not_authorized"))return "Tu sesión no tiene autorización para preparar este destino.";
  if(message.includes("workflow_execution_not_authorized"))return "Tu sesión no tiene autorización para ejecutar este flujo.";
  if(message.includes("workflow_manual_assignee_required"))return "Selecciona quién realizará esta ejecución.";
  if(message.includes("workflow_manual_assignee_not_eligible"))return "La persona seleccionada no tiene capacidad operativa válida para este ámbito.";
  if(message.includes("workflow_property_responsible_unavailable"))return "Este piso no tiene un responsable operativo vigente para ejecutar el flujo.";
  if(message.includes("workflow_schedule_must_be_future"))return "La fecha programada debe estar en el futuro.";
  if(message.includes("workflow_schedule_timezone_invalid")||message.includes("workflow_schedule_timezone_conflict"))return "No se pudo validar la zona horaria de esta programación. Vuelve al Creador y revisa la fecha.";
  if(message.includes("workflow_schedule_local_time_ambiguous"))return "Esa hora se repite por el cambio horario. Vuelve al Creador y elige otra hora.";
  if(message.includes("workflow_scheduled_utc_invalid")||message.includes("workflow_schedule_time_mismatch"))return "La fecha y hora programadas no representan un instante válido. Vuelve al Creador y selecciónalas de nuevo.";
  if(message.includes("workflow_schedule_assignment_not_supported"))return "Esta regla de asignación todavía no admite programación automática.";
  if(message.includes("workflow_scheduled_execute_now_forbidden")||message.includes("workflow_scheduled_manual_execution_forbidden"))return "Los flujos de Fecha concreta se programan; no se ejecutan manualmente desde este paso.";
  if(message.includes("workflow_assignment_not_supported"))return "Esta regla de asignación todavía no está habilitada para Ejecutar ahora.";
  if(message.includes("workflow_execution_property_unavailable")||message.includes("workflow_execution_room_unavailable")||message.includes("workflow_execution_occupancy_unavailable"))return "El destino de esta aplicación ya no está disponible para nuevas ejecuciones.";
  if(message.includes("workflow_application_not_executable"))return "Este destino ya no está disponible para nuevas ejecuciones.";
  if(message.includes("workflow_photo_step_requires_property"))return "El paso Fotografía necesita una aplicación vinculada a un piso.";
  if(message.includes("workflow_photo_resources_required"))return "Selecciona al menos un patrón fotográfico real.";
  if(message.includes("workflow_photo_pattern_not_available"))return "Uno de los patrones ya no está disponible, no pertenece al piso o no tiene silueta guardada.";
  if(message.includes("workflow_photo_pattern_duplicate"))return "No se puede seleccionar dos veces el mismo patrón.";
  if(message.includes("workflow_application_photo_resources_conflict"))return "Este destino ya tiene otros recursos fotográficos vinculados.";
  if(message.includes("workflow_application_photo_resources_locked"))return "Los recursos de este destino ya están congelados por una ejecución existente.";
  if(message.includes("workflow_execution_photo_snapshot_missing"))return "La ejecución no tiene el snapshot fotográfico requerido.";
  if(message.includes("workflow_definition_has_history"))return "Este flujo ya tiene historial y debe editarse como una nueva versión.";
  if(message.includes("workflow_revision_requires_history"))return "Este flujo todavía no tiene historial; debe editarse directamente.";
  if(message.includes("workflow_creation_request_conflict"))return "Esta creación ya fue finalizada con otros datos. Vuelve a Mis Flujos antes de repetirla.";
  if(message.includes("workflow_request_key_invalid"))return "La sesión temporal de creación ya no es válida.";
  if(message.includes("workflow_draft_conflict"))return "El flujo cambió en otra sesión. Recarga Mis Flujos antes de continuar.";
  if(message.includes("workflow_unexecuted_delete_instead"))return "Este flujo nunca se ha ejecutado; puede eliminarse en lugar de archivarse.";
  return "No se pudo completar la operación. No se ha modificado ningún dato.";
}
function meta(label,value){
  const box=document.createElement("div");box.className="application-meta-item";
  const strong=document.createElement("strong");strong.textContent=label;
  const span=document.createElement("span");span.textContent=value||"—";
  box.append(strong,span);return box;
}
function setSetupStage(stage){
  if(!guidedSetup||!setupJourney)return;
  setupJourney.hidden=false;
  const order=["design","destination","ready"];
  const activeIndex=stage==="done"?order.length:Math.max(0,order.indexOf(stage));
  setupJourney.querySelectorAll("[data-setup-stage]").forEach(node=>{
    const index=order.indexOf(node.dataset.setupStage);
    node.classList.toggle("is-complete",stage==="done"||index<activeIndex);
    node.classList.toggle("is-current",stage!=="done"&&index===activeIndex);
  });
}

function stepsSummary(version){
  const spec=version?.spec||{};
  const steps=spec.steps||{};
  const parts=[];
  if(steps.accept===true)parts.push("Aceptar / Rechazar");
  if(steps.photo===true)parts.push("Foto");
  if(steps.checklist===true){
    const count=Array.isArray(spec.checklistItems)?spec.checklistItems.length:0;
    parts.push(count?count+" comprobación"+(count===1?"":"es"):"Checklist");
  }
  if(steps.document===true)parts.push("Documento");
  return parts.join(" · ")||"Pasos configurados";
}

function configurePresentation(){
  if(!guidedSetup){
    if(setupJourney)setupJourney.hidden=true;
    if(pageTitle)pageTitle.textContent="Usar flujo";
    return;
  }

  document.body.classList.add("workflow-guided-setup");

  if(executionIntent){
    document.body.classList.add("workflow-execution-assist");
    if(pageTitle)pageTitle.textContent=batchQueue?"Ejecutar flujos":"Ejecutar flujo";
    if(contextBackLink){
      contextBackLink.href="./workflow-definitions.html";
      const cancelLabel=batchQueue?"Cancelar ejecución masiva":"Cancelar ejecución";
      contextBackLink.setAttribute("aria-label",cancelLabel);
      contextBackLink.title=cancelLabel;
      if(batchQueue)contextBackLink.addEventListener("click",clearBatchQueue,{once:true});
    }
    if(formCard)formCard.classList.toggle("execution-attention",!guidedApplicationId);
    if(formEyebrow)formEyebrow.textContent=batchQueue?batchProgressLabel()+" · Destino":"Ejecución · Destino";
    if(formTitle)formTitle.textContent="Completa lo necesario para ejecutar";
    if(formDescription)formDescription.textContent="Falta información del destino. Completa únicamente los campos resaltados para continuar.";
    if(versionRow)versionRow.hidden=true;
    if(createButton)createButton.textContent="Continuar";
    if(applicationsEyebrow)applicationsEyebrow.textContent="Ejecución";
    if(applicationsTitle)applicationsTitle.textContent="Preparar ejecución";
    if(applicationsSection)applicationsSection.hidden=!guidedApplicationId;
    setSetupStage(guidedApplicationId?"ready":"destination");
    return;
  }

  if(pageTitle)pageTitle.textContent="Preparar flujo";
  if(contextBackLink&&transientSetup){
    contextBackLink.href=transientPayload?.mode==="create"?"./workflows.html":"./workflow-definitions.html";
    contextBackLink.setAttribute("aria-label","Salir del recorrido");
    contextBackLink.title="Salir del recorrido";
  }
  if(formEyebrow)formEyebrow.textContent="Paso 2 · Destino";
  if(formTitle)formTitle.textContent="¿Dónde quieres utilizarlo?";
  if(formDescription)formDescription.textContent="El diseño ya está listo. Elige ahora el destino real y los recursos que necesita.";
  if(versionRow)versionRow.hidden=true;
  if(createButton)createButton.textContent="Continuar";
  if(applicationsEyebrow)applicationsEyebrow.textContent="Paso 3 · Listo";
  if(applicationsTitle)applicationsTitle.textContent="Listo para usar";
  if(applicationsSection)applicationsSection.hidden=!guidedApplicationId;
  setSetupStage(guidedApplicationId?"ready":"destination");
}


function consumeTransientHandoff(){
  if(!transientSetup)return null;
  let raw=null;
  try{
    raw=sessionStorage.getItem(HANDOFF_KEY_PREFIX+handoffToken);
    sessionStorage.removeItem(HANDOFF_KEY_PREFIX+handoffToken);
  }catch{}
  if(!raw)return null;
  try{
    const payload=JSON.parse(raw);
    if(!payload||typeof payload!=="object")return null;
    if(!["create","edit_unexecuted","revision"].includes(payload.mode))return null;
    if(!payload.spec||typeof payload.spec!=="object")return null;
    if(!payload.requestKey)return null;
    if(payload.createdAt&&Date.now()-Number(payload.createdAt)>2*60*60*1000)return null;
    return payload;
  }catch{
    return null;
  }
}

async function resolveAuthorOrganization(){
  const {data:roles,error}=await supabase
    .from("user_roles")
    .select("role,organization_id,revoked_at")
    .eq("user_id",currentUser.id)
    .is("revoked_at",null);
  if(error)throw error;
  const active=(roles||[]).filter(row=>["root","admin"].includes(row.role));
  if(!active.length)throw new Error("workflow_author_role_required");
  const organizations=[...new Set(active.map(row=>row.organization_id).filter(Boolean))];
  if(organizations.length===1)return organizations[0];
  if(organizations.length>1)throw new Error("organization_selection_required");

  const isRoot=active.some(row=>row.role==="root");
  if(!isRoot)throw new Error("organization_missing");
  const {data:orgs,error:orgError}=await supabase
    .from("organizations")
    .select("id,status,created_at")
    .eq("status","active")
    .order("created_at");
  if(orgError)throw orgError;
  if((orgs||[]).length!==1)throw new Error("organization_selection_required");
  return orgs[0].id;
}

function transientVersionNumber(){
  if(transientPayload?.mode==="revision"){
    return Number(transientPayload.baseVersion||0)+1;
  }
  return Number(transientPayload?.baseVersion||1)||1;
}

async function preloadTransientTarget(){
  if(!transientPayload?.definitionId)return;
  const {data,error}=await supabase
    .from("workflow_applications_v2")
    .select("id,definition_version_id,scope_type,property_id,room_id,occupancy_id,status,created_at")
    .eq("definition_id",transientPayload.definitionId)
    .eq("status","configured")
    .order("created_at",{ascending:false})
    .limit(1);
  if(error)throw error;
  const app=(data||[])[0]||null;
  if(!app)return;

  if(app.property_id){
    propertySelect.value=app.property_id;
    if(versionScope()==="room")await loadRoomsFor(app.property_id);
    if(versionScope()==="occupancy")await loadOccupanciesFor(app.property_id);
    if(versionNeedsPhoto())await loadPhotoPatternsFor(app.property_id);
  }
  if(app.room_id)roomSelect.value=app.room_id;
  if(app.occupancy_id)occupancySelect.value=app.occupancy_id;

  if(versionNeedsPhoto()){
    const {data:resources,error:resourceError}=await supabase
      .from("workflow_application_photo_resources_v2")
      .select("pattern_id,sort_order")
      .eq("application_id",app.id)
      .order("sort_order");
    if(resourceError)throw resourceError;
    const selected=new Set((resources||[]).map(item=>item.pattern_id));
    photoPatternsBox.querySelectorAll('input[type="checkbox"]').forEach(input=>{
      input.checked=selected.has(input.value);
    });
  }
  refreshCreateAvailability();
}

function targetFromControls(){
  const scope=versionScope();
  return {
    scope_type:scope,
    property_id:["property","room","occupancy"].includes(scope)?propertySelect.value||null:null,
    room_id:scope==="room"?roomSelect.value||null:null,
    occupancy_id:scope==="occupancy"?occupancySelect.value||null:null,
    photo_pattern_ids:versionNeedsPhoto()?selectedPhotoPatternIds():[]
  };
}

function scheduledDisplay(spec){
  if(!spec?.scheduledAtUtc||!spec?.scheduledTimezone)return "Fecha pendiente";
  const parsed=new Date(spec.scheduledAtUtc);
  if(Number.isNaN(parsed.getTime()))return String(spec.scheduledAt||"Fecha pendiente");
  try{
    return new Intl.DateTimeFormat("es-ES",{
      dateStyle:"medium",
      timeStyle:"short",
      timeZone:spec.scheduledTimezone
    }).format(parsed)+" · "+spec.scheduledTimezone;
  }catch{
    return String(spec.scheduledAt||"Fecha pendiente")+" · "+String(spec.scheduledTimezone||"");
  }
}

function transientAssignmentControls(app){
  const spec=transientPayload?.spec||{};
  const assignmentType=String(spec.assignmentType||"");
  const scheduled=String(spec.triggerType||"")==="scheduled_once";
  const wrap=document.createElement("div");
  wrap.className="execution-controls";
  const title=document.createElement("strong");
  title.textContent=scheduled?"Programación":"Decisión final";
  wrap.append(title);

  let assigneeSelect=null;
  let executable=true;
  if(assignmentType==="manual"){
    const candidates=executionCandidates(app);
    const label=document.createElement("label");
    label.textContent=scheduled
      ?"¿Quién realizará esta tarea cuando llegue la fecha?"
      :"¿Quién realizará esta tarea si eliges Ejecutar?";
    assigneeSelect=document.createElement("select");
    assigneeSelect.append(option("","Selecciona una persona"));
    assigneeSelect.append(...candidates.map(person=>option(person.user_id,candidateLabel(person))));
    label.append(assigneeSelect);
    wrap.append(label);
    if(!candidates.length)executable=false;
  }else if(assignmentType==="property_responsible"){
    const note=document.createElement("span");
    note.className="execution-note";
    note.textContent=scheduled
      ?"El responsable operativo se resolverá de nuevo cuando llegue la fecha programada."
      :"Si ejecutas, se validará de nuevo el responsable operativo vigente del piso.";
    wrap.append(note);
  }else{
    executable=false;
    const note=document.createElement("span");
    note.className="execution-note";
    note.textContent=scheduled
      ?"Esta regla de asignación todavía no admite programación automática."
      :"Puedes Publicar este flujo, pero esta regla de asignación todavía no admite ejecución manual.";
    wrap.append(note);
  }

  const explanation=document.createElement("div");
  explanation.className="application-note";
  explanation.textContent=scheduled
    ?"Programar guarda el flujo y su destino sin crear una tarea ahora. La tarea se creará automáticamente el "+scheduledDisplay(spec)+"."
    :"Publicar lo guarda en Mis Flujos sin crear tareas. Mientras nunca se ejecute podrás editarlo o eliminarlo. Ejecutar lo publica y crea la tarea; desde ese momento conservará historial y solo podrá archivarse.";
  wrap.append(explanation);

  const actions=document.createElement("div");
  actions.className="application-guided-actions";

  const publish=document.createElement("button");
  publish.type="button";
  publish.className=scheduled?"primary":"secondary";
  publish.textContent=scheduled?"Programar":"Publicar";
  publish.disabled=scheduled&&!executable;
  publish.addEventListener("click",()=>{
    const assignee=assigneeSelect?.value||null;
    if(scheduled&&assignmentType==="manual"&&!assignee){
      setStatus("Selecciona quién realizará la tarea cuando llegue la fecha.",true);
      return;
    }
    finalizeTransient(false,scheduled?assignee:null,publish);
  });

  const execute=document.createElement("button");
  execute.type="button";
  execute.className="primary";
  execute.textContent="Ejecutar";
  execute.disabled=!executable;
  execute.hidden=scheduled;
  execute.addEventListener("click",()=>{
    const assignee=assigneeSelect?.value||null;
    if(assignmentType==="manual"&&!assignee){
      setStatus("Selecciona quién realizará esta tarea.",true);
      return;
    }
    finalizeTransient(true,assignee,execute);
  });

  const changeTarget=document.createElement("button");
  changeTarget.type="button";
  changeTarget.className="secondary";
  changeTarget.textContent="Cambiar destino";
  changeTarget.addEventListener("click",()=>{
    transientTarget=null;
    applicationsSection.hidden=true;
    formCard.hidden=false;
    setSetupStage("destination");
    setStatus("Ajusta el destino y pulsa Continuar cuando esté listo.");
    window.scrollTo({top:0,behavior:"smooth"});
  });

  const discard=document.createElement("button");
  discard.type="button";
  discard.className="danger-soft";
  discard.textContent="Descartar todo";
  discard.addEventListener("click",discardTransient);

  actions.append(publish);
  if(!scheduled)actions.append(execute);
  actions.append(changeTarget,discard);
  wrap.append(actions);
  return wrap;
}

function renderTransientReady(){
  const spec=transientPayload.spec;
  const app={
    scope_type:transientTarget.scope_type,
    property_id:transientTarget.property_id,
    room_id:transientTarget.room_id,
    occupancy_id:transientTarget.occupancy_id
  };
  applicationsList.replaceChildren();

  const article=document.createElement("article");
  article.className="application-card application-ready-card";
  const head=document.createElement("div");head.className="application-item-head";
  const title=document.createElement("h3");title.textContent=spec.flowName||"Flujo";
  const badge=document.createElement("span");badge.className="application-badge";badge.textContent="Listo";
  head.append(title,badge);

  const details=document.createElement("div");details.className="application-meta application-ready-summary";
  details.append(
    meta("Destino",targetLabel(app)),
    meta("Qué hará",stepsSummary({spec})),
    meta("Asignación",assignmentLabels[String(spec.assignmentType||"")]||"Configurada")
  );
  if(String(spec.triggerType||"")==="scheduled_once"){
    details.append(meta("Programada para",scheduledDisplay(spec)));
  }
  if(versionNeedsPhoto({spec})){
    const names=transientTarget.photo_pattern_ids.map(id=>photoPatternById.get(id)?.name||photoPatternById.get(id)?.target_key||"Patrón");
    details.append(meta("Fotografías",names.join(" · ")));
  }
  article.append(head,details,transientAssignmentControls(app));
  applicationsList.append(article);
}

function renderTransientResult(result,{executed=false,scheduled=false,assigneeId=null}={}){
  const spec=transientPayload.spec;
  const app={
    scope_type:transientTarget.scope_type,
    property_id:transientTarget.property_id,
    room_id:transientTarget.room_id,
    occupancy_id:transientTarget.occupancy_id
  };
  applicationsList.replaceChildren();

  const article=document.createElement("article");
  article.className="application-card application-ready-card";
  const head=document.createElement("div");head.className="application-item-head";
  const title=document.createElement("h3");title.textContent=spec.flowName||"Flujo";
  const badge=document.createElement("span");badge.className="application-badge";badge.textContent=executed?"Ejecutado":scheduled?"Programado":"Publicado";
  head.append(title,badge);

  const details=document.createElement("div");details.className="application-meta application-ready-summary";
  details.append(
    meta("Destino",targetLabel(app)),
    meta("Qué hará",stepsSummary({spec})),
    meta("Estado",executed?"Tarea creada":scheduled?"Programación activa":"Sin tareas")
  );
  if(scheduled)details.append(meta("Programada para",scheduledDisplay(spec)));
  if((executed||scheduled)&&assigneeId){
    const person=executionCandidates(app).find(item=>item.user_id===assigneeId);
    details.append(meta("Asignado a",person?candidateLabel(person):"Persona seleccionada"));
  }
  article.append(head,details);

  const done=document.createElement("div");done.className="application-complete";
  const strong=document.createElement("strong");
  strong.textContent=executed?"Tarea creada":scheduled?"Flujo programado":"Flujo publicado";
  const p=document.createElement("p");
  p.textContent=executed
    ?"El flujo quedó publicado en Mis Flujos y la tarea ya está disponible para la persona asignada."
    :scheduled
      ?"No se ha creado ninguna tarea todavía. GestionPisos la creará automáticamente cuando llegue la fecha programada."
      :"No se ha creado ninguna tarea. Mientras este flujo no se ejecute podrás editarlo o eliminarlo desde Mis Flujos.";
  const actions=document.createElement("div");actions.className="application-guided-actions";
  if(executed){
    const tasks=document.createElement("a");tasks.className="primary";tasks.href="./workflow-tasks.html";tasks.textContent="Abrir Tareas";
    actions.append(tasks);
  }
  const flows=document.createElement("a");flows.className=executed?"secondary":"primary";flows.href="./workflow-definitions.html?published="+encodeURIComponent(result.definition_id);flows.textContent="Abrir Mis Flujos";
  actions.append(flows);
  done.append(strong,p,actions);
  article.append(done);
  applicationsList.append(article);
}

async function finalizeTransient(execute,assigneeId,button){
  if(!transientPayload||!transientTarget)return;
  const spec=transientPayload.spec||{};
  const scheduled=String(spec.triggerType||"")==="scheduled_once";
  if(!execute){
    const confirmed=window.confirm(scheduled
      ?"Programar guardará el flujo y creará la tarea automáticamente el "+scheduledDisplay(spec)+". ¿Programar?"
      :"Publicar guardará este flujo en Mis Flujos sin crear ninguna tarea. Mientras siga sin ejecutarse podrá editarse o eliminarse. ¿Publicar?");
    if(!confirmed)return;
  }

  const original=button.textContent;
  button.disabled=true;
  button.textContent=execute?"Ejecutando…":scheduled?"Programando…":"Publicando…";
  setStatus(execute
    ?"Validando condiciones, publicando y creando la tarea…"
    :scheduled
      ?"Guardando el flujo y preparando su ejecución automática…"
      :"Publicando el flujo sin crear tareas…");

  const common={
    p_property_id:transientTarget.property_id,
    p_room_id:transientTarget.room_id,
    p_occupancy_id:transientTarget.occupancy_id,
    p_photo_pattern_ids:transientTarget.photo_pattern_ids,
    p_execute:execute,
    p_idempotency_key:execute?transientPayload.requestKey:null,
    p_assigned_user_id:execute?assigneeId:null
  };
  if(scheduled){
    common.p_schedule_timezone=spec.scheduledTimezone||null;
    common.p_schedule_assigned_user_id=String(spec.assignmentType||"")==="manual"?assigneeId:null;
  }

  let rpc="";
  let args={};
  if(transientPayload.mode==="create"){
    rpc=scheduled?"publish_workflow_ready_v2":"publish_workflow_ready_v1";
    args={
      p_spec:transientPayload.spec,
      ...common,
      p_request_key:transientPayload.requestKey
    };
  }else if(transientPayload.mode==="edit_unexecuted"){
    rpc=scheduled?"update_unexecuted_workflow_v2":"update_unexecuted_workflow_v1";
    args={
      p_definition_id:transientPayload.definitionId,
      p_spec:transientPayload.spec,
      p_expected_revision:transientPayload.expectedRevision,
      ...common
    };
  }else{
    rpc=scheduled?"publish_workflow_revision_ready_v2":"publish_workflow_revision_ready_v1";
    args={
      p_definition_id:transientPayload.definitionId,
      p_expected_revision:transientPayload.expectedRevision,
      ...common
    };
  }

  const {data,error}=await supabase.rpc(rpc,args);
  button.textContent=original;
  if(error||!Array.isArray(data)||!data[0]){
    button.disabled=false;
    setStatus(errorText(error),true);
    return;
  }

  const result=data[0];
  transientFinalized=true;
  const url=new URL("./workflow-applications.html",window.location.href);
  url.searchParams.set("definition",result.definition_id);
  url.searchParams.set("setup","1");
  url.searchParams.set("application",result.application_id);
  if(execute&&result.execution_id)url.searchParams.set("execution",result.execution_id);
  window.history.replaceState({},"",url);

  formCard.hidden=true;
  applicationsSection.hidden=false;
  setSetupStage(execute||scheduled?"done":"ready");
  renderTransientResult(result,{executed:execute,scheduled,assigneeId});
  setStatus(execute
    ?"Tarea creada. El flujo queda protegido por historial desde esta primera ejecución."
    :scheduled
      ?"Flujo programado. La tarea se creará automáticamente el "+scheduledDisplay(spec)+"."
      :"Flujo publicado sin tareas. Puedes editarlo o eliminarlo desde Mis Flujos mientras no se ejecute.");
  window.scrollTo({top:0,behavior:"smooth"});
}

async function discardTransient(){
  if(!transientPayload)return;
  const message=transientPayload.mode==="revision"
    ?"¿Descartar esta nueva versión? La versión actualmente publicada seguirá intacta."
    :"¿Descartar este recorrido? No se guardará ningún cambio.";
  if(!window.confirm(message))return;

  if(transientPayload.mode==="revision"){
    const {error}=await supabase.rpc("discard_workflow_definition_revision_draft_v1",{
      p_definition_id:transientPayload.definitionId,
      p_expected_revision:transientPayload.expectedRevision
    });
    if(error){
      setStatus(errorText(error),true);
      return;
    }
  }

  transientFinalized=true;
  window.location.href=transientPayload.mode==="create"?"./workflows.html":"./workflow-definitions.html";
}

async function loadTransient(){
  transientPayload=consumeTransientHandoff();
  if(!transientPayload){
    definitionBox.classList.remove("application-card--loading");
    definitionBox.textContent="Esta creación temporal ya no está disponible.";
    formCard.hidden=true;
    applicationsSection.hidden=true;
    setStatus("Las creaciones incompletas no se guardan. Vuelve al Creador para empezar de nuevo.",true);
    return;
  }

  const {data:userData,error:userError}=await supabase.auth.getUser();
  if(userError||!userData?.user){
    setStatus("No se pudo validar la sesión.",true);
    return;
  }
  currentUser=userData.user;

  if(transientPayload.definitionId){
    const {data:def,error:defError}=await supabase
      .from("workflow_definitions_v2")
      .select("id,organization_id,name,scope_type,status")
      .eq("id",transientPayload.definitionId)
      .maybeSingle();
    if(defError||!def)throw defError||new Error("workflow_definition_not_found");
    authorOrganizationId=def.organization_id;
  }else{
    authorOrganizationId=await resolveAuthorOrganization();
  }

  definition={
    id:transientPayload.definitionId||null,
    organization_id:authorOrganizationId,
    name:String(transientPayload.spec.flowName||"Flujo"),
    scope_type:String(transientPayload.spec.scopeType||""),
    status:transientPayload.mode==="create"?"prepublish":"published"
  };
  versions=[{
    id:"transient",
    definition_id:transientPayload.definitionId||null,
    version:transientVersionNumber(),
    spec:transientPayload.spec,
    published_at:null
  }];

  versionSelect.replaceChildren(option("transient","Configuración actual"));
  versionSelect.value="transient";
  await loadProperties();
  const available=properties.filter(item=>item.status!=="archived"&&!item.archived_at);
  propertySelect.replaceChildren(option("","Selecciona un piso"),...available.map(item=>option(item.id,item.name+(item.address_line?" · "+item.address_line:""))));

  const {data:contextData,error:contextError}=await supabase.rpc("get_permission_management_context",{p_organization_id:authorOrganizationId});
  permissionContext=contextError?null:contextData;

  renderDefinition();
  configurePresentation();
  formCard.hidden=false;
  applicationsSection.hidden=true;
  await updateTargetControls();
  await preloadTransientTarget();
  setSetupStage("destination");
  setStatus(transientPayload.mode==="create"
    ?"El diseño sigue siendo temporal. Elige el destino; todavía no se ha guardado ningún flujo."
    :"Elige o confirma el destino de esta edición antes de Publicar o Ejecutar.");
}

async function loadProperties(){
  const organizationId=definition?.organization_id||authorOrganizationId;
  if(!organizationId)throw new Error("workflow_author_organization_missing");
  const {data,error}=await supabase
    .from("properties_v2")
    .select("id,name,address_line,city,status,archived_at")
    .eq("organization_id",organizationId)
    .order("name");
  if(error)throw error;
  properties=data||[];
}

async function loadRoomsFor(propertyId){
  roomSelect.replaceChildren(option("","Selecciona una habitación"));
  if(!propertyId)return;
  const {data,error}=await supabase
    .from("rooms_v2")
    .select("id,property_id,label,status,archived_at")
    .eq("property_id",propertyId)
    .order("label");
  if(error)throw error;
  const received=data||[];
  received.forEach(item=>{if(!rooms.some(existing=>existing.id===item.id))rooms.push(item)});
  const available=received.filter(item=>item.status!=="archived"&&!item.archived_at);
  roomSelect.append(...available.map(item=>option(item.id,item.label)));
}

async function loadOccupanciesFor(propertyId){
  occupancySelect.replaceChildren(option("","Selecciona una ocupación vigente"));
  if(!propertyId)return;
  const {data,error}=await supabase
    .from("occupancies_v2")
    .select("id,property_id,room_id,occupant_email,starts_on,ends_on,status,tenants_v2(full_name,email)")
    .eq("property_id",propertyId)
    .eq("status","active")
    .order("starts_on",{ascending:false});
  if(error)throw error;
  const today=new Date();today.setHours(0,0,0,0);
  const received=(data||[]).filter(item=>{
    const starts=item.starts_on?new Date(item.starts_on+"T00:00:00"):null;
    const ends=item.ends_on?new Date(item.ends_on+"T23:59:59"):null;
    return (!starts||starts<=today)&&(!ends||ends>=today);
  });
  received.forEach(item=>{if(!occupancies.some(existing=>existing.id===item.id))occupancies.push(item)});
  occupancySelect.append(...received.map(item=>{
    const person=item.tenants_v2?.full_name||item.occupant_email||"Ocupación";
    return option(item.id,person);
  }));
}

function renderPhotoPatternOptions(){
  photoPatternsBox.replaceChildren();
  if(!photoPatterns.length){
    const empty=document.createElement("div");
    empty.className="application-note";
    empty.textContent="No hay patrones activos con silueta manual para este piso.";
    photoPatternsBox.append(empty);
    return;
  }

  photoPatterns.forEach(pattern=>{
    photoPatternById.set(pattern.id,pattern);
    const label=document.createElement("label");
    label.className="application-photo-option";
    const input=document.createElement("input");
    input.type="checkbox";
    input.value=pattern.id;
    input.addEventListener("change",refreshCreateAvailability);
    const text=document.createElement("span");
    const strong=document.createElement("strong");
    strong.textContent=pattern.name||pattern.target_key||"Patrón";
    const small=document.createElement("small");
    small.textContent=[pattern.target_key&&pattern.target_key!==pattern.name?pattern.target_key:null,"v"+pattern.version].filter(Boolean).join(" · ");
    text.append(strong,small);
    label.append(input,text);
    photoPatternsBox.append(label);
  });
}

async function loadPhotoPatternsFor(propertyId){
  photoPatterns=[];
  photoPatternsBox.replaceChildren();
  if(!versionNeedsPhoto()){
    photoNote.textContent="";
    return;
  }
  if(!propertyId){
    photoNote.textContent="Selecciona primero un piso para cargar sus patrones fotográficos.";
    return;
  }

  photoNote.textContent="Cargando patrones del piso…";
  const {data,error}=await supabase
    .from("photo_patterns_v2")
    .select("id,property_id,name,target_key,version,active,retired_at,contour_data")
    .eq("property_id",propertyId)
    .eq("active",true)
    .is("retired_at",null)
    .order("created_at");

  if(error)throw error;
  photoPatterns=(data||[]).filter(hasManualContour);
  renderPhotoPatternOptions();
  photoNote.textContent=photoPatterns.length
    ?"Selecciona uno o varios patrones. La ejecución congelará la versión y silueta efectiva."
    :"Este piso no tiene patrones utilizables. Crea y guarda una silueta en Banco Fotográfico.";
}

function updateExecutionTargetHighlights(){
  const rows=[propertyRow,roomRow,occupancyRow,photoRow];
  rows.forEach(row=>row?.classList.remove("execution-field-missing"));
  if(!executionIntent||guidedApplicationId)return;

  const scope=versionScope();
  const missing=[];
  if(["property","room","occupancy"].includes(scope)&&!propertySelect.value)missing.push(propertyRow);
  if(scope==="room"&&propertySelect.value&&!roomSelect.value)missing.push(roomRow);
  if(scope==="occupancy"&&propertySelect.value&&!occupancySelect.value)missing.push(occupancyRow);
  if(versionNeedsPhoto()&&propertySelect.value&&selectedPhotoPatternIds().length<1)missing.push(photoRow);

  missing.forEach(row=>row?.classList.add("execution-field-missing"));

  if(!executionMissingFocusDone&&missing.length){
    executionMissingFocusDone=true;
    requestAnimationFrame(()=>{
      const first=missing[0];
      const control=first?.querySelector("select,input");
      (control||first)?.focus?.({preventScroll:true});
      first?.scrollIntoView({block:"center",behavior:"smooth"});
    });
  }
}

function refreshCreateAvailability(){
  const scope=versionScope();
  const available=properties.filter(item=>item.status!=="archived"&&!item.archived_at);
  let disabled=false;

  if(scope!=="organization"&&!available.length)disabled=true;
  if(versionNeedsPhoto()){
    if(scope==="organization"||!propertySelect.value||selectedPhotoPatternIds().length<1)disabled=true;
  }

  if(executionIntent&&!guidedApplicationId){
    if(["property","room","occupancy"].includes(scope)&&!propertySelect.value)disabled=true;
    if(scope==="room"&&!roomSelect.value)disabled=true;
    if(scope==="occupancy"&&!occupancySelect.value)disabled=true;
  }

  createButton.disabled=disabled;
  updateExecutionTargetHighlights();
}

async function updateTargetControls(){
  const scope=versionScope();
  const photoRequired=versionNeedsPhoto();
  scopeText.textContent=scopeLabels[scope]||"—";
  propertyRow.hidden=!["property","room","occupancy"].includes(scope);
  roomRow.hidden=scope!=="room";
  occupancyRow.hidden=scope!=="occupancy";
  photoRow.hidden=!photoRequired;
  propertySelect.required=["property","room","occupancy"].includes(scope);
  roomSelect.required=scope==="room";
  occupancySelect.required=scope==="occupancy";
  roomSelect.disabled=scope!=="room"||!propertySelect.value;
  occupancySelect.disabled=scope!=="occupancy"||!propertySelect.value;

  if(scope==="organization"){
    targetNote.textContent=photoRequired
      ?"Esta receta exige fotografía y todavía necesita un destino que resuelva un piso concreto."
      :"Esta versión se aplicará a toda la organización. No requiere otro selector.";
    if(photoRequired){
      photoPatterns=[];
      renderPhotoPatternOptions();
      photoNote.textContent="El paso Fotografía no puede vincular patrones sin un piso concreto.";
    }
    refreshCreateAvailability();
    return;
  }

  const available=properties.filter(item=>item.status!=="archived"&&!item.archived_at);
  if(!available.length){
    targetNote.textContent="No hay pisos disponibles en Cartera. Crea primero un piso real para poder aplicar esta receta.";
    if(photoRequired){
      photoPatterns=[];
      renderPhotoPatternOptions();
      photoNote.textContent="Primero necesitas un piso y después sus patrones fotográficos.";
    }
    refreshCreateAvailability();
    return;
  }

  targetNote.textContent=scope==="room"
    ?"Selecciona primero el piso y después una habitación perteneciente a ese piso."
    :scope==="occupancy"
      ?"Selecciona primero el piso y después una ocupación vigente."
      :"Selecciona el piso concreto donde quieres aplicar esta versión.";

  if(photoRequired)await loadPhotoPatternsFor(propertySelect.value);
  else{
    photoPatterns=[];
    photoPatternsBox.replaceChildren();
    photoNote.textContent="";
  }
  refreshCreateAvailability();
}

function renderDefinition(){
  definitionBox.classList.remove("application-card--loading");
  const head=document.createElement("div");
  const eyebrow=document.createElement("p");eyebrow.className="eyebrow";eyebrow.textContent=transientSetup?"Diseño completado":guidedSetup?"Diseño completado":"Flujo publicado";
  const title=document.createElement("h2");title.textContent=definition.name;
  head.append(eyebrow,title);
  const info=document.createElement("div");info.className="application-meta";
  const version=activeVersion();
  if(transientSetup){
    info.append(
      meta("Estado",transientPayload?.mode==="create"?"Sin publicar":"Editando"),
      meta("Alcance",scopeLabels[String(version?.spec?.scopeType||definition.scope_type)]||definition.scope_type),
      meta("Qué hará",stepsSummary(version)),
      meta("Asignación",assignmentLabels[String(version?.spec?.assignmentType||"")]||"Configurada")
    );
  }else if(guidedSetup){
    info.append(
      meta("Versión","v"+(version?.version||"?")),
      meta("Alcance",scopeLabels[String(version?.spec?.scopeType||definition.scope_type)]||definition.scope_type),
      meta("Qué hará",stepsSummary(version)),
      meta("Asignación",assignmentLabels[String(version?.spec?.assignmentType||"")]||"Configurada")
    );
  }else{
    info.append(
      meta("Estado",definition.status==="published"?"Publicado":definition.status),
      meta("Alcance",scopeLabels[definition.scope_type]||definition.scope_type),
      meta("Versiones",String(versions.length)),
      meta("Última publicación",fmtDate(versions[0]?.published_at))
    );
  }
  definitionBox.replaceChildren(head,info);
}

function versionForApplication(app){
  return versions.find(item=>item.id===app.definition_version_id)||null;
}
function executionLabel(execution){
  if(!execution)return "Ninguna";
  return (executionStatusLabels[execution.status]||execution.status)+" · "+fmtDate(execution.created_at);
}
function candidateLabel(person){
  const roles=Array.isArray(person.roles)?person.roles:[];
  const role=roles.includes("admin")?"ADMIN":roles.includes("employee")?"EMPLEADO":roles.includes("root")?"ROOT":"USUARIO";
  return (person.display_name||person.email||"Usuario")+" · "+role;
}
function executionCandidates(app){
  const candidates=[];
  const seen=new Set();
  const actorRole=String(currentUser?.app_metadata?.role||"").toLowerCase();

  if(actorRole==="root"&&currentUser?.id){
    candidates.push({
      user_id:currentUser.id,
      display_name:currentUser.user_metadata?.display_name||currentUser.email||"ROOT",
      email:currentUser.email||"",
      roles:["root"]
    });
    seen.add(currentUser.id);
  }

  const propertyContext=(permissionContext?.properties||[]).find(item=>item.id===app.property_id);
  const responsibleId=propertyContext?.responsible_user_id||null;
  const writableAccess=new Set(
    (propertyContext?.staff_access||[])
      .filter(item=>item.can_write===true)
      .map(item=>item.employee_user_id)
  );

  (permissionContext?.people||[]).forEach(person=>{
    if(!person?.user_id||seen.has(person.user_id))return;
    if(person.profile_status==="archived")return;
    const roles=Array.isArray(person.roles)?person.roles:[];
    const isAdmin=roles.includes("admin");
    const isEmployee=roles.includes("employee");
    const employeeEligible=isEmployee&&(
      !app.property_id
      || person.user_id===responsibleId
      || writableAccess.has(person.user_id)
    );
    if(!isAdmin&&!employeeEligible)return;
    candidates.push(person);
    seen.add(person.user_id);
  });
  return candidates;
}
function requestKey(appId){
  const storageKey=EXECUTION_KEY_PREFIX+appId;
  let key=sessionStorage.getItem(storageKey);
  if(!key){
    key=globalThis.crypto?.randomUUID?.()||("manual-"+Date.now()+"-"+Math.random().toString(36).slice(2));
    sessionStorage.setItem(storageKey,key);
  }
  return {storageKey,key};
}
function clearRequestKey(appId){
  sessionStorage.removeItem(EXECUTION_KEY_PREFIX+appId);
}

function applicationPhotoLabel(app){
  const bindings=applicationPhotoResources
    .filter(item=>item.application_id===app.id)
    .sort((a,b)=>a.sort_order-b.sort_order);
  if(!bindings.length)return "Sin vincular";
  return bindings.map(binding=>{
    const pattern=photoPatternById.get(binding.pattern_id);
    return pattern?.name||pattern?.target_key||("Patrón "+String(binding.pattern_id).slice(0,8));
  }).join(" · ");
}

function occupancyIsCurrent(item){
  if(!item||item.status!=="active")return false;
  const today=new Date();today.setHours(0,0,0,0);
  const starts=item.starts_on?new Date(item.starts_on+"T00:00:00"):null;
  const ends=item.ends_on?new Date(item.ends_on+"T23:59:59"):null;
  return (!starts||starts<=today)&&(!ends||ends>=today);
}

function executionDestinationRequirement(app){
  if(!app||app.status!=="configured"){
    return {complete:false,value:"Destino pendiente",message:"Este flujo no tiene un destino disponible para ejecutar."};
  }
  if(app.scope_type==="organization"){
    return {complete:true,value:"Toda la organización",message:"Destino configurado."};
  }

  const property=properties.find(item=>item.id===app.property_id);
  const propertyAvailable=Boolean(property&&property.status!=="archived"&&!property.archived_at);
  if(!propertyAvailable){
    return {complete:false,value:"Piso no disponible",message:"El piso configurado ya no está disponible."};
  }

  if(app.scope_type==="property"){
    return {complete:true,value:targetLabel(app),message:"Destino configurado."};
  }

  if(app.scope_type==="room"){
    const room=rooms.find(item=>item.id===app.room_id);
    const available=Boolean(room&&room.property_id===app.property_id&&room.status!=="archived"&&!room.archived_at);
    return available
      ?{complete:true,value:targetLabel(app),message:"Destino configurado."}
      :{complete:false,value:"Habitación no disponible",message:"La habitación configurada ya no está disponible."};
  }

  if(app.scope_type==="occupancy"){
    const occupancy=occupancies.find(item=>item.id===app.occupancy_id);
    const available=Boolean(occupancy&&occupancy.property_id===app.property_id&&occupancyIsCurrent(occupancy));
    return available
      ?{complete:true,value:targetLabel(app),message:"Destino configurado."}
      :{complete:false,value:"Ocupación no disponible",message:"La ocupación configurada ya no está vigente."};
  }

  return {complete:false,value:"Destino pendiente",message:"El destino configurado no se puede validar."};
}

function executionPhotoRequirement(app,version){
  if(!versionNeedsPhoto(version))return null;
  const bindings=applicationPhotoResources
    .filter(item=>item.application_id===app.id)
    .sort((a,b)=>a.sort_order-b.sort_order);
  if(!bindings.length){
    return {complete:false,value:"Fotografías pendientes",message:"Este flujo requiere fotografías, pero no tiene patrones vinculados."};
  }
  const usable=bindings.every(binding=>{
    const pattern=photoPatternById.get(binding.pattern_id);
    return Boolean(pattern&&hasManualContour(pattern));
  });
  return usable
    ?{complete:true,value:applicationPhotoLabel(app),message:"Patrones fotográficos preparados."}
    :{complete:false,value:"Patrón no disponible",message:"Uno de los patrones fotográficos ya no está disponible para ejecutar."};
}

function propertyResponsibleFor(app){
  const propertyContext=(permissionContext?.properties||[]).find(item=>item.id===app.property_id);
  return propertyContext?.responsible_user_id||null;
}

function executionAssignmentRequirement(app,version){
  const assignmentType=String(version?.spec?.assignmentType||"");
  if(assignmentType==="manual"){
    const candidates=executionCandidates(app);
    return {
      complete:false,
      needsInput:true,
      blocking:candidates.length===0,
      value:"Se decide al iniciar",
      message:candidates.length
        ?"Selecciona quién realizará esta tarea."
        :"No hay una persona con capacidad operativa disponible para este destino.",
      candidates
    };
  }

  if(assignmentType==="property_responsible"){
    const responsibleId=propertyResponsibleFor(app);
    return responsibleId
      ?{complete:true,needsInput:false,blocking:false,value:"Responsable operativo",message:"Se resolverá automáticamente al ejecutar."}
      :{complete:false,needsInput:false,blocking:true,value:"Responsable pendiente",message:"Este piso no tiene un responsable operativo vigente."};
  }

  return {
    complete:false,
    needsInput:false,
    blocking:true,
    value:assignmentLabels[assignmentType]||"Asignación pendiente",
    message:"Esta regla de asignación todavía no está habilitada para ejecución manual."
  };
}

function executionReviewCard(label,value,{pending=false,body=null}={}){
  const card=document.createElement("details");
  card.className="execution-review-card"+(pending?" is-pending":" is-complete");
  card.open=pending;

  const summary=document.createElement("summary");
  const heading=document.createElement("span");heading.className="execution-review-heading";
  const key=document.createElement("strong");key.textContent=label;
  const current=document.createElement("span");current.className="execution-review-value";current.textContent=value||"—";
  heading.append(key,current);

  const state=document.createElement("span");state.className="execution-review-state";
  state.textContent=pending?"Pendiente":"Listo";
  summary.append(heading,state);
  card.append(summary);

  const content=document.createElement("div");content.className="execution-review-body";
  if(body instanceof Node)content.append(body);
  else{
    const p=document.createElement("p");
    p.textContent=String(body||"Configurado correctamente.");
    content.append(p);
  }
  card.append(content);

  return {card,summary,current,state,content};
}

function renderExecutionAssist(app){
  const version=versionForApplication(app);
  const destination=executionDestinationRequirement(app);
  const photo=executionPhotoRequirement(app,version);
  const assignment=executionAssignmentRequirement(app,version);

  const article=document.createElement("article");
  article.className="application-card application-ready-card execution-assist-card";

  const head=document.createElement("div");head.className="application-item-head";
  const title=document.createElement("h3");title.textContent=definition?.name||"Flujo";
  const badge=document.createElement("span");badge.className="application-badge";badge.textContent="Preparar";
  head.append(title,badge);
  article.append(head);

  if(batchQueue){
    const progress=document.createElement("div");
    progress.className="execution-batch-progress";
    progress.textContent=batchProgressLabel()+" · "+batchQueue.items[batchIndex].name;
    article.append(progress);
  }

  const banner=document.createElement("div");
  banner.className="execution-assist-banner";
  const bannerTitle=document.createElement("strong");
  const bannerText=document.createElement("p");
  banner.append(bannerTitle,bannerText);
  article.append(banner);

  const review=document.createElement("div");
  review.className="execution-review-list";
  article.append(review);

  const states=[];

  const destinationCard=executionReviewCard("Destino",destination.value,{
    pending:!destination.complete,
    body:destination.message
  });
  review.append(destinationCard.card);
  states.push({kind:"destination",complete:destination.complete,blocking:!destination.complete,ref:destinationCard});

  const stepsCard=executionReviewCard("Qué hará",stepsSummary(version),{
    pending:false,
    body:"Los pasos del flujo ya están configurados."
  });
  review.append(stepsCard.card);

  const versionCard=executionReviewCard("Versión","v"+(version?.version||"?"),{
    pending:false,
    body:"Esta es la versión que se utilizará para crear la tarea."
  });
  review.append(versionCard.card);

  if(photo){
    const photoCard=executionReviewCard("Fotografías",photo.value,{
      pending:!photo.complete,
      body:photo.message
    });
    review.append(photoCard.card);
    states.push({kind:"photo",complete:photo.complete,blocking:!photo.complete,ref:photoCard});
  }

  const assignmentBody=document.createElement("div");
  assignmentBody.className="execution-assignment-body";
  let assigneeSelect=null;
  let assigneeId=null;

  if(assignment.needsInput){
    const label=document.createElement("label");
    label.textContent="¿Quién realizará esta tarea?";
    assigneeSelect=document.createElement("select");
    assigneeSelect.append(option("","Selecciona una persona"));
    assigneeSelect.append(...assignment.candidates.map(person=>option(person.user_id,candidateLabel(person))));
    label.append(assigneeSelect);
    assignmentBody.append(label);

    if(assignment.blocking){
      const note=document.createElement("p");note.className="execution-note";note.textContent=assignment.message;
      assignmentBody.append(note);
    }
  }else{
    const note=document.createElement("p");note.className="execution-note";note.textContent=assignment.message;
    assignmentBody.append(note);
  }

  const assignmentCard=executionReviewCard("Asignación",assignment.value,{
    pending:!assignment.complete,
    body:assignmentBody
  });
  review.append(assignmentCard.card);
  const assignmentState={kind:"assignment",complete:assignment.complete,blocking:assignment.blocking,ref:assignmentCard};
  states.push(assignmentState);

  const actions=document.createElement("div");
  actions.className="application-guided-actions execution-assist-actions";

  const run=document.createElement("button");
  run.type="button";
  run.className="primary";
  run.textContent="Ejecutar ahora";

  const cancel=document.createElement("a");
  cancel.className="secondary";
  cancel.href="./workflow-definitions.html";
  cancel.textContent=batchQueue?"Cancelar ejecución masiva":"Cancelar ejecución";
  cancel.addEventListener("click",()=>{
    clearRequestKey(app.id);
    if(batchQueue)clearBatchQueue();
  });

  if(executionFromFlows)actions.append(run,cancel);
  else actions.append(run);
  article.append(actions);

  function updateState(){
    const pending=states.filter(item=>!item.complete);
    const blocked=pending.some(item=>item.blocking);

    run.disabled=pending.length>0||blocked;

    if(!pending.length){
      banner.classList.add("is-ready");
      banner.classList.remove("is-blocked");
      bannerTitle.textContent="Todo listo para ejecutar";
      bannerText.textContent="La información necesaria está completa. Puedes crear la tarea.";
      return;
    }

    banner.classList.remove("is-ready");
    banner.classList.toggle("is-blocked",blocked);
    bannerTitle.textContent=blocked?"No se puede ejecutar todavía":"Falta información para ejecutar";
    bannerText.textContent=blocked
      ?"Revisa los apartados abiertos. Hay información que debe resolverse antes de crear la tarea."
      :"Completa únicamente los apartados abiertos para continuar.";
  }

  if(assigneeSelect){
    assigneeSelect.addEventListener("change",()=>{
      clearRequestKey(app.id);
      assigneeId=assigneeSelect.value||null;
      assignmentState.complete=Boolean(assigneeId);
      assignmentState.blocking=assignment.blocking&&!assigneeId;
      assignmentCard.card.classList.toggle("is-pending",!assignmentState.complete);
      assignmentCard.card.classList.toggle("is-complete",assignmentState.complete);
      assignmentCard.state.textContent=assignmentState.complete?"Listo":"Pendiente";
      if(assignmentState.complete){
        const person=assignment.candidates.find(item=>item.user_id===assigneeId);
        assignmentCard.current.textContent=person?candidateLabel(person):"Persona seleccionada";
        assignmentCard.card.open=false;
      }else{
        assignmentCard.current.textContent=assignment.value;
        assignmentCard.card.open=true;
      }
      updateState();
    });
  }

  run.addEventListener("click",()=>executeNow(app,assigneeId,run));
  updateState();

  applicationsList.append(article);

  if(executionFromFlows){
    requestAnimationFrame(()=>{
      const firstPending=review.querySelector(".execution-review-card.is-pending > summary");
      if(firstPending){
        firstPending.focus({preventScroll:true});
        firstPending.scrollIntoView({block:"center",behavior:"smooth"});
      }
    });
  }
}

function buildExecutionControls(app,{guided=false}={}){
  const version=versionForApplication(app);
  const assignmentType=String(version?.spec?.assignmentType||"");
  const controls=document.createElement("div");controls.className="execution-controls";
  const controlTitle=document.createElement("strong");
  controlTitle.textContent=guided?"Último paso":"Ejecutar ahora";
  controls.append(controlTitle);

  let assigneeSelect=null;
  let executable=true;

  if(assignmentType==="manual"){
    const candidates=executionCandidates(app);
    const label=document.createElement("label");
    label.textContent=guided?"¿Quién realizará esta tarea?":"Responsable de esta ejecución";
    assigneeSelect=document.createElement("select");
    assigneeSelect.append(option("","Selecciona una persona"));
    assigneeSelect.append(...candidates.map(person=>option(person.user_id,candidateLabel(person))));
    assigneeSelect.addEventListener("change",()=>clearRequestKey(app.id));
    label.append(assigneeSelect);
    controls.append(label);
    if(!candidates.length){
      executable=false;
      const note=document.createElement("span");note.className="execution-note";
      note.textContent="No hay una persona con capacidad operativa disponible para este destino.";
      controls.append(note);
    }
  }else if(assignmentType==="property_responsible"){
    const note=document.createElement("span");note.className="execution-note";
    note.textContent="Se asignará al responsable operativo vigente del piso.";
    controls.append(note);
  }else{
    executable=false;
    const note=document.createElement("span");note.className="execution-note";
    note.textContent="Esta regla de asignación todavía no está habilitada para ejecución manual.";
    controls.append(note);
  }

  const run=document.createElement("button");
  run.type="button";
  run.className="primary";
  run.textContent="Ejecutar ahora";
  run.disabled=!executable;
  run.addEventListener("click",()=>executeNow(app,assigneeSelect?.value||null,run));
  controls.append(run);
  return controls;
}

function assignedUserLabel(userId,app){
  if(!userId)return "Asignada";
  const candidate=executionCandidates(app).find(item=>item.user_id===userId);
  if(candidate)return candidateLabel(candidate);
  if(currentUser?.id===userId)return currentUser.user_metadata?.display_name||currentUser.email||"Usuario asignado";
  const person=(permissionContext?.people||[]).find(item=>item.user_id===userId);
  return person?.display_name||person?.email||"Usuario asignado";
}

function renderGuidedReady(app){
  if(executionIntent&&!guidedExecutionId){
    renderExecutionAssist(app);
    return;
  }

  const version=versionForApplication(app);
  const guidedExecution=guidedExecutionId
    ?executions.find(item=>item.id===guidedExecutionId&&item.application_id===app.id)||null
    :null;
  const article=document.createElement("article");
  article.className="application-card application-ready-card";

  const head=document.createElement("div");head.className="application-item-head";
  const title=document.createElement("h3");title.textContent=definition?.name||"Flujo";
  const badge=document.createElement("span");badge.className="application-badge";badge.textContent=guidedExecutionId?"Ejecutado":"Listo";
  head.append(title,badge);

  const details=document.createElement("div");details.className="application-meta application-ready-summary";
  details.append(
    meta("Destino",targetLabel(app)),
    meta("Qué hará",stepsSummary(version)),
    meta("Asignación",guidedExecution?assignedUserLabel(guidedExecution.assigned_user_id,app):(assignmentLabels[String(version?.spec?.assignmentType||"")]||"Configurada")),
    meta("Versión","v"+(version?.version||"?"))
  );
  if(versionNeedsPhoto(version))details.append(meta("Fotografías",applicationPhotoLabel(app)));
  article.append(head,details);

  if(guidedExecutionId){
    const done=document.createElement("div");done.className="application-complete";
    const strong=document.createElement("strong");strong.textContent="Tarea creada";
    const p=document.createElement("p");
    const actions=document.createElement("div");actions.className="application-guided-actions";

    const nextUrl=batchNextUrl();
    if(batchQueue&&nextUrl){
      p.textContent=batchProgressLabel()+" completado. Continúa con el siguiente flujo de la selección.";
      const next=document.createElement("a");
      next.className="primary";
      next.href=nextUrl;
      next.textContent="Siguiente flujo · "+(batchIndex+2)+" de "+batchQueue.items.length;
      const cancel=document.createElement("a");
      cancel.className="secondary";
      cancel.href="./workflow-definitions.html";
      cancel.textContent="Cancelar ejecución masiva";
      cancel.addEventListener("click",clearBatchQueue);
      actions.append(next,cancel);
    }else{
      if(batchQueue)clearBatchQueue();
      p.textContent=batchQueue
        ?"Ejecución masiva completada. Todas las tareas preparadas en esta selección ya han sido procesadas."
        :"El flujo ya se ejecutó y la tarea está disponible para la persona asignada.";
      const tasks=document.createElement("a");tasks.className="primary";tasks.href="./workflow-tasks.html";tasks.textContent="Abrir Tareas";
      const flows=document.createElement("a");flows.className="secondary";flows.href="./workflow-definitions.html";flows.textContent="Volver a Mis Flujos";
      actions.append(tasks,flows);
    }

    done.append(strong,p,actions);
    article.append(done);
  }else{
    article.append(buildExecutionControls(app,{guided:true}));
  }
  applicationsList.append(article);
}

function renderApplications(){
  applicationsList.replaceChildren();

  if(guidedSetup&&guidedApplicationId){
    const guided=applications.find(item=>item.id===guidedApplicationId);
    if(!guided){
      const empty=document.createElement("article");empty.className="application-empty";
      empty.textContent="No se encontró el destino recién preparado. Puedes volver a gestionarlo desde Mis Flujos.";
      applicationsList.append(empty);
      return;
    }
    renderGuidedReady(guided);
    return;
  }

  if(!applications.length){
    const empty=document.createElement("article");empty.className="application-empty";
    empty.textContent="Todavía no hay destinos configurados para este flujo.";
    applicationsList.append(empty);return;
  }

  applications.forEach(app=>{
    const article=document.createElement("article");article.className="application-card";
    const head=document.createElement("div");head.className="application-item-head";
    const title=document.createElement("h3");title.textContent=targetLabel(app);
    const badge=document.createElement("span");badge.className="application-badge application-badge--"+app.status;badge.textContent=app.status==="configured"?"Disponible":"Archivado";
    head.append(title,badge);

    const appExecutions=executions.filter(item=>item.application_id===app.id);
    const latestExecution=appExecutions[0]||null;
    const details=document.createElement("div");details.className="application-meta";
    const version=versionForApplication(app);
    details.append(
      meta("Alcance",scopeLabels[app.scope_type]||app.scope_type),
      meta("Versión","v"+(version?.version||"?")),
      meta("Preparado",fmtDate(app.created_at)),
      meta("Ejecuciones",String(appExecutions.length)),
      meta("Última ejecución",executionLabel(latestExecution))
    );
    if(versionNeedsPhoto(version))details.append(meta("Fotografías",applicationPhotoLabel(app)));
    article.append(head,details);

    if(app.status==="configured"){
      article.append(buildExecutionControls(app));

      const actions=document.createElement("div");actions.className="application-actions";
      const archive=document.createElement("button");archive.type="button";archive.className="danger-soft";archive.textContent="Archivar destino";
      archive.addEventListener("click",()=>archiveApplication(app));
      actions.append(archive);article.append(actions);
    }
    applicationsList.append(article);
  });
}

async function loadApplications(){
  const {data,error}=await supabase
    .from("workflow_applications_v2")
    .select("id,definition_version_id,scope_type,property_id,room_id,occupancy_id,status,created_at,archived_at")
    .eq("definition_id",definitionId)
    .order("created_at",{ascending:false});
  if(error)throw error;
  applications=data||[];

  const applicationIds=applications.map(item=>item.id);
  applicationPhotoResources=[];
  if(applicationIds.length){
    const {data:resourceData,error:resourceError}=await supabase
      .from("workflow_application_photo_resources_v2")
      .select("application_id,pattern_id,sort_order")
      .in("application_id",applicationIds)
      .order("sort_order");
    if(resourceError)throw resourceError;
    applicationPhotoResources=resourceData||[];

    const patternIds=[...new Set(applicationPhotoResources.map(item=>item.pattern_id))];
    if(patternIds.length){
      const {data:patternData,error:patternError}=await supabase
        .from("photo_patterns_v2")
        .select("id,name,target_key,version,contour_data")
        .in("id",patternIds);
      if(patternError)throw patternError;
      (patternData||[]).forEach(item=>photoPatternById.set(item.id,item));
    }
  }

  executions=[];
  if(applicationIds.length){
    const {data:executionData,error:executionError}=await supabase
      .from("workflow_executions_v2")
      .select("id,application_id,status,assigned_user_id,assignment_type,trigger_kind,created_at")
      .in("application_id",applicationIds)
      .order("created_at",{ascending:false});
    if(executionError)throw executionError;
    executions=executionData||[];
  }

  if(guidedSetup&&guidedExecutionId){
    const belongsToGuidedApplication=executions.some(item=>item.id===guidedExecutionId&&item.application_id===guidedApplicationId);
    if(belongsToGuidedApplication){
      setSetupStage("done");
    }else{
      guidedExecutionId=null;
      const url=new URL(window.location.href);
      url.searchParams.delete("execution");
      window.history.replaceState({},"",url);
      setSetupStage(guidedApplicationId?"ready":"destination");
    }
  }

  const roomIds=[...new Set(applications.map(x=>x.room_id).filter(Boolean))];
  if(roomIds.length){
    const {data}=await supabase.from("rooms_v2").select("id,property_id,label,status,archived_at").in("id",roomIds);
    (data||[]).forEach(item=>{if(!rooms.some(existing=>existing.id===item.id))rooms.push(item)});
  }
  const occupancyIds=[...new Set(applications.map(x=>x.occupancy_id).filter(Boolean))];
  if(occupancyIds.length){
    const {data}=await supabase.from("occupancies_v2").select("id,property_id,room_id,occupant_email,starts_on,ends_on,status,tenants_v2(full_name,email)").in("id",occupancyIds);
    (data||[]).forEach(item=>{if(!occupancies.some(existing=>existing.id===item.id))occupancies.push(item)});
  }
  renderApplications();
}

async function executeNow(app,assigneeId,button){
  const version=versionForApplication(app);
  const assignmentType=String(version?.spec?.assignmentType||"");
  if(assignmentType==="manual"&&!assigneeId){
    setStatus("Selecciona quién realizará esta tarea.",true);
    return;
  }

  const {storageKey,key}=requestKey(app.id);
  button.disabled=true;
  const original=button.textContent;
  button.textContent="Creando ejecución…";
  setStatus(guidedSetup?"Creando la tarea y validando la asignación…":"Creando una ejecución idempotente y validando la asignación…");

  const {data,error}=await supabase.rpc("execute_workflow_application_now_v1",{
    p_application_id:app.id,
    p_idempotency_key:key,
    p_assigned_user_id:assignmentType==="manual"?assigneeId:null
  });

  button.textContent=original;

  if(error){
    button.disabled=false;
    const known=String(error.message||"").includes("workflow_");
    if(known)sessionStorage.removeItem(storageKey);
    setStatus(errorText(error),true);
    return;
  }

  sessionStorage.removeItem(storageKey);
  const result=Array.isArray(data)?data[0]:null;
  if(guidedSetup){
    guidedExecutionId=result?.execution_id||"created";
    if(result?.execution_id){
      const url=new URL(window.location.href);
      url.searchParams.set("execution",result.execution_id);
      window.history.replaceState({},"",url);
    }
    setSetupStage("done");
    setStatus(result?.created_new===false
      ?"La ejecución ya existía y se recuperó sin crear un duplicado."
      :"Tarea creada. Ya está disponible para la persona asignada.");
    await loadApplications();
    return;
  }
  if(result?.created_new===false){
    setStatus("El reintento recuperó la ejecución existente; no se creó un duplicado.");
  }else{
    setStatus("Ejecución creada en estado Pendiente y tarea materializada sin duplicados.");
  }
  await loadApplications();
}

async function archiveApplication(app){
  if(!window.confirm("¿Archivar este destino? El flujo y su historial no se eliminarán."))return;
  setStatus("Archivando destino…");
  const {error}=await supabase.rpc("archive_workflow_application_v1",{p_application_id:app.id});
  if(error){setStatus(errorText(error),true);return}
  setStatus("Destino archivado. El flujo publicado permanece intacto.");
  await loadApplications();
}

propertySelect.addEventListener("change",async()=>{
  const scope=versionScope();
  try{
    if(scope==="room")await loadRoomsFor(propertySelect.value);
    if(scope==="occupancy")await loadOccupanciesFor(propertySelect.value);
    roomSelect.disabled=scope!=="room"||!propertySelect.value;
    occupancySelect.disabled=scope!=="occupancy"||!propertySelect.value;
    if(versionNeedsPhoto())await loadPhotoPatternsFor(propertySelect.value);
    refreshCreateAvailability();
  }catch{setStatus("No se pudieron cargar los destinos dependientes.",true)}
});
roomSelect.addEventListener("change",refreshCreateAvailability);
occupancySelect.addEventListener("change",refreshCreateAvailability);

versionSelect.addEventListener("change",async()=>{
  propertySelect.value="";
  roomSelect.replaceChildren(option("","Selecciona una habitación"));
  occupancySelect.replaceChildren(option("","Selecciona una ocupación vigente"));
  photoPatterns=[];
  photoPatternsBox.replaceChildren();
  await updateTargetControls();
});

form.addEventListener("submit",async event=>{
  event.preventDefault();
  const version=activeVersion();
  if(!version)return;
  const scope=versionScope();
  const photoPatternIds=versionNeedsPhoto(version)?selectedPhotoPatternIds():[];
  if(versionNeedsPhoto(version)&&!photoPatternIds.length){
    setStatus("Selecciona al menos un patrón fotográfico.",true);
    return;
  }
  if(transientSetup){
    transientTarget=targetFromControls();
    formCard.hidden=true;
    applicationsSection.hidden=false;
    setSetupStage("ready");
    renderTransientReady();
    setStatus("Destino preparado. Elige Publicar o Ejecutar.");
    window.scrollTo({top:0,behavior:"smooth"});
    return;
  }

  const args={
    p_definition_version_id:version.id,
    p_property_id:["property","room","occupancy"].includes(scope)?propertySelect.value||null:null,
    p_room_id:scope==="room"?roomSelect.value||null:null,
    p_occupancy_id:scope==="occupancy"?occupancySelect.value||null:null,
    p_photo_pattern_ids:photoPatternIds
  };
  createButton.disabled=true;
  createButton.textContent=guidedSetup?"Preparando…":"Guardando…";
  setStatus(guidedSetup?"Preparando el destino…":"Validando el destino en servidor…");
  const {data,error}=await supabase.rpc("create_workflow_application_v2",args);
  createButton.textContent=guidedSetup?"Continuar":"Guardar destino";
  if(error){
    createButton.disabled=false;
    setStatus(errorText(error),true);
    return;
  }

  const result=Array.isArray(data)?data[0]:null;
  if(guidedSetup&&result?.application_id){
    guidedApplicationId=result.application_id;
    const url=new URL(window.location.href);
    url.searchParams.set("application",guidedApplicationId);
    url.searchParams.delete("execution");
    guidedExecutionId=null;
    window.history.replaceState({},"",url);
    formCard.hidden=true;
    applicationsSection.hidden=false;
    setSetupStage("ready");
    await loadApplications();
    setStatus(executionIntent
      ?"Destino preparado. Completa únicamente los apartados abiertos para ejecutar."
      :"Destino preparado. Revisa quién realizará la tarea y pulsa Ejecutar ahora.");
    window.scrollTo({top:0,behavior:"smooth"});
    return;
  }

  setStatus(versionNeedsPhoto(version)?"Destino guardado con sus patrones fotográficos vinculados.":"Destino guardado.");
  propertySelect.value="";
  roomSelect.replaceChildren(option("","Selecciona una habitación"));
  occupancySelect.replaceChildren(option("","Selecciona una ocupación vigente"));
  await updateTargetControls();
  await loadApplications();
});

async function load(){
  batchQueue=loadBatchQueue();
  if(batchToken&&!batchQueue){
    setStatus("La selección de ejecución masiva ya no está disponible. Vuelve a Mis Flujos para seleccionar de nuevo.",true);
  }

  if(transientSetup){
    await loadTransient();
    return;
  }

  if(!definitionId){
    definitionBox.textContent="Falta identificar la definición.";
    applicationsList.replaceChildren();
    setStatus("Abre el flujo desde Mis Flujos.",true);
    return;
  }

  const {data:userData,error:userError}=await supabase.auth.getUser();
  if(userError||!userData?.user){setStatus("No se pudo validar la sesión.",true);return}
  currentUser=userData.user;
  const role=String(userData.user.app_metadata?.role||"").toLowerCase();
  if(!["root","admin"].includes(role)){
    setStatus("La preparación de destinos requiere acceso administrativo.",true);
    return;
  }

  const {data:def,error:defError}=await supabase
    .from("workflow_definitions_v2")
    .select("id,organization_id,name,scope_type,status")
    .eq("id",definitionId)
    .maybeSingle();
  if(defError||!def){setStatus("No se encontró la definición autorizada.",true);return}
  definition=def;

  const {data:versionData,error:versionError}=await supabase
    .from("workflow_definition_versions_v2")
    .select("id,definition_id,version,spec,published_at")
    .eq("definition_id",definitionId)
    .order("version",{ascending:false});
  if(versionError)throw versionError;
  versions=versionData||[];

  if(!versions.length){
    definitionBox.textContent="Esta definición todavía no tiene una versión publicada.";
    applicationsList.replaceChildren();
    setStatus("Publícala primero desde Mis Flujos.");
    return;
  }

  versionSelect.replaceChildren(...versions.map(item=>option(item.id,"v"+item.version+" · "+fmtDate(item.published_at))));
  if(guidedSetup&&Number.isFinite(setupVersionNumber)&&setupVersionNumber>0){
    const requested=versions.find(item=>Number(item.version)===setupVersionNumber);
    if(requested)versionSelect.value=requested.id;
  }
  await loadProperties();
  const available=properties.filter(item=>item.status!=="archived"&&!item.archived_at);
  propertySelect.replaceChildren(option("","Selecciona un piso"),...available.map(item=>option(item.id,item.name+(item.address_line?" · "+item.address_line:""))));

  const {data:contextData,error:contextError}=await supabase.rpc("get_permission_management_context",{p_organization_id:definition.organization_id});
  permissionContext=contextError?null:contextData;

  renderDefinition();
  configurePresentation();
  formCard.hidden=guidedSetup&&Boolean(guidedApplicationId);
  if(applicationsSection&&guidedSetup)applicationsSection.hidden=!guidedApplicationId;
  await updateTargetControls();
  await loadApplications();

  if(guidedSetup){
    setStatus(guidedApplicationId
      ?(guidedExecutionId
        ?"Tarea creada. Puedes abrir Tareas o volver a Mis Flujos."
        :executionIntent
          ?"Completa únicamente los apartados abiertos para ejecutar."
          :"Destino preparado. Revisa la asignación y pulsa Ejecutar ahora.")
      :executionIntent
        ?"Falta el destino. Completa los campos resaltados para continuar."
        :"Diseño completado. Elige dónde quieres utilizar este flujo.");
  }else if(revisionPublished){
    setStatus("Nueva versión publicada. Revisa los destinos existentes o prepara uno nuevo para esta versión.");
  }else{
    setStatus("Destinos cargados. Puedes preparar uno nuevo o ejecutar el flujo desde un destino disponible.");
  }
}

load().catch(()=>setStatus("No se pudieron cargar las aplicaciones del flujo.",true));


window.addEventListener("beforeunload",event=>{
  if(!transientSetup||!transientPayload||transientFinalized)return;
  event.preventDefault();
  event.returnValue="";
});
