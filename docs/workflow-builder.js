import { supabase } from "./supabase-client.js";

const AUTHORING_VERSION=2;
const DRAFT_KEY="gestionpisos.workflow-builder.draft.v3";
const LEGACY_DRAFT_KEY="gestionpisos.workflow-builder.draft.v2";
const form=document.getElementById("workflowBuilderForm");
const panels=[...document.querySelectorAll(".builder-panel")];
const stepButtons=[...document.querySelectorAll(".builder-step")];
const backButton=document.getElementById("builderBack");
const nextButton=document.getElementById("builderNext");
const clearButton=document.getElementById("builderClear");
const saveButton=document.getElementById("builderSave");
const saveExitButton=document.getElementById("builderSaveExitInline");
const publishButton=document.getElementById("builderPublish");
const draftsView=document.getElementById("builderDraftsView");
const editorView=document.getElementById("builderEditorView");
const editorTitle=document.getElementById("builderEditorTitle");
const exitEditorButton=document.getElementById("builderExitEditor");
const exitDialog=document.getElementById("builderExitDialog");
const exitSaveButton=document.getElementById("builderExitSave");
const exitDiscardButton=document.getElementById("builderExitDiscard");
const exitCancelButton=document.getElementById("builderExitCancel");
const draftsList=document.getElementById("builderDrafts");
const draftSearch=document.getElementById("builderDraftSearch");
const draftFilter=document.getElementById("builderDraftFilter");
const draftCount=document.getElementById("builderDraftCount");
const draftLoadMore=document.getElementById("builderDraftLoadMore");
const draftStatus=document.getElementById("builderDraftStatus");
const triggerType=document.getElementById("triggerType");
const recurrenceRow=document.getElementById("recurrenceRow");
const customRecurrenceRow=document.getElementById("customRecurrenceRow");
const scheduledAtRow=document.getElementById("scheduledAtRow");
const photoBankLink=document.getElementById("photoBankLink");
const checklistEditor=document.getElementById("checklistEditor");
const checklistItemsBox=document.getElementById("checklistItems");
const addChecklistItemButton=document.getElementById("addChecklistItem");
const summary=document.getElementById("workflowSummary");
const serverStatus=document.getElementById("builderServerStatus");
const builderBadge=document.getElementById("builderBadge");
const initialParams=new URLSearchParams(window.location.search);
const newDraftMode=initialParams.get("new")==="1";
const editorRequested=Boolean(initialParams.get("id"))||newDraftMode;
let currentStep=0;
let currentDefinitionId=initialParams.get("id")||null;
let revisionMode=initialParams.get("revision")==="1";
let currentRevision=null;
let currentBaseVersion=null;
let loadingServerDraft=false;
let legacyDraftNeedsReview=false;
let savedSnapshot=null;
let allowNavigation=false;
let draftItems=[];
let draftVisibleLimit=12;

const labels={
  flowType:{cleaning:"Limpieza",inspection:"Inspección",maintenance:"Mantenimiento",checkin:"Check-in",checkout:"Check-out",custom:"Personalizado"},
  scopeType:{property:"Un piso",organization:"Toda la organización",room:"Una habitación",occupancy:"Una ocupación / inquilino"},
  triggerType:{manual:"Manual",recurring:"Recurrente",scheduled_once:"Fecha concreta",event:"Por evento"},
  recurrence:{weekly:"Cada semana",biweekly:"Cada 2 semanas",monthly:"Cada mes",custom:"Personalizada"},
  customUnit:{day:"día(s)",week:"semana(s)",month:"mes(es)"},
  assignmentType:{property_responsible:"Responsable operativo del piso",active_occupants_rotation:"Ocupantes activos en rotación",fixed_person:"Persona fija",role:"Rol o capacidad",manual:"Se decide al iniciar"},
  closeType:{auto:"Automáticamente al completar pasos",human_review:"Tras revisión humana",domain_adapter:"Según regla especializada del flujo"}
};

function field(name){return form.elements.namedItem(name)}
function checked(name){return Boolean(field(name)?.checked)}
function value(name){return String(field(name)?.value||"").trim()}
function label(group,key){return labels[group]?.[key]||key||"Pendiente"}
function setChecked(name,next){const node=field(name);if(node)node.checked=Boolean(next)}

function checklistItemsDraft(){
  if(!checklistItemsBox)return [];
  return [...checklistItemsBox.querySelectorAll(".builder-checklist-item")].map(row=>({
    text:String(row.querySelector("[data-checklist-text]")?.value||"").trim(),
    required:Boolean(row.querySelector("[data-checklist-required]")?.checked)
  }));
}

function notifyChecklistChanged(){
  saveLocalDraft();
  updateCompletionUI();
  if(currentStep===panels.length-1)renderSummary();
}

function addChecklistItem(item={text:"",required:true},{focus=false}={}){
  if(!checklistItemsBox)return;
  if(checklistItemsBox.children.length>=30){
    setServerStatus("El checklist admite un máximo de 30 elementos.","warning");
    return;
  }
  const row=document.createElement("div");
  row.className="builder-checklist-item";

  const main=document.createElement("div");
  main.className="builder-checklist-item-main";

  const input=document.createElement("input");
  input.type="text";
  input.maxLength=160;
  input.placeholder="Ej. Comprobar que las ventanas quedan cerradas";
  input.value=String(item?.text||"");
  input.setAttribute("data-checklist-text","1");
  input.setAttribute("aria-label","Texto del elemento de checklist");

  const requiredLabel=document.createElement("label");
  requiredLabel.className="builder-checklist-required";
  const required=document.createElement("input");
  required.type="checkbox";
  required.checked=item?.required!==false;
  required.setAttribute("data-checklist-required","1");
  requiredLabel.append(required,document.createTextNode("Obligatorio"));

  main.append(input,requiredLabel);

  const actions=document.createElement("div");
  actions.className="builder-checklist-item-actions";
  const up=document.createElement("button");
  up.type="button";up.className="builder-checklist-icon-button";up.textContent="↑";up.title="Subir";up.setAttribute("aria-label","Subir elemento");
  const down=document.createElement("button");
  down.type="button";down.className="builder-checklist-icon-button";down.textContent="↓";down.title="Bajar";down.setAttribute("aria-label","Bajar elemento");
  const remove=document.createElement("button");
  remove.type="button";remove.className="builder-checklist-icon-button builder-checklist-icon-button--danger";remove.textContent="×";remove.title="Eliminar";remove.setAttribute("aria-label","Eliminar elemento");

  up.addEventListener("click",()=>{
    const previous=row.previousElementSibling;
    if(previous){checklistItemsBox.insertBefore(row,previous);notifyChecklistChanged()}
  });
  down.addEventListener("click",()=>{
    const next=row.nextElementSibling;
    if(next){checklistItemsBox.insertBefore(next,row);notifyChecklistChanged()}
  });
  remove.addEventListener("click",()=>{row.remove();notifyChecklistChanged()});

  actions.append(up,down,remove);
  row.append(main,actions);
  checklistItemsBox.append(row);
  if(focus)input.focus();
}

function renderChecklistItems(items=[]){
  if(!checklistItemsBox)return;
  checklistItemsBox.replaceChildren();
  (Array.isArray(items)?items:[]).slice(0,30).forEach(item=>addChecklistItem(item));
}

function updateChecklistEditor(){
  if(!checklistEditor)return;
  const enabled=checked("stepChecklist");
  checklistEditor.hidden=!enabled;
  if(enabled&&!checklistItemsBox.children.length){
    addChecklistItem({text:"",required:true});
  }
}

function checklistConfigurationComplete(data){
  if(!data.steps?.checklist)return true;
  const items=Array.isArray(data.checklistItems)?data.checklistItems:[];
  return items.length>0
    && items.length<=30
    && items.every(item=>String(item?.text||"").trim().length>=1&&String(item?.text||"").trim().length<=160)
    && items.some(item=>item?.required!==false);
}

function draft(){
  return {
    authoringVersion:AUTHORING_VERSION,
    flowName:value("flowName"),
    flowType:value("flowType"),
    flowDescription:value("flowDescription"),
    scopeType:value("scopeType"),
    triggerType:value("triggerType"),
    recurrence:value("recurrence"),
    scheduledAt:value("scheduledAt"),
    customEvery:value("customEvery"),
    customUnit:value("customUnit"),
    assignmentType:value("assignmentType"),
    steps:{accept:checked("stepAccept"),photo:checked("stepPhoto"),checklist:checked("stepChecklist"),document:checked("stepDocument")},
    checklistItems:checked("stepChecklist")?checklistItemsDraft():[],
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

function specSnapshot(){
  return JSON.stringify(serverDraft());
}

function markSavedSnapshot(){
  savedSnapshot=specSnapshot();
}

function hasUnsavedChanges(){
  return editorRequested&&savedSnapshot!==null&&specSnapshot()!==savedSnapshot;
}

function updateEditorTitle(){
  if(!editorTitle)return;
  const name=value("flowName")||"Nuevo flujo";
  editorTitle.textContent=revisionMode&&currentBaseVersion
    ?"Nueva v"+(currentBaseVersion+1)+" · "+name
    :name;
}

function showWorkspaceView(){
  draftsView.hidden=editorRequested;
  editorView.hidden=!editorRequested;
  document.body.classList.toggle("builder-editor-active",editorRequested);
}

function goToDrafts(){
  allowNavigation=true;
  window.location.href="./workflow-builder.html";
}

function clearLocalDraftCache(){
  try{
    sessionStorage.removeItem(DRAFT_KEY);
    sessionStorage.removeItem(LEGACY_DRAFT_KEY);
  }catch{}
}

async function requestExitEditor(){
  if(!hasUnsavedChanges()){
    goToDrafts();
    return;
  }
  if(exitDialog?.showModal){
    exitDialog.showModal();
    return;
  }
  if(window.confirm("Hay cambios sin guardar. ¿Salir sin guardarlos?"))goToDrafts();
}

function completion(data=draft()){
  const sections=[
    {key:"identity",label:"Identidad",complete:data.flowName.trim().length>=3&&Boolean(data.flowType)},
    {key:"scope",label:"Ámbito",complete:Boolean(data.scopeType)},
    {key:"trigger",label:"Activación",complete:triggerComplete(data)},
    {key:"assignment",label:"Asignación",complete:Boolean(data.assignmentType)},
    {key:"steps",label:"Pasos y recursos",complete:Object.values(data.steps||{}).some(Boolean)&&checklistConfigurationComplete(data)},
    {key:"close",label:"Cierre",complete:Boolean(data.closeType)}
  ];
  const completed=sections.filter(section=>section.complete).length;
  return {sections,completed,total:sections.length,complete:completed===sections.length};
}

function triggerComplete(data){
  if(!data.triggerType)return false;
  if(data.triggerType==="manual"||data.triggerType==="event")return true;
  if(data.triggerType==="scheduled_once")return Boolean(data.scheduledAt);
  if(data.triggerType==="recurring"){
    if(!data.recurrence)return false;
    if(data.recurrence!=="custom")return true;
    const every=Number(data.customEvery);
    return Number.isInteger(every)&&every>=1&&every<=365&&["day","week","month"].includes(data.customUnit);
  }
  return false;
}

function saveLocalDraft(){
  if(loadingServerDraft||currentDefinitionId)return;
  try{sessionStorage.setItem(DRAFT_KEY,JSON.stringify(draft()))}catch{}
}

function applyDraft(saved,{restoreStep=true}={}){
  if(!saved||typeof saved!=="object")return;
  for(const name of ["flowName","flowType","flowDescription","scopeType","triggerType","recurrence","scheduledAt","customEvery","customUnit","assignmentType","closeType"]){
    const node=field(name);
    if(node&&typeof saved[name]==="string")node.value=saved[name];
  }
  setChecked("stepAccept",saved.steps?.accept);
  setChecked("stepPhoto",saved.steps?.photo);
  setChecked("stepChecklist",saved.steps?.checklist);
  setChecked("stepDocument",saved.steps?.document);
  renderChecklistItems(saved.checklistItems||[]);
  updateChecklistEditor();
  setChecked("notifyOnCreate",saved.notifications?.onCreate);
  setChecked("notifyOnClose",saved.notifications?.onClose);
  if(restoreStep&&Number.isInteger(saved.currentStep))currentStep=Math.max(0,Math.min(panels.length-1,saved.currentStep));
}

function restoreLocalDraft(){
  let saved=null;
  try{
    sessionStorage.removeItem(LEGACY_DRAFT_KEY);
    saved=JSON.parse(sessionStorage.getItem(DRAFT_KEY)||"null");
  }catch{}
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
  if(text.includes("aal2_required"))return "Para publicar debes completar MFA (sesión AAL2). El borrador permanece guardado.";
  if(text.includes("workflow_author_role_required"))return "Solo ROOT o ADMIN pueden guardar definiciones de flujo.";
  if(text.includes("workflow_definition_not_editable"))return "Este flujo ya no es un borrador editable.";
  if(text.includes("workflow_revision_draft_not_found"))return "No existe el borrador de la nueva versión. Vuelve a iniciarlo desde Mis Flujos.";
  if(text.includes("workflow_revision_base_version_conflict"))return "La versión publicada cambió mientras editabas. Vuelve a Mis Flujos y crea una nueva revisión.";
  if(text.includes("workflow_revision_requires_published_definition"))return "Solo una receta publicada puede generar una nueva versión.";
  if(text.includes("workflow_definition_not_found"))return "No se encontró este borrador o ya no pertenece a tu ámbito.";
  if(text.includes("workflow_checklist_too_many_items"))return "El checklist admite un máximo de 30 elementos.";
  if(text.includes("workflow_checklist_item_text_invalid"))return "Cada elemento del checklist admite hasta 160 caracteres.";
  if(text.includes("workflow_checklist_item_invalid")||text.includes("workflow_checklist_item_required_invalid"))return "Hay un elemento de checklist con formato no válido.";
  if(text.includes("workflow_name_invalid"))return "El borrador necesita un nombre de al menos 3 caracteres para poder guardarse.";
  if(text.includes("not_authenticated"))return "La sesión ya no es válida. Vuelve a iniciar sesión.";
  if(text.includes("organization_selection_required"))return "No se puede determinar de forma inequívoca la organización del borrador.";
  return "No se pudo guardar el borrador en el servidor. No se ha publicado ni creado ninguna tarea.";
}

function toggleDependentRow(row,enabled){
  if(!row)return;
  row.hidden=!enabled;
  row.querySelectorAll("input,select,textarea").forEach(control=>{control.disabled=!enabled});
}

function updateTriggerFields({clearHidden=false}={}){
  const type=value("triggerType");
  const recurrence=field("recurrence");
  const scheduledAt=field("scheduledAt");
  const customEvery=field("customEvery");
  const customUnit=field("customUnit");
  const recurring=type==="recurring";
  const scheduled=type==="scheduled_once";
  const custom=recurring&&value("recurrence")==="custom";

  toggleDependentRow(recurrenceRow,recurring);
  toggleDependentRow(customRecurrenceRow,custom);
  toggleDependentRow(scheduledAtRow,scheduled);

  if(clearHidden){
    if(!recurring&&recurrence)recurrence.value="";
    if(!custom){
      if(customEvery)customEvery.value="";
      if(customUnit)customUnit.value="";
    }
    if(!scheduled&&scheduledAt)scheduledAt.value="";
  }
}

function updatePhotoResource(){
  if(photoBankLink)photoBankLink.hidden=!checked("stepPhoto");
}

function updateCompletionUI(){
  updatePhotoResource();
  updateChecklistEditor();
  const state=completion();
  stepButtons.forEach((button,index)=>{
    const section=state.sections[index];
    button.classList.toggle("is-complete",Boolean(section?.complete));
    button.classList.toggle("is-pending",Boolean(section&&!section.complete));
    if(section)button.title=section.complete?section.label+": configurado":section.label+": pendiente";
  });
  updateEditorTitle();
  if(builderBadge){
    const completeLabel=revisionMode&&currentBaseVersion
      ?"Nueva v"+(currentBaseVersion+1)+" preparada"
      :"Configuración completa";
    builderBadge.textContent=state.complete?"Listo":"Borrador";
    builderBadge.title=state.complete?completeLabel:"Borrador incompleto";
    builderBadge.classList.toggle("is-complete",state.complete);
  }
  if(publishButton){
    publishButton.disabled=!state.complete||!currentDefinitionId;
  }
  return state;
}

async function loadServerDraft(){
  if(!currentDefinitionId)return;
  loadingServerDraft=true;
  setServerStatus(revisionMode?"Cargando borrador de nueva versión…":"Cargando borrador guardado…");

  const query=revisionMode
    ? supabase
        .from("workflow_definition_revision_drafts_v2")
        .select("definition_id,base_version,revision,draft_spec,authoring_complete,updated_at,published_at")
        .eq("definition_id",currentDefinitionId)
        .is("published_at",null)
    : supabase
        .from("workflow_definitions_v2")
        .select("id,status,revision,draft_spec,authoring_complete,updated_at")
        .eq("id",currentDefinitionId);

  const {data,error}=await query.maybeSingle();

  if(error||!data){
    loadingServerDraft=false;
    setServerStatus(error?errorMessage(error):"No se encontró este borrador o no tienes permiso para verlo.","error");
    saveButton.disabled=true;
    publishButton.disabled=true;
    return;
  }

  if(!revisionMode&&data.status!=="draft"){
    loadingServerDraft=false;
    setServerStatus("Esta receta ya está publicada. Las nuevas ediciones se crean desde Mis Flujos → Crear nueva versión.","error");
    saveButton.disabled=true;
    publishButton.disabled=true;
    return;
  }

  currentRevision=Number(data.revision);
  currentBaseVersion=revisionMode?Number(data.base_version):null;
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
    setServerStatus("Borrador guardado · revisión "+currentRevision+". Debes revisar sus decisiones explícitas antes de publicarlo.","warning");
  }else{
    const state=completion();
    const prefix=revisionMode
      ?"Nueva versión basada en v"+currentBaseVersion+" · borrador revisión "+currentRevision
      :"Borrador · revisión "+currentRevision;
    setServerStatus(
      state.complete
        ?prefix+" · configuración completa. Aún no está publicado."
        :prefix+" · incompleto ("+state.completed+"/"+state.total+" apartados).",
      state.complete?"success":"neutral"
    );
  }
  markSavedSnapshot();
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

function activationSummary(data){
  if(data.triggerType==="recurring"){
    if(data.recurrence==="custom"){
      const every=data.customEvery||"—";
      return "Recurrente · Cada "+every+" "+label("customUnit",data.customUnit);
    }
    return label("triggerType",data.triggerType)+" · "+label("recurrence",data.recurrence);
  }
  if(data.triggerType==="scheduled_once"){
    if(!data.scheduledAt)return "Fecha concreta · Pendiente";
    const parsed=new Date(data.scheduledAt);
    const shown=Number.isNaN(parsed.getTime())?data.scheduledAt:new Intl.DateTimeFormat("es-ES",{dateStyle:"medium",timeStyle:"short"}).format(parsed);
    return "Fecha concreta · "+shown;
  }
  return label("triggerType",data.triggerType);
}

function renderSummary(){
  if(!summary)return;
  const data=draft();
  const state=completion(data);
  const stepNames=[];
  if(data.steps.accept)stepNames.push("Decisión Aceptar / Rechazar");
  if(data.steps.photo)stepNames.push("Evidencia fotográfica");
  if(data.steps.checklist){
    const items=Array.isArray(data.checklistItems)?data.checklistItems:[];
    const required=items.filter(item=>item?.required!==false).length;
    stepNames.push("Checklist · "+items.length+" elemento"+(items.length===1?"":"s")+" ("+required+" obligatorio"+(required===1?"":"s")+")");
  }
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
    summaryRow("Activación",activationSummary(data)),
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
    nextButton.textContent="Revisión completa";
    nextButton.disabled=true;
    nextButton.classList.remove("builder-action--primary");
    renderSummary();
  }else{
    nextButton.textContent="Continuar";
    nextButton.disabled=false;
    nextButton.classList.add("builder-action--primary");
  }
  updateCompletionUI();
  saveLocalDraft();
  if(shouldScroll)document.querySelector(".builder-card")?.scrollIntoView({block:"start",behavior:"smooth"});
}

async function saveServerDraft(){
  if(!validateBeforeSave())return false;
  const originalText=saveButton.textContent;
  saveButton.disabled=true;
  saveButton.textContent="Guardando…";
  setServerStatus("Guardando borrador en GestionPisos…");

  const wasExisting=Boolean(currentDefinitionId);
  const previousRevision=currentRevision;
  const args=revisionMode
    ? {
        p_definition_id:currentDefinitionId,
        p_spec:serverDraft(),
        p_expected_revision:Number.isFinite(currentRevision)?currentRevision:null
      }
    : {p_spec:serverDraft()};
  if(!revisionMode&&currentDefinitionId)args.p_definition_id=currentDefinitionId;
  if(!revisionMode&&currentDefinitionId&&Number.isFinite(currentRevision))args.p_expected_revision=currentRevision;

  const rpc=revisionMode
    ?"save_workflow_definition_revision_draft_v1"
    :"save_workflow_definition_draft_v2";
  const {data,error}=await supabase.rpc(rpc,args);
  if(error||!Array.isArray(data)||!data[0]){
    setServerStatus(errorMessage(error),"error");
    saveButton.disabled=false;
    saveButton.textContent=originalText;
    return false;
  }

  currentDefinitionId=data[0].definition_id;
  currentRevision=Number(data[0].revision);
  if(revisionMode)currentBaseVersion=Number(data[0].base_version);
  legacyDraftNeedsReview=false;
  const url=new URL(window.location.href);
  url.searchParams.set("id",currentDefinitionId);
  url.searchParams.delete("new");
  if(revisionMode)url.searchParams.set("revision","1");else url.searchParams.delete("revision");
  window.history.replaceState({},"",url);
  try{
    sessionStorage.removeItem(DRAFT_KEY);
    sessionStorage.removeItem(LEGACY_DRAFT_KEY);
  }catch{}

  const persistedQuery=revisionMode
    ? supabase.from("workflow_definition_revision_drafts_v2").select("authoring_complete").eq("definition_id",currentDefinitionId).is("published_at",null)
    : supabase.from("workflow_definitions_v2").select("authoring_complete").eq("id",currentDefinitionId);
  const {data:persisted}=await persistedQuery.maybeSingle();

  const state=completion();
  const serverComplete=Boolean(persisted?.authoring_complete);
  const noChanges=wasExisting&&Number.isFinite(previousRevision)&&currentRevision===previousRevision;
  setServerStatus(
    noChanges
      ?"Sin cambios · revisión "+currentRevision
      :serverComplete
        ?"Guardado · revisión "+currentRevision+" · listo para continuar."
        :"Guardado · revisión "+currentRevision+" · "+state.completed+"/"+state.total+" apartados completos.",
    noChanges||serverComplete?"success":"neutral"
  );
  saveButton.disabled=false;
  saveButton.textContent="Guardar";
  updateCompletionUI();
  if(currentStep===panels.length-1)renderSummary();
  markSavedSnapshot();
  return true;
}


function draftDate(value){
  if(!value)return "—";
  try{return new Intl.DateTimeFormat("es-ES",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value))}catch{return value}
}

async function publishDefinition(definitionId,revision,{isRevision=false,button=null}={}){
  if(!window.confirm(isRevision
    ?"¿Publicar esta nueva versión? La versión actualmente operativa conservará su historial y después podrás revisar dónde utilizar la nueva."
    :"¿Continuar para usar este flujo? Se publicará una versión estable y después elegirás directamente dónde utilizarla."))return false;
  const original=button?.textContent;
  if(button){button.disabled=true;button.textContent="Preparando…"}
  setServerStatus("Publicando una versión estable antes de elegir el destino…");
  const rpc=isRevision
    ?"publish_workflow_definition_revision_v1"
    :"publish_workflow_definition_v1";
  const {data,error}=await supabase.rpc(rpc,{
    p_definition_id:definitionId,
    p_expected_revision:revision
  });
  if(error){
    if(button){button.disabled=false;button.textContent=original}
    setServerStatus(errorMessage(error),"error");
    return false;
  }
  const published=Array.isArray(data)?data[0]:null;
  const next=new URL("./workflow-applications.html",window.location.href);
  next.searchParams.set("definition",definitionId);
  if(published?.version)next.searchParams.set("version",String(published.version));
  if(isRevision)next.searchParams.set("published","1");
  else next.searchParams.set("setup","1");
  window.location.href=next.href;
  return true;
}

async function publishCurrentDraft(){
  const state=completion();
  if(!state.complete){
    setServerStatus("Completa todos los apartados antes de publicar.","warning");
    return;
  }
  const saved=await saveServerDraft();
  if(!saved)return;
  await publishDefinition(currentDefinitionId,currentRevision,{isRevision:revisionMode,button:publishButton});
}

function setDraftStatus(message,tone="neutral"){
  if(!draftStatus)return;
  draftStatus.hidden=!message;
  draftStatus.textContent=message||"";
  draftStatus.dataset.tone=tone;
}

function discardDraftErrorMessage(error){
  const text=String(error?.message||error?.details||"");
  if(text.includes("workflow_draft_conflict"))return "Este borrador cambió en otra sesión. Recarga antes de eliminarlo.";
  if(text.includes("workflow_draft_discard_forbidden"))return "No tienes permiso para eliminar este borrador.";
  if(text.includes("workflow_draft_discard_requires_unpublished"))return "Este flujo ya fue publicado y no puede eliminarse como borrador.";
  if(text.includes("workflow_draft_has_dependencies"))return "Este borrador tiene dependencias operativas y no se puede eliminar.";
  if(text.includes("workflow_revision_draft_not_found")||text.includes("workflow_definition_not_found"))return "El borrador ya no existe o fue modificado. Recarga la lista.";
  return "No se pudo eliminar el borrador. No se modificó ninguna versión publicada.";
}

async function discardDraft(item,button){
  const revision=Number(item.revision);
  const isRevision=Boolean(item.is_revision);
  const message=isRevision
    ?"¿Eliminar este borrador de la nueva versión? La v"+item.base_version+" publicada seguirá operativa y no se modificará."
    :"¿Eliminar definitivamente este borrador? Todavía no ha sido publicado y desaparecerá del Creador.";
  if(!window.confirm(message))return;

  const original=button.textContent;
  button.disabled=true;
  button.textContent="Eliminando…";
  setDraftStatus(isRevision
    ?"Eliminando solo el borrador de la nueva versión…"
    :"Eliminando borrador no publicado…");

  const rpc=isRevision
    ?"discard_workflow_definition_revision_draft_v1"
    :"discard_workflow_definition_draft_v1";
  const {error}=await supabase.rpc(rpc,{
    p_definition_id:item.definition_id,
    p_expected_revision:Number.isFinite(revision)?revision:null
  });

  if(error){
    button.disabled=false;
    button.textContent=original;
    setDraftStatus(discardDraftErrorMessage(error),"error");
    return;
  }

  draftItems=draftItems.filter(candidate=>!(
    candidate.definition_id===item.definition_id
    && Boolean(candidate.is_revision)===isRevision
  ));
  renderDraftWorkspace();
  setDraftStatus(
    isRevision
      ?"Borrador de nueva versión eliminado. La versión publicada permanece intacta."
      :"Borrador eliminado.",
    "success"
  );
}

function draftWorkspaceCard(item){
  const article=document.createElement("article");
  article.className="builder-draft-card";

  const head=document.createElement("div");head.className="builder-draft-head";
  const title=document.createElement("h3");title.textContent=item.name||"Borrador";
  const badge=document.createElement("span");badge.className="builder-draft-badge "+(item.authoring_complete?"is-complete":"is-pending");
  badge.textContent=item.authoring_complete?"Listo para continuar":"Incompleto";
  head.append(title,badge);

  const meta=document.createElement("div");meta.className="builder-draft-meta";
  const versionText=item.is_revision
    ?"Nueva v"+(Number(item.base_version)+1)+" · basada en v"+item.base_version
    :"Primera publicación";
  meta.textContent=versionText+" · revisión "+item.revision+" · "+draftDate(item.updated_at);

  const actions=document.createElement("div");actions.className="builder-draft-actions";
  const edit=document.createElement("a");edit.className="builder-action builder-action--primary";
  edit.href="./workflow-builder.html?id="+encodeURIComponent(item.definition_id)+(item.is_revision?"&revision=1":"");
  edit.textContent="Editar";

  const discard=document.createElement("button");
  discard.type="button";
  discard.className="builder-action builder-action--danger";
  discard.textContent="Eliminar borrador";
  discard.addEventListener("click",()=>discardDraft(item,discard));

  actions.append(edit,discard);

  article.append(head,meta,actions);
  return article;
}

function filteredDraftItems(){
  const term=String(draftSearch?.value||"").trim().toLocaleLowerCase("es");
  const filter=String(draftFilter?.value||"all");
  return draftItems.filter(item=>{
    const matchesTerm=!term||String(item.name||"").toLocaleLowerCase("es").includes(term);
    const matchesFilter=
      filter==="all"
      ||(filter==="ready"&&item.authoring_complete)
      ||(filter==="incomplete"&&!item.authoring_complete)
      ||(filter==="revision"&&item.is_revision);
    return matchesTerm&&matchesFilter;
  });
}

function renderDraftWorkspace(){
  if(!draftsList)return;
  const filtered=filteredDraftItems();
  const visible=filtered.slice(0,draftVisibleLimit);
  draftsList.replaceChildren();

  if(draftCount){
    draftCount.textContent=filtered.length+" borrador"+(filtered.length===1?"":"es");
  }

  if(!visible.length){
    const empty=document.createElement("article");empty.className="builder-draft-card";
    empty.textContent=draftItems.length
      ?"No hay borradores que coincidan con este filtro."
      :"No hay borradores guardados. Puedes crear un flujo nuevo.";
    draftsList.append(empty);
  }else{
    visible.forEach(item=>draftsList.append(draftWorkspaceCard(item)));
  }

  if(draftLoadMore){
    draftLoadMore.hidden=visible.length>=filtered.length;
    if(!draftLoadMore.hidden){
      draftLoadMore.textContent="Cargar más · "+(filtered.length-visible.length)+" pendientes";
    }
  }
}

async function loadDraftWorkspace(){
  if(!draftsList)return;
  const [initialResult,revisionResult]=await Promise.all([
    supabase
      .from("workflow_definitions_v2")
      .select("id,name,revision,authoring_complete,updated_at")
      .eq("status","draft")
      .order("updated_at",{ascending:false}),
    supabase
      .from("workflow_definition_revision_drafts_v2")
      .select("definition_id,base_version,revision,draft_spec,authoring_complete,updated_at,published_at")
      .is("published_at",null)
      .order("updated_at",{ascending:false})
  ]);

  if(initialResult.error||revisionResult.error){
    draftsList.replaceChildren();
    const error=document.createElement("article");error.className="builder-draft-card";
    error.textContent="No se pudieron cargar los borradores autorizados.";
    draftsList.append(error);
    if(draftCount)draftCount.textContent="Error al cargar";
    return;
  }

  draftItems=[
    ...(initialResult.data||[]).map(row=>({
      definition_id:row.id,
      name:row.name,
      revision:row.revision,
      authoring_complete:row.authoring_complete,
      updated_at:row.updated_at,
      is_revision:false
    })),
    ...(revisionResult.data||[]).map(row=>({
      definition_id:row.definition_id,
      name:String(row.draft_spec?.flowName||"Nueva versión"),
      base_version:row.base_version,
      revision:row.revision,
      authoring_complete:row.authoring_complete,
      updated_at:row.updated_at,
      is_revision:true
    }))
  ].sort((a,b)=>new Date(b.updated_at)-new Date(a.updated_at));

  draftVisibleLimit=12;
  renderDraftWorkspace();
}

publishButton?.addEventListener("click",publishCurrentDraft);
addChecklistItemButton?.addEventListener("click",()=>{
  addChecklistItem({text:"",required:true},{focus:true});
  notifyChecklistChanged();
});

form.addEventListener("input",()=>{
  saveLocalDraft();
  updateCompletionUI();
  if(currentStep===panels.length-1)renderSummary();
});
form.addEventListener("change",event=>{
  if(event.target===triggerType||event.target===field("recurrence"))updateTriggerFields({clearHidden:true});
  if(event.target===field("stepChecklist"))updateChecklistEditor();
  saveLocalDraft();
  updateCompletionUI();
  if(currentStep===panels.length-1)renderSummary();
});
backButton.addEventListener("click",()=>showStep(currentStep-1,true));
nextButton.addEventListener("click",()=>showStep(currentStep+1,true));
stepButtons.forEach((button,index)=>button.addEventListener("click",()=>showStep(index,true)));
saveButton.addEventListener("click",saveServerDraft);

async function saveAndExit(){
  const saved=await saveServerDraft();
  if(saved)goToDrafts();
}
saveExitButton?.addEventListener("click",saveAndExit);
exitEditorButton?.addEventListener("click",requestExitEditor);

exitSaveButton?.addEventListener("click",async()=>{
  exitSaveButton.disabled=true;
  const saved=await saveServerDraft();
  exitSaveButton.disabled=false;
  if(saved){
    exitDialog?.close();
    goToDrafts();
  }
});
exitDiscardButton?.addEventListener("click",()=>{
  clearLocalDraftCache();
  exitDialog?.close();
  goToDrafts();
});
exitCancelButton?.addEventListener("click",()=>exitDialog?.close());

draftSearch?.addEventListener("input",()=>{
  draftVisibleLimit=12;
  renderDraftWorkspace();
});
draftFilter?.addEventListener("change",()=>{
  draftVisibleLimit=12;
  renderDraftWorkspace();
});
draftLoadMore?.addEventListener("click",()=>{
  draftVisibleLimit+=12;
  renderDraftWorkspace();
});

clearButton.addEventListener("click",async()=>{
  const message=currentDefinitionId
    ?"¿Descartar los cambios sin guardar y recuperar la última versión guardada del borrador?"
    :"¿Borrar los cambios locales de este flujo nuevo?";
  if(!window.confirm(message))return;

  clearLocalDraftCache();
  if(currentDefinitionId){
    await loadServerDraft();
    setServerStatus("Cambios locales descartados. Se restauró la última revisión guardada.","success");
    return;
  }

  form.reset();
  renderChecklistItems([]);
  currentStep=0;
  legacyDraftNeedsReview=false;
  updateTriggerFields();
  showStep(0,true);
  markSavedSnapshot();
  setServerStatus("Cambios locales eliminados. El flujo nuevo vuelve a estar vacío.");
});

window.addEventListener("beforeunload",event=>{
  if(allowNavigation||!hasUnsavedChanges())return;
  event.preventDefault();
  event.returnValue="";
});

(async()=>{
  showWorkspaceView();

  if(!editorRequested){
    await loadDraftWorkspace();
    return;
  }

  if(currentDefinitionId){
    await loadServerDraft();
    return;
  }

  form.reset();
  renderChecklistItems([]);
  markSavedSnapshot();
  restoreLocalDraft();
  updateTriggerFields();
  showStep(currentStep);
  const state=completion();
  setServerStatus("Nuevo flujo · "+state.completed+"/"+state.total+" apartados completos.");
})();
