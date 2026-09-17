import { supabase } from "./supabase-client.js";

const list=document.getElementById("workflowDefinitions");
const status=document.getElementById("definitionsStatus");

const labels={
  flowType:{cleaning:"Limpieza",inspection:"Inspección",maintenance:"Mantenimiento",checkin:"Check-in",checkout:"Check-out",custom:"Personalizado"},
  scopeType:{property:"Un piso",organization:"Toda la organización",room:"Una habitación",occupancy:"Una ocupación / inquilino"},
  triggerType:{manual:"Manual",recurring:"Recurrente",scheduled_once:"Fecha concreta",event:"Por evento"},
  assignmentType:{property_responsible:"Responsable operativo del piso",active_occupants_rotation:"Ocupantes activos en rotación",fixed_person:"Persona fija",role:"Rol o capacidad",manual:"Se decide al iniciar"},
  status:{draft:"Borrador",published:"Publicado",paused:"Pausado",archived:"Archivado"}
};

function text(group,key){return labels[group]?.[key]||key||"—"}
function setStatus(message,error=false){
  const span=status?.querySelector("span:last-child");
  if(span)span.textContent=message;
  status?.classList.toggle("error",error);
}
function dateTime(value){
  if(!value)return "—";
  try{return new Intl.DateTimeFormat("es-ES",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value))}catch{return value}
}
function meta(label,value){
  const box=document.createElement("div");box.className="definition-meta-item";
  const strong=document.createElement("strong");strong.textContent=label;
  const span=document.createElement("span");span.textContent=value||"—";
  box.append(strong,span);return box;
}
function card(row){
  const article=document.createElement("article");article.className="definition-card";
  const head=document.createElement("div");head.className="definition-card-head";
  const title=document.createElement("h3");title.textContent=row.name;
  const badge=document.createElement("span");badge.className="definition-badge";badge.textContent=text("status",row.status);
  head.append(title,badge);

  const details=document.createElement("div");details.className="definition-meta";
  details.append(
    meta("Tipo",text("flowType",row.flow_type)),
    meta("Ámbito",text("scopeType",row.scope_type)),
    meta("Activación",text("triggerType",row.trigger_type)),
    meta("Asignación",text("assignmentType",row.assignment_type)),
    meta("Revisión",String(row.revision||1)),
    meta("Último cambio",dateTime(row.updated_at))
  );

  const actions=document.createElement("div");actions.className="definition-actions";
  if(row.status==="draft"){
    const edit=document.createElement("a");
    edit.className="secondary";
    edit.href=`./workflow-builder.html?id=${encodeURIComponent(row.id)}`;
    edit.textContent="Editar borrador";
    actions.append(edit);
  }
  article.append(head,details,actions);
  return article;
}
function emptyState(){
  const article=document.createElement("article");article.className="definitions-empty";
  const h=document.createElement("h3");h.textContent="Todavía no hay flujos guardados";
  const p=document.createElement("p");p.textContent="Crea el primer borrador desde el Creador de Flujos.";
  const link=document.createElement("a");link.className="primary definitions-create";link.href="./workflow-builder.html";link.textContent="➕ Crear flujo";
  article.append(h,p,link);return article;
}

async function load(){
  const {data:userData,error:userError}=await supabase.auth.getUser();
  if(userError||!userData?.user){
    list.replaceChildren();
    setStatus("No se pudo validar la sesión.",true);
    return;
  }

  const role=String(userData.user.app_metadata?.role||"").toLowerCase();
  if(!["root","admin"].includes(role)){
    list.replaceChildren();
    const article=document.createElement("article");article.className="definitions-empty";
    const h=document.createElement("h3");h.textContent="Acceso administrativo";
    const p=document.createElement("p");p.textContent="Las definiciones de flujo solo pueden consultarlas ROOT o ADMIN autorizados.";
    article.append(h,p);list.append(article);
    setStatus("RLS mantiene las definiciones fuera del ámbito de otros roles.");
    return;
  }

  const {data,error}=await supabase
    .from("workflow_definitions_v2")
    .select("id,name,flow_type,scope_type,trigger_type,assignment_type,status,revision,updated_at")
    .neq("status","archived")
    .order("updated_at",{ascending:false});

  if(error){
    list.replaceChildren();
    const article=document.createElement("article");article.className="definitions-empty";
    const h=document.createElement("h3");h.textContent="No se pudieron cargar los flujos";
    const p=document.createElement("p");p.textContent="La consulta fue rechazada o el servicio no está disponible. No se ha modificado ningún dato.";
    article.append(h,p);list.append(article);
    setStatus("Error al consultar definiciones autorizadas.",true);
    return;
  }

  list.replaceChildren();
  if(!data?.length){
    list.append(emptyState());
    setStatus("No hay definiciones guardadas en tu ámbito.");
    return;
  }
  data.forEach(row=>list.append(card(row)));
  setStatus(`${data.length} definición${data.length===1?"":"es"} visible${data.length===1?"":"s"} en tu ámbito.`);
}

load();
