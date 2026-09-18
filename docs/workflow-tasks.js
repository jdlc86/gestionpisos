import { supabase } from "./supabase-client.js";

const list=document.getElementById("workflowTasks");
const statusBox=document.getElementById("tasksStatus");
const filter=document.getElementById("taskFilter");

let currentUser=null;
let tasks=[];
let properties=new Map();
let rooms=new Map();
let profiles=new Map();

const statusLabels={
  pending:"Pendiente",accepted:"Aceptada",in_progress:"En curso",waiting_info:"Esperando información",
  submitted:"Enviada",completed:"Completada",cancelled:"Cancelada",rejected:"Rechazada",
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
function render(){
  list.replaceChildren();
  const rows=visibleTasks();
  if(!rows.length){
    const empty=document.createElement("article");empty.className="task-empty";
    empty.textContent=filter.value==="mine"?"No tienes tareas asignadas en este filtro.":"No hay tareas visibles con este filtro.";
    list.append(empty);
    return;
  }

  rows.forEach(task=>{
    const article=document.createElement("article");article.className="task-card";
    article.dataset.taskId=task.id;

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

    if(task.source_kind==="workflow_execution"){
      const note=document.createElement("div");note.className="task-note";
      note.textContent="La tarea está materializada y trazada a su ejecución. Las acciones se habilitarán cuando tarea y ejecución puedan cambiar de estado de forma atómica.";
      article.append(note);
    }

    list.append(article);
  });
}

async function loadRelated(){
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

async function load(){
  const {data:userData,error:userError}=await supabase.auth.getUser();
  if(userError||!userData?.user){
    list.replaceChildren();
    setStatus("No se pudo validar la sesión.",true);
    return;
  }
  currentUser=userData.user;

  const {data,error}=await supabase
    .from("tenant_tasks_v2")
    .select("id,organization_id,tenant_id,property_id,room_id,task_type,origin,title,description,status,due_at,assigned_user_id,source_kind,source_id,created_at")
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
  await loadRelated();
  render();

  const workflowCount=tasks.filter(task=>task.source_kind==="workflow_execution").length;
  setStatus(tasks.length+" tarea"+(tasks.length===1?"":"s")+" visible"+(tasks.length===1?"":"s")+(workflowCount?" · "+workflowCount+" generada"+(workflowCount===1?"":"s")+" por workflow.":"."));
}

filter.addEventListener("change",render);
load();
