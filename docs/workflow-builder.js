const DRAFT_KEY="gestionpisos.workflow-builder.draft.v1";
const form=document.getElementById("workflowBuilderForm");
const panels=[...document.querySelectorAll(".builder-panel")];
const stepButtons=[...document.querySelectorAll(".builder-step")];
const backButton=document.getElementById("builderBack");
const nextButton=document.getElementById("builderNext");
const clearButton=document.getElementById("builderClear");
const triggerType=document.getElementById("triggerType");
const recurrenceRow=document.getElementById("recurrenceRow");
const summary=document.getElementById("workflowSummary");
let currentStep=0;

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
function label(group,key){return labels[group]?.[key]||key||"—"}

function draft(){
  return {
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

function saveDraft(){
  try{sessionStorage.setItem(DRAFT_KEY,JSON.stringify(draft()))}catch{}
}

function setChecked(name,next){const node=field(name);if(node)node.checked=Boolean(next)}
function restoreDraft(){
  let saved=null;
  try{saved=JSON.parse(sessionStorage.getItem(DRAFT_KEY)||"null")}catch{}
  if(!saved||typeof saved!=="object")return;
  for(const name of ["flowName","flowType","flowDescription","scopeType","triggerType","recurrence","assignmentType","closeType"]){
    const node=field(name);if(node&&typeof saved[name]==="string")node.value=saved[name];
  }
  setChecked("stepAccept",saved.steps?.accept);
  setChecked("stepPhoto",saved.steps?.photo);
  setChecked("stepChecklist",saved.steps?.checklist);
  setChecked("stepDocument",saved.steps?.document);
  setChecked("notifyOnCreate",saved.notifications?.onCreate);
  setChecked("notifyOnClose",saved.notifications?.onClose);
  if(Number.isInteger(saved.currentStep))currentStep=Math.max(0,Math.min(panels.length-1,saved.currentStep));
}

function updateTriggerFields(){recurrenceRow.hidden=triggerType.value!=="recurring"}

function validateCurrentStep(){
  if(currentStep!==0)return true;
  const name=field("flowName");
  if(name&&name.value.trim()===""){
    name.setCustomValidity("Escribe un nombre para identificar el flujo.");
    name.reportValidity();
    name.setCustomValidity("");
    return false;
  }
  return true;
}

function summaryRow(title,text){
  const row=document.createElement("div");row.className="builder-summary-row";
  const strong=document.createElement("strong");strong.textContent=title;
  const span=document.createElement("span");span.textContent=text||"—";
  row.append(strong,span);return row;
}

function renderSummary(){
  if(!summary)return;
  const data=draft();
  const stepNames=[];
  if(data.steps.accept)stepNames.push("Confirmar / aceptar");
  if(data.steps.photo)stepNames.push("Evidencia fotográfica");
  if(data.steps.checklist)stepNames.push("Checklist / formulario");
  if(data.steps.document)stepNames.push("Documento");
  const notificationNames=[];
  if(data.notifications.onCreate)notificationNames.push("al crear tarea");
  if(data.notifications.onClose)notificationNames.push("al cerrar flujo");
  summary.replaceChildren(
    summaryRow("Nombre",data.flowName||"Sin nombre"),
    summaryRow("Tipo",label("flowType",data.flowType)),
    summaryRow("Ámbito",label("scopeType",data.scopeType)),
    summaryRow("Activación",data.triggerType==="recurring"?`${label("triggerType",data.triggerType)} · ${label("recurrence",data.recurrence)}`:label("triggerType",data.triggerType)),
    summaryRow("Asignación",label("assignmentType",data.assignmentType)),
    summaryRow("Pasos",stepNames.length?stepNames.join(" → "):"Sin pasos seleccionados"),
    summaryRow("Cierre",label("closeType",data.closeType)),
    summaryRow("Notificaciones",notificationNames.length?notificationNames.join(" y "):"Sin notificaciones"),
    summaryRow("Descripción",data.flowDescription||"Sin descripción")
  );
}

function showStep(next){
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
    renderSummary();
  }else{
    nextButton.textContent="Continuar";
    nextButton.disabled=false;
  }
  saveDraft();
  document.querySelector(".builder-card")?.scrollIntoView({block:"start",behavior:"smooth"});
}

form.addEventListener("input",saveDraft);
form.addEventListener("change",()=>{updateTriggerFields();saveDraft();if(currentStep===panels.length-1)renderSummary()});
triggerType.addEventListener("change",updateTriggerFields);
backButton.addEventListener("click",()=>showStep(currentStep-1));
nextButton.addEventListener("click",()=>{if(validateCurrentStep())showStep(currentStep+1)});
stepButtons.forEach((button,index)=>button.addEventListener("click",()=>{if(index<=currentStep||validateCurrentStep())showStep(index)}));
clearButton.addEventListener("click",()=>{
  if(!window.confirm("¿Borrar el borrador local de este flujo?"))return;
  try{sessionStorage.removeItem(DRAFT_KEY)}catch{}
  form.reset();currentStep=0;updateTriggerFields();showStep(0);
});

restoreDraft();
updateTriggerFields();
showStep(currentStep);
