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
const targetNote=document.getElementById("applicationTargetNote");
const createButton=document.getElementById("applicationCreate");
const applicationsList=document.getElementById("workflowApplications");
const status=document.getElementById("applicationsStatus");

const definitionId=new URLSearchParams(window.location.search).get("definition")||"";
let definition=null;
let versions=[];
let properties=[];
let rooms=[];
let occupancies=[];
let applications=[];

const scopeLabels={organization:"Toda la organización",property:"Un piso",room:"Una habitación",occupancy:"Una ocupación / inquilino"};

function setStatus(message,error=false){
  const span=status?.querySelector("span:last-child");
  if(span)span.textContent=message;
  status?.classList.toggle("error",error);
}
function option(value,label){const node=document.createElement("option");node.value=value;node.textContent=label;return node}
function fmtDate(value){if(!value)return "—";try{return new Intl.DateTimeFormat("es-ES",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value))}catch{return value}}
function activeVersion(){return versions.find(item=>item.id===versionSelect.value)||versions[0]||null}
function versionScope(){return String(activeVersion()?.spec?.scopeType||definition?.scope_type||"")}
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
  if(message.includes("workflow_application_version_conflict"))return "Este flujo ya está aplicado a ese destino con otra versión. Archiva primero la aplicación existente.";
  if(message.includes("workflow_application_not_authorized"))return "Tu sesión no tiene autorización para aplicar este flujo.";
  return "No se pudo guardar la aplicación. No se ha modificado ningún dato.";
}
function meta(label,value){
  const box=document.createElement("div");box.className="application-meta-item";
  const strong=document.createElement("strong");strong.textContent=label;
  const span=document.createElement("span");span.textContent=value||"—";
  box.append(strong,span);return box;
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

async function updateTargetControls(){
  const scope=versionScope();
  scopeText.textContent=scopeLabels[scope]||"—";
  propertyRow.hidden=!["property","room","occupancy"].includes(scope);
  roomRow.hidden=scope!=="room";
  occupancyRow.hidden=scope!=="occupancy";
  propertySelect.required=["property","room","occupancy"].includes(scope);
  roomSelect.required=scope==="room";
  occupancySelect.required=scope==="occupancy";
  roomSelect.disabled=scope!=="room"||!propertySelect.value;
  occupancySelect.disabled=scope!=="occupancy"||!propertySelect.value;

  if(scope==="organization"){
    targetNote.textContent="Esta versión se aplicará a toda la organización. No requiere otro selector.";
    createButton.disabled=false;
    return;
  }

  const available=properties.filter(item=>item.status!=="archived"&&!item.archived_at);
  if(!available.length){
    targetNote.textContent="No hay pisos disponibles en Cartera. Crea primero un piso real para poder aplicar esta receta.";
    createButton.disabled=true;
    return;
  }

  createButton.disabled=false;
  targetNote.textContent=scope==="room"
    ?"Selecciona primero el piso y después una habitación perteneciente a ese piso."
    :scope==="occupancy"
      ?"Selecciona primero el piso y después una ocupación vigente."
      :"Selecciona el piso concreto donde quieres aplicar esta versión.";
}

function renderDefinition(){
  definitionBox.classList.remove("application-card--loading");
  const head=document.createElement("div");
  const eyebrow=document.createElement("p");eyebrow.className="eyebrow";eyebrow.textContent="Receta publicada";
  const title=document.createElement("h2");title.textContent=definition.name;
  head.append(eyebrow,title);
  const info=document.createElement("div");info.className="application-meta";
  info.append(
    meta("Estado",definition.status==="published"?"Publicado":definition.status),
    meta("Ámbito lógico",scopeLabels[definition.scope_type]||definition.scope_type),
    meta("Versiones",String(versions.length)),
    meta("Última publicación",fmtDate(versions[0]?.published_at))
  );
  definitionBox.replaceChildren(head,info);
}

function renderApplications(){
  applicationsList.replaceChildren();
  if(!applications.length){
    const empty=document.createElement("article");empty.className="application-empty";
    empty.textContent="Todavía no hay aplicaciones para esta definición.";
    applicationsList.append(empty);return;
  }
  applications.forEach(app=>{
    const article=document.createElement("article");article.className="application-card";
    const head=document.createElement("div");head.className="application-item-head";
    const title=document.createElement("h3");title.textContent=targetLabel(app);
    const badge=document.createElement("span");badge.className="application-badge application-badge--"+app.status;badge.textContent=app.status==="configured"?"Configurada":"Archivada";
    head.append(title,badge);
    const details=document.createElement("div");details.className="application-meta";
    const version=versions.find(item=>item.id===app.definition_version_id);
    details.append(
      meta("Ámbito",scopeLabels[app.scope_type]||app.scope_type),
      meta("Versión","v"+(version?.version||"?")),
      meta("Creada",fmtDate(app.created_at)),
      meta("Estado",app.status==="configured"?"Sin ejecución todavía":"Archivada")
    );
    article.append(head,details);
    if(app.status==="configured"){
      const actions=document.createElement("div");actions.className="application-actions";
      const archive=document.createElement("button");archive.type="button";archive.className="danger-soft";archive.textContent="Archivar aplicación";
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

async function archiveApplication(app){
  if(!window.confirm("¿Archivar esta aplicación? La receta y su historial no se eliminarán."))return;
  setStatus("Archivando aplicación…");
  const {error}=await supabase.rpc("archive_workflow_application_v1",{p_application_id:app.id});
  if(error){setStatus(errorText(error),true);return}
  setStatus("Aplicación archivada. La definición publicada permanece intacta.");
  await loadApplications();
}

propertySelect.addEventListener("change",async()=>{
  const scope=versionScope();
  try{
    if(scope==="room")await loadRoomsFor(propertySelect.value);
    if(scope==="occupancy")await loadOccupanciesFor(propertySelect.value);
    roomSelect.disabled=scope!=="room"||!propertySelect.value;
    occupancySelect.disabled=scope!=="occupancy"||!propertySelect.value;
  }catch{setStatus("No se pudieron cargar los destinos dependientes.",true)}
});

versionSelect.addEventListener("change",async()=>{
  propertySelect.value="";
  roomSelect.replaceChildren(option("","Selecciona una habitación"));
  occupancySelect.replaceChildren(option("","Selecciona una ocupación vigente"));
  await updateTargetControls();
});

form.addEventListener("submit",async event=>{
  event.preventDefault();
  const version=activeVersion();
  if(!version)return;
  const scope=versionScope();
  const args={
    p_definition_version_id:version.id,
    p_property_id:["property","room","occupancy"].includes(scope)?propertySelect.value||null:null,
    p_room_id:scope==="room"?roomSelect.value||null:null,
    p_occupancy_id:scope==="occupancy"?occupancySelect.value||null:null
  };
  createButton.disabled=true;
  createButton.textContent="Guardando…";
  setStatus("Validando el destino en servidor…");
  const {error}=await supabase.rpc("create_workflow_application_v1",args);
  createButton.textContent="Crear aplicación";
  if(error){
    createButton.disabled=false;
    setStatus(errorText(error),true);
    return;
  }
  setStatus("Aplicación configurada. Todavía no crea tareas ni recurrencias.");
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
    setStatus("Abre Aplicaciones desde Mis Flujos.",true);
    return;
  }

  const {data:userData,error:userError}=await supabase.auth.getUser();
  if(userError||!userData?.user){setStatus("No se pudo validar la sesión.",true);return}
  const role=String(userData.user.app_metadata?.role||"").toLowerCase();
  if(!["root","admin"].includes(role)){
    setStatus("Las aplicaciones de flujo requieren acceso administrativo.",true);
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
  await loadProperties();
  const available=properties.filter(item=>item.status!=="archived"&&!item.archived_at);
  propertySelect.replaceChildren(option("","Selecciona un piso"),...available.map(item=>option(item.id,item.name+(item.address_line?" · "+item.address_line:""))));

  renderDefinition();
  formCard.hidden=false;
  await updateTargetControls();
  await loadApplications();
  setStatus("Aplicaciones cargadas. Configurada no significa activa: la ejecución todavía está bloqueada.");
}

load().catch(()=>setStatus("No se pudieron cargar las aplicaciones del flujo.",true));
