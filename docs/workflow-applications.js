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

const params=new URLSearchParams(window.location.search);
const definitionId=params.get("definition")||"";
const guidedSetup=params.get("setup")==="1";
const revisionPublished=params.get("published")==="1";
const setupVersionNumber=Number(params.get("version")||0);
let guidedApplicationId=params.get("application")||null;
let guidedExecutionId=null;
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

const EXECUTION_KEY_PREFIX="workflow-execute-now:";
const scopeLabels={organization:"Toda la organización",property:"Un piso",room:"Una habitación",occupancy:"Una ocupación / inquilino"};
const executionStatusLabels={pending:"Pendiente",active:"Activa",waiting_review:"Esperando revisión",completed:"Completada",cancelled:"Cancelada",failed:"Fallida"};
const assignmentLabels={
  manual:"Se decide al iniciar",
  property_responsible:"Responsable operativo del piso",
  active_occupants_rotation:"Ocupantes activos en rotación",
  fixed_person:"Persona fija",
  role:"Rol o capacidad"
};

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
  if(pageTitle)pageTitle.textContent="Preparar flujo";
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


async function loadProperties(){
  const {data,error}=await supabase
    .from("properties_v2")
    .select("id,name,address_line,city,status,archived_at")
    .eq("organization_id",definition.organization_id)
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

function refreshCreateAvailability(){
  const scope=versionScope();
  const available=properties.filter(item=>item.status!=="archived"&&!item.archived_at);
  let disabled=false;

  if(scope!=="organization"&&!available.length)disabled=true;
  if(versionNeedsPhoto()){
    if(scope==="organization"||!propertySelect.value||selectedPhotoPatternIds().length<1)disabled=true;
  }

  createButton.disabled=disabled;
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
  const eyebrow=document.createElement("p");eyebrow.className="eyebrow";eyebrow.textContent=guidedSetup?"Diseño completado":"Flujo publicado";
  const title=document.createElement("h2");title.textContent=definition.name;
  head.append(eyebrow,title);
  const info=document.createElement("div");info.className="application-meta";
  const version=activeVersion();
  if(guidedSetup){
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

function renderGuidedReady(app){
  const version=versionForApplication(app);
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
    meta("Asignación",assignmentLabels[String(version?.spec?.assignmentType||"")]||"Configurada"),
    meta("Versión","v"+(version?.version||"?"))
  );
  if(versionNeedsPhoto(version))details.append(meta("Fotografías",applicationPhotoLabel(app)));
  article.append(head,details);

  if(guidedExecutionId){
    const done=document.createElement("div");done.className="application-complete";
    const strong=document.createElement("strong");strong.textContent="Tarea creada";
    const p=document.createElement("p");p.textContent="El flujo ya se ejecutó y la tarea está disponible para la persona asignada.";
    const actions=document.createElement("div");actions.className="application-guided-actions";
    const tasks=document.createElement("a");tasks.className="primary";tasks.href="./workflow-tasks.html";tasks.textContent="Abrir Tareas";
    const flows=document.createElement("a");flows.className="secondary";flows.href="./workflow-definitions.html";flows.textContent="Volver a Mis Flujos";
    actions.append(tasks,flows);
    done.append(strong,p,actions);
    article.append(done);
  }else{
    article.append(buildExecutionControls(app,{guided:true}));
    const actions=document.createElement("div");actions.className="application-guided-actions";
    const manage=document.createElement("a");manage.className="secondary";
    manage.href="./workflow-applications.html?definition="+encodeURIComponent(definitionId);
    manage.textContent="Gestionar destinos";
    actions.append(manage);
    article.append(actions);
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
    window.history.replaceState({},"",url);
    formCard.hidden=true;
    applicationsSection.hidden=false;
    setSetupStage("ready");
    await loadApplications();
    setStatus("Destino preparado. Revisa quién realizará la tarea y pulsa Ejecutar ahora.");
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
      ?"Destino preparado. Revisa la asignación y pulsa Ejecutar ahora."
      :"Diseño completado. Elige dónde quieres utilizar este flujo.");
  }else if(revisionPublished){
    setStatus("Nueva versión publicada. Revisa los destinos existentes o prepara uno nuevo para esta versión.");
  }else{
    setStatus("Destinos cargados. Puedes preparar uno nuevo o ejecutar el flujo desde un destino disponible.");
  }
}

load().catch(()=>setStatus("No se pudieron cargar las aplicaciones del flujo.",true));
