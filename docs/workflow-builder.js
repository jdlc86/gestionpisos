import { supabase } from "./supabase-client.js";

const AUTHORING_VERSION=2;
const DRAFT_KEY="gestionpisos.workflow-builder.draft.v2";
const form=document.getElementById("workflowBuilderForm");
const panels=[...document.querySelectorAll(".builder-panel")];
const stepButtons=[...document.querySelectorAll(".builder-step")];
const backButton=document.getElementById("builderBack");
const nextButton=document.getElementById("builderNext");
const clearButton=document.getElementById("builderClear");
const saveButton=document.getElementById("builderSave");
const triggerType=document.getElementById("triggerType");
const recurrenceRow=document.getElementById("recurrenceRow");
const summary=document.getElementById("workflowSummary");
const serverStatus=document.getElementById("builderServerStatus");
const builderBadge=document.getElementById("builderBadge");
let currentStep=0;
let currentDefinitionId=new URLSearchParams(window.location.search).get("id")||null;
let currentRevision=null;
let loadingServerDraft=false;
let legacyDraftNeedsReview=false;

const labels={
  flowType:{cleaning:"Limpieza",inspection:"Inspección",maintenance:"Mantenimiento",checkin:"Check-in",checkout:"Check-out",custom:"Personalizado"},
  scopeType:{property:"Un piso",organization:"Toda la organización",room:"Una habitación",occupancy:"Una ocupación / inquilino"},
  triggerType:{manual:"Manual",recurring:"Recurrente",scheduled_once:"Fecha concreta",event:"Por evento"},
  recurrence:{weekly:"Cada semana",biweekly:"Cada 2 semanas",monthly:"Cada mes",custom:"Personalizada"},
  assignmentType:{property_responsible:"Responsable operativo del piso",active_occupants_rotation:"Ocupantes activos en rotación",fixed_person:"Persona fija",role:"Rol o capacidad",manual:"Se decide al iniciar"},
  closeType:{auto:"Automáticamente al completar pasos",human_review:"Tras revisión humana",domain_adapter:"Según regla especializada del flujo"}
};

function field(name){return form.elements.namedItem(name)}
function checked(name){return Boolean(field(name)?.checked)}
function value(name){return String(field(name)?.value||"").trim()}
function label(group,key){return labels[group]?.[key]||key||"Pendiente"}
function setChecked(name,next){const node=field(name);if(node)node.checked=Boolean(next)}

function draft(){
  return {
    authoringVersion:AUTHORING_VERSION,
    flowName:value("flowName"),
    flowType:value("flowType"),
    flowDescription:value("flowDescription"),
    scopeType:value("scopeType"),
    triggerType:value("triggerType"),
    recurrence:value("recurrence"),
    assignmentType:value("assignmentType"),
    steps:{accept:checked("stepAccept"),photo:checked("stepPhoto"),checklist:checked("stepChecklist"),document:checked("stepDocument")},
    closeType:value("closeType"),
    notifications:{onCreate:checked("notifyOnCreate"),onClose:checked("notifyOnClose")},
    currentStep
  };
}

function serverDraft(){
  const data=draft();
  delete data.currentStep;
  return data;
}

function completion(data=draft()){
  const sections=[
    {key:"identity",label:"Identidad",complete:data.flowName.trim().length>=3&&Boolean(data.flowType)},
    {key:"scope",label:"Ámbito",complete:Boolean(data.scopeType)},
    {key:"trigger",label:"Activación",complete:Boolean(data.triggerType)&&(data.triggerType!=="recurring"||Boolean(data.recurrence))},
    {key:"assignment",label:"Asignación",complete:Boolean(data.assignmentType)},
    {key:"steps",label:"Pasos y recursos",complete:Object.values(data.steps||{}).some(Boolean)},
    {key:"close",label:"Cierre",complete:Boolean(data.closeType)}
  ];
  const completed=sections.filter(section=>section.complete).length;
  return {sections,completed,total:sections.length,complete:completed===sections.length};
}

function saveLocalDraft(){
  if(loadingServerDraft)return;
  try{sessionStorage.setItem(DRAFT_KEY,JSON.stringify(draft()))}catch{}
}

function applyDraft(saved,{restoreStep=true}={}){
  if(!saved||typeof saved!=="object")return;
  for(const name of ["flowName","flowType","flowDescription","scopeType","triggerType","recurrence","assignmentType","closeType"]){
    const node=field(name);
    if(node&&typeof saved[name]==="string")node.value=saved[name];
  }
  setChecked("stepAccept",saved.steps?.accept);
  setChecked("stepPhoto",saved.steps?.photo);
  setChecked("stepChecklist",saved.steps?.checklist);
  setChecked("stepDocument",saved.steps?.document);
  setChecked("notifyOnCreate",saved.notifications?.onCreate);
  setChecked("notifyOnClose",saved.notifications?.onClose);
  if(restoreStep&&Number.isInteger(saved.currentStep))currentStep=Math.max(0,Math.min(panels.length-1,saved.currentStep));
}

function restoreLocalDraft(){
  let saved=null;
  try{saved=JSON.parse(sessionStorage.getItem(DRAFT_KEY)||"null")}catch{}
  applyDraft(saved);
}

function resetDecisionsKeepingIdentity(saved){
  form.reset();
  const name=field("flowName");
  const description=field("flowDescription");
  if(name)name.value=String(saved?.flowName||"");
  if(description)description.value=String(saved?.flowDescription||"");
  currentStep=0;
}

function setServerStatus(message,tone="neutral"){
  if(!serverStatus)return;
  serverStatus.textContent=message;
  serverStatus.dataset.tone=tone;
}

function errorMessage(error){
  const text=String(error?.message||error?.details||"");
  if(text.includes("workflow_draft_conflict"))return "Este borrador cambió en otra sesión. Recarga antes de volver a guardar para no sobrescribir cambios.";
  if(text.includes("workflow_author_role_required"))return "Solo ROOT o ADMIN pueden guardar definiciones de flujo.";
  if(text.includes("workflow_definition_not_editable"))return "Este flujo ya no es un borrador editable.";
  if(text.includes("workflow_definition_not_found"))return "No se encontró este borrador o ya no pertenece a tu ámbito.";
  if(text.includes("workflow_name_invalid"))return "El borrador necesita un nombre de al menos 3 caracteres para poder guardarse.";
  if(text.includes("not_authenticated"))return "La sesión ya no es válida. Vuelve a iniciar sesión.";
  if(text.includes("organization_selection_required"))return "No se puede determinar de forma inequívoca la organización del borrador.";
  return "No se pudo guardar el borrador en el servidor. No se ha publicado ni creado ninguna tarea.";
}

function updateTriggerFields({clearHidden=false}={}){
  const recurring=triggerType.value==="recurring";
  recurrenceRow.hidden=!recurring;
  if(clearHidden&&!recurring){
    const recurrence=field("recurrence");
    if(recurrence)recurrence.value="";
  }
}

function updateCompletionUI(){
  const state=completion();
  stepButtons.forEach((button,index)=>{
    const section=state.sections[index];
    button.classList.toggle("is-complete",Boolean(section?.complete));
    button.classList.toggle("is-pending",Boolean(section&&!section.complete));
    if(section)button.title=section.complete?section.label+": configurado":section.label+": pendiente";
  });
  if(builderBadge){
    builderBadge.textContent=state.complete?"Configuración completa":"Borrador incompleto";
  }
  return state;
}

async function loadServerDraft(){
  if(!currentDefinitionId)return;
  loadingServerDraft=true;
  setServerStatus("Cargando borrador guardado…");
  const {data,error}=await supabase
    .from("workflow_definitions_v2")
    .select("id,status,revision,draft_spec,authoring_complete,updated_at")
    .eq("id",currentDefinitionId)
    .maybeSingle();

  if(error||!data){
    loadingServerDraft=false;
    setServerStatus(error?errorMessage(error):"No se encontró este borrador o no tienes permiso para verlo.","error");
    saveButton.disabled=true;
    return;
  }
  if(data.status!=="draft"){
    loadingServerDraft=false;
    setServerStatus("Este flujo ya no está en estado borrador y no puede editarse desde esta pantalla.","error");
    saveButton.disabled=true;
    return;
  }

  currentRevision=Number(data.revision);
  const savedVersion=Number(data.draft_spec?.authoringVersion||1);
  if(savedVersion<AUTHORING_VERSION){
    legacyDraftNeedsReview=true;
    resetDecisionsKeepingIdentity(data.draft_spec);
  }else{
    applyDraft(data.draft_spec,{restoreStep:false});
    currentStep=0;
  }

  loadingServerDraft=false;
  updateTriggerFields();
  showStep(0,false);
  if(legacyDraftNeedsReview){
    setServerStatus("Borrador guardado · revisión "+currentRevision+". Se creó antes del control de decisiones explícitas: conservamos nombre y descripción, pero debes configurar los demás apartados antes de considerarlo completo.","warning");
  }else{
    const state=completion();
    setServerStatus(
      state.complete
        ?"Borrador guardado · revisión "+currentRevision+" · configuración completa. Aún no está publicado."
        :"Borrador guardado · revisión "+currentRevision+" · incompleto ("+state.completed+"/"+state.total+" apartados).",
      state.complete?"success":"neutral"
    );
  }
}

function validateBeforeSave(){
  const name=field("flowName");
  if(!name||name.value.trim().length<3){
    currentStep=0;
    showStep(0,true);
    name?.setCustomValidity("Escribe un nombre de al menos 3 caracteres.");
    name?.reportValidity();
    name?.setCustomValidity("");
    return false;
  }
  return true;
}

function summaryRow(title,text){
  const row=document.createElement("div");row.className="builder-summary-row";
  const strong=document.createElement("strong");strong.textContent=title;
  const span=document.createElement("span");span.textContent=text||"Pendiente";
  row.append(strong,span);return row;
}

function renderSummary(){
  if(!summary)return;
  const data=draft();
  const state=completion(data);
  const stepNames=[];
  if(data.steps.accept)stepNames.push("Confirmar / aceptar");
  if(data.steps.photo)stepNames.push("Evidencia fotográfica");
  if(data.steps.checklist)stepNames.push("Checklist / formulario");
  if(data.steps.document)stepNames.push("Documento");
  const notificationNames=[];
  if(data.notifications.onCreate)notificationNames.push("al crear tarea");
  if(data.notifications.onClose)notificationNames.push("al cerrar flujo");
  const pending=state.sections.filter(section=>!section.complete).map(section=>section.label);
  summary.replaceChildren(
    summaryRow("Estado",state.complete?"Configuración completa":"Borrador incompleto · "+state.completed+"/"+state.total),
    summaryRow("Pendiente",pending.length?pending.join(", "):"Nada pendiente en el asistente"),
    summaryRow("Nombre",data.flowName||"Sin nombre"),
    summaryRow("Tipo",label("flowType",data.flowType)),
    summaryRow("Ámbito",label("scopeType",data.scopeType)),
    summaryRow("Activación",data.triggerType==="recurring"?label("triggerType",data.triggerType)+" · "+label("recurrence",data.recurrence):label("triggerType",data.triggerType)),
    summaryRow("Asignación",label("assignmentType",data.assignmentType)),
    summaryRow("Pasos",stepNames.length?stepNames.join(" → "):"Pendiente"),
    summaryRow("Cierre",label("closeType",data.closeType)),
    summaryRow("Notificaciones",notificationNames.length?notificationNames.join(" y "):"Sin notificaciones"),
    summaryRow("Descripción",data.flowDescription||"Sin descripción")
  );
}

function showStep(next,shouldScroll=false){
  currentStep=Math.max(0,Math.min(panels.length-1,next));
  panels.forEach((panel,index)=>panel.classList.toggle("is-active",index===currentStep));
  stepButtons.forEach((button,index)=>{
    button.classList.toggle("is-active",index===currentStep);
    if(index===currentStep)button.setAttribute("aria-current","step");else button.removeAttribute("aria-current");
  });
  backButton.disabled=currentStep===0;
  if(currentStep===panels.length-1){
    nextButton.textContent="Borrador revisado";
    nextButton.disabled=true;
    nextButton.classList.remove("primary");
    nextButton.classList.add("secondary");
    saveButton.classList.remove("secondary");
    saveButton.classList.add("primary");
    renderSummary();
  }else{
    nextButton.textContent="Continuar";
    nextButton.disabled=false;
    nextButton.classList.remove("secondary");
    nextButton.classList.add("primary");
    saveButton.classList.remove("primary");
    saveButton.classList.add("secondary");
  }
  updateCompletionUI();
  saveLocalDraft();
  if(shouldScroll)document.querySelector(".builder-card")?.scrollIntoView({block:"start",behavior:"smooth"});
}

async function saveServerDraft(){
  if(!validateBeforeSave())return;
  const originalText=saveButton.textContent;
  saveButton.disabled=true;
  saveButton.textContent="Guardando…";
  setServerStatus("Guardando borrador en GestionPisos…");

  const wasExisting=Boolean(currentDefinitionId);
  const previousRevision=currentRevision;
  const args={p_spec:serverDraft()};
  if(currentDefinitionId)args.p_definition_id=currentDefinitionId;
  if(currentDefinitionId&&Number.isFinite(currentRevision))args.p_expected_revision=currentRevision;

  const {data,error}=await supabase.rpc("save_workflow_definition_draft_v1",args);
  if(error||!Array.isArray(data)||!data[0]){
    setServerStatus(errorMessage(error),"error");
    saveButton.disabled=false;
    saveButton.textContent=originalText;
    return;
  }

  currentDefinitionId=data[0].definition_id;
  currentRevision=Number(data[0].revision);
  legacyDraftNeedsReview=false;
  const url=new URL(window.location.href);
  url.searchParams.set("id",currentDefinitionId);
  window.history.replaceState({},"",url);
  saveLocalDraft();

  const {data:persisted}=await supabase
    .from("workflow_definitions_v2")
    .select("authoring_complete")
    .eq("id",currentDefinitionId)
    .maybeSingle();

  const state=completion();
  const serverComplete=Boolean(persisted?.authoring_complete);
  const noChanges=wasExisting&&Number.isFinite(previousRevision)&&currentRevision===previousRevision;
  setServerStatus(
    noChanges
      ?"Sin cambios · revisión "+currentRevision+". No se creó una revisión nueva."
      :serverComplete
        ?"Borrador guardado · revisión "+currentRevision+" · configuración completa. Todavía no está publicado."
        :"Borrador guardado · revisión "+currentRevision+" · incompleto ("+state.completed+"/"+state.total+" apartados). Puedes continuar después desde Mis Flujos.",
    noChanges||serverComplete?"success":"neutral"
  );
  saveButton.disabled=false;
  saveButton.textContent="Guardar borrador";
  updateCompletionUI();
  if(currentStep===panels.length-1)renderSummary();
}

form.addEventListener("input",()=>{saveLocalDraft();updateCompletionUI();if(currentStep===panels.length-1)renderSummary()});
form.addEventListener("change",event=>{
  if(event.target===triggerType)updateTriggerFields({clearHidden:true});
  saveLocalDraft();
  updateCompletionUI();
  if(currentStep===panels.length-1)renderSummary();
});
backButton.addEventListener("click",()=>showStep(currentStep-1,true));
nextButton.addEventListener("click",()=>showStep(currentStep+1,true));
stepButtons.forEach((button,index)=>button.addEventListener("click",()=>showStep(index,true)));
saveButton.addEventListener("click",saveServerDraft);
clearButton.addEventListener("click",()=>{
  const message=currentDefinitionId
    ?"¿Descartar los cambios locales? El borrador guardado en el servidor no se eliminará."
    :"¿Borrar el borrador local de este flujo?";
  if(!window.confirm(message))return;
  try{sessionStorage.removeItem(DRAFT_KEY)}catch{}
  form.reset();
  currentStep=0;
  legacyDraftNeedsReview=false;
  updateTriggerFields();
  showStep(0,true);
  setServerStatus(currentDefinitionId
    ?"Cambios locales descartados. El borrador guardado (revisión "+currentRevision+") sigue existiendo; recarga o vuelve desde Mis Flujos para recuperarlo."
    :"Borrador local eliminado. Aún no existe ningún borrador guardado en el servidor.");
});

(async()=>{
  if(currentDefinitionId){
    await loadServerDraft();
  }else{
    restoreLocalDraft();
    updateTriggerFields();
    showStep(currentStep);
    const state=completion();
    setServerStatus("Aún no guardado en el servidor · "+state.completed+"/"+state.total+" apartados configurados. Puedes guardar el borrador aunque esté incompleto.");
  }
})();
