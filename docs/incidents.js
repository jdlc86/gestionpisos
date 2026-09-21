import { supabase } from "./supabase-client.js";

const openToggle=document.getElementById("incidentOpenToggle");
const openPanel=document.getElementById("incidentOpenPanel");
const openClose=document.getElementById("incidentOpenClose");
const openCancel=document.getElementById("incidentOpenCancel");
const openForm=document.getElementById("incidentOpenForm");
const openSubmit=document.getElementById("incidentOpenSubmit");
const propertySelect=document.getElementById("incidentProperty");
const roomSelect=document.getElementById("incidentRoom");
const filter=document.getElementById("incidentFilter");
const list=document.getElementById("incidentList");
const statusBox=document.getElementById("incidentStatus");

let currentUser=null;
let incidents=[];
let properties=new Map();
let rooms=[];
let updatesByIncident=new Map();

const terminalStatuses=new Set(["resolved","closed","rejected"]);
const statusLabels={
  reported:"Reportada",triaged:"Clasificada",assigned:"Asignada",
  in_progress:"En gestión",waiting_info:"Esperando información",
  resolved:"Resuelta",closed:"Cerrada",rejected:"Rechazada",reopened:"Reabierta"
};
const kindLabels={incident:"Incidencia",maintenance:"Mantenimiento"};
const priorityLabels={low:"Baja",normal:"Normal",high:"Alta",urgent:"Urgente"};
const updateLabels={
  request_info:"Información solicitada",information_response:"Respuesta enviada",
  resolution:"Resolución",rejection:"Rechazo",legacy:"Actualización"
};

function setStatus(message,error=false){
  const text=statusBox?.querySelector("span:last-child");
  if(text)text.textContent=message;
  statusBox?.classList.toggle("error",error);
}
function fmtDate(value){
  if(!value)return "—";
  try{return new Intl.DateTimeFormat("es-ES",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value))}catch{return String(value)}
}
function randomKey(prefix){
  return prefix+(globalThis.crypto?.randomUUID?.()||Date.now()+"-"+Math.random().toString(36).slice(2));
}
function errorText(error){
  const message=String(error?.message||"");
  if(message.includes("incident_open_forbidden"))return "No tienes autorización vigente para abrir una incidencia en ese piso.";
  if(message.includes("incident_destination_invalid"))return "El piso o la habitación ya no son un destino válido.";
  if(message.includes("incident_request_key_conflict"))return "El reintento pertenece a otro reporte. Revisa los datos y vuelve a intentarlo.";
  if(message.includes("incident_not_waiting_information"))return "El expediente ya no está esperando información.";
  if(message.includes("incident_information_forbidden"))return "Solo quien abrió este expediente puede responder a la solicitud.";
  if(message.includes("not_authenticated"))return "La sesión ya no es válida. Vuelve a iniciar sesión.";
  return "No se pudo completar la operación. No se ha aplicado ningún cambio parcial.";
}
function setOpenPanel(open){
  openPanel.hidden=!open;
  openToggle.setAttribute("aria-expanded",String(open));
  if(open)openPanel.scrollIntoView({behavior:"smooth",block:"start"});
}
function syncRooms(){
  const propertyId=propertySelect.value;
  const selected=roomSelect.value;
  const options=[new Option("Todo el piso","")];
  rooms.filter(room=>room.property_id===propertyId).forEach(room=>{
    options.push(new Option(room.label||"Habitación",room.id));
  });
  roomSelect.replaceChildren(...options);
  if(options.some(option=>option.value===selected))roomSelect.value=selected;
}
function syncPropertyOptions(){
  const selected=propertySelect.value;
  propertySelect.replaceChildren(new Option("Selecciona un piso",""),
    ...[...properties.values()]
      .sort((a,b)=>String(a.name||a.address_line||"").localeCompare(String(b.name||b.address_line||""),"es"))
      .map(property=>new Option(property.name||property.address_line||"Piso",property.id))
  );
  if(properties.has(selected))propertySelect.value=selected;
  syncRooms();
  openSubmit.disabled=properties.size===0;
}
function meta(label,value){
  const box=document.createElement("div");box.className="incident-meta-item";
  const strong=document.createElement("strong");strong.textContent=label;
  const span=document.createElement("span");span.textContent=value||"—";
  box.append(strong,span);return box;
}
function visibleIncidents(){
  if(filter.value==="all")return incidents;
  if(filter.value==="waiting_info")return incidents.filter(row=>row.status==="waiting_info");
  if(filter.value==="resolved")return incidents.filter(row=>terminalStatuses.has(row.status));
  return incidents.filter(row=>!terminalStatuses.has(row.status));
}
function renderUpdates(incident,card){
  const rows=updatesByIncident.get(incident.id)||[];
  if(!rows.length)return;
  const box=document.createElement("section");box.className="incident-updates";
  rows.slice(-5).forEach(row=>{
    const item=document.createElement("div");item.className="incident-update";
    const strong=document.createElement("strong");strong.textContent=updateLabels[row.update_kind]||"Actualización";
    const body=document.createElement("span");body.textContent=row.body;
    const small=document.createElement("small");small.textContent=fmtDate(row.created_at);
    item.append(strong,body,small);box.append(item);
  });
  card.append(box);
}
function renderResponse(incident,card){
  if(incident.status!=="waiting_info"||incident.created_by!==currentUser?.id)return;
  const section=document.createElement("section");section.className="incident-response";
  const label=document.createElement("label");label.textContent="Responder a la solicitud";
  const textarea=document.createElement("textarea");textarea.rows=3;textarea.maxLength=5000;textarea.placeholder="Añade la información solicitada";
  label.append(textarea);
  const actions=document.createElement("div");actions.className="incident-response-actions";
  const button=document.createElement("button");button.type="button";button.className="primary";button.textContent="Enviar información";
  button.addEventListener("click",async()=>{
    const body=textarea.value.trim();
    if(!body){setStatus("Escribe la información antes de enviarla.",true);textarea.focus();return}
    const storageKey="incident-response:"+incident.id+":"+body;
    let requestKey=sessionStorage.getItem(storageKey);
    if(!requestKey){requestKey=randomKey("incident-info-");sessionStorage.setItem(storageKey,requestKey)}
    button.disabled=true;button.textContent="Enviando…";
    const {data,error}=await supabase.rpc("submit_incident_information_v1",{
      p_incident_id:incident.id,p_request_key:requestKey,p_body:body
    });
    button.disabled=false;button.textContent="Enviar información";
    if(error){setStatus(errorText(error),true);return}
    sessionStorage.removeItem(storageKey);
    const result=Array.isArray(data)?data[0]:null;
    setStatus(result?.applied_new===false?"La respuesta ya estaba registrada; no se duplicó.":"Información enviada. La misma gestión podrá continuar.");
    await loadIncidents();
  });
  actions.append(button);section.append(label,actions);card.append(section);
}
function render(){
  list.replaceChildren();
  const rows=visibleIncidents();
  if(!rows.length){
    const empty=document.createElement("article");empty.className="incident-empty";
    empty.textContent="No hay expedientes visibles en este filtro.";list.append(empty);return;
  }
  rows.forEach(incident=>{
    const card=document.createElement("article");card.className="incident-card";
    const head=document.createElement("div");head.className="incident-card-head";
    const titleBox=document.createElement("div");
    const eyebrow=document.createElement("p");eyebrow.className="eyebrow";eyebrow.textContent=kindLabels[incident.incident_kind]||"Incidencia";
    const title=document.createElement("h3");title.textContent=incident.category;
    titleBox.append(eyebrow,title);
    const badges=document.createElement("div");badges.className="incident-badges";
    const state=document.createElement("span");state.className="incident-badge";state.textContent=statusLabels[incident.status]||incident.status;
    const priority=document.createElement("span");priority.className="incident-badge"+(incident.priority==="urgent"?" incident-badge--urgent":"");priority.textContent=priorityLabels[incident.priority]||incident.priority;
    badges.append(state,priority);head.append(titleBox,badges);card.append(head);
    const description=document.createElement("p");description.className="incident-description";description.textContent=incident.description;card.append(description);
    const property=properties.get(incident.property_id);
    const room=rooms.find(item=>item.id===incident.room_id);
    const details=document.createElement("div");details.className="incident-meta";
    details.append(
      meta("Piso",property?.name||property?.address_line||"Piso"),
      meta("Ubicación",room?.label||"Todo el piso"),
      meta("Creada",fmtDate(incident.created_at)),
      meta("Actualizada",fmtDate(incident.updated_at))
    );
    card.append(details);renderUpdates(incident,card);renderResponse(incident,card);list.append(card);
  });
}
async function loadScope(){
  const [propertyResult,roomResult]=await Promise.all([
    supabase.from("properties_v2").select("id,organization_id,name,address_line,status,archived_at").eq("status","active").is("archived_at",null),
    supabase.from("rooms_v2").select("id,property_id,label,status,archived_at").eq("status","active").is("archived_at",null)
  ]);
  if(propertyResult.error||roomResult.error)throw propertyResult.error||roomResult.error;
  properties=new Map((propertyResult.data||[]).map(row=>[row.id,row]));
  rooms=roomResult.data||[];syncPropertyOptions();
}
async function loadIncidents(){
  const {data,error}=await supabase.from("incidents_v2")
    .select("id,organization_id,property_id,room_id,created_by,assigned_to,category,description,priority,status,rejection_reason,resolved_at,created_at,updated_at,incident_kind,opened_occupancy_id")
    .order("created_at",{ascending:false}).limit(100);
  if(error)throw error;
  incidents=data||[];updatesByIncident=new Map();
  const ids=incidents.map(row=>row.id);
  if(ids.length){
    const {data:updateRows,error:updateError}=await supabase.from("incident_updates_v2")
      .select("id,incident_id,author_user_id,visibility,body,update_kind,created_at")
      .in("incident_id",ids).order("created_at");
    if(updateError)throw updateError;
    (updateRows||[]).forEach(row=>{
      const bucket=updatesByIncident.get(row.incident_id)||[];bucket.push(row);updatesByIncident.set(row.incident_id,bucket);
    });
  }
  render();
  setStatus(incidents.length
    ?incidents.length+" expediente"+(incidents.length===1?"":"s")+" visible"+(incidents.length===1?"":"s")+" según tus permisos."
    :"No hay incidencias visibles todavía.");
}

openForm.addEventListener("submit",async event=>{
  event.preventDefault();
  const values=new FormData(openForm);
  const payload={
    propertyId:String(values.get("propertyId")||""),roomId:String(values.get("roomId")||"")||null,
    incidentKind:String(values.get("incidentKind")||""),category:String(values.get("category")||"").trim(),
    description:String(values.get("description")||"").trim(),priority:String(values.get("priority")||"")
  };
  if(!payload.propertyId||!payload.category||!payload.description){setStatus("Completa los campos obligatorios.",true);return}
  const fingerprint=JSON.stringify(payload);
  const storageKey="incident-open:"+fingerprint;
  let requestKey=sessionStorage.getItem(storageKey);
  if(!requestKey){requestKey=randomKey("incident-open-");sessionStorage.setItem(storageKey,requestKey)}
  openSubmit.disabled=true;openSubmit.textContent="Creando…";setStatus("Creando el expediente y publicando su evento de workflow…");
  const {data,error}=await supabase.rpc("open_workflow_incident_v1",{
    p_property_id:payload.propertyId,p_room_id:payload.roomId,p_incident_kind:payload.incidentKind,
    p_category:payload.category,p_description:payload.description,p_priority:payload.priority,p_request_key:requestKey
  });
  openSubmit.disabled=false;openSubmit.textContent="Crear reporte";
  if(error){setStatus(errorText(error),true);return}
  sessionStorage.removeItem(storageKey);
  const result=Array.isArray(data)?data[0]:null;
  setStatus(result?.created_new===false?"El reporte ya existía; se recuperó sin duplicarlo.":"Reporte creado. La gestión se asignará mediante el workflow configurado.");
  openForm.reset();syncRooms();setOpenPanel(false);await loadIncidents();
});

openToggle.addEventListener("click",()=>setOpenPanel(openPanel.hidden));
openClose.addEventListener("click",()=>setOpenPanel(false));
openCancel.addEventListener("click",()=>setOpenPanel(false));
propertySelect.addEventListener("change",syncRooms);
filter.addEventListener("change",render);

async function init(){
  const {data,error}=await supabase.auth.getUser();
  if(error||!data?.user){setStatus("No se pudo validar la sesión.",true);return}
  currentUser=data.user;
  try{await loadScope();await loadIncidents()}catch(loadError){list.replaceChildren();setStatus(errorText(loadError),true)}
}
init();
