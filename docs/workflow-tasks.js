import { supabase } from "./supabase-client.js";

const list=document.getElementById("workflowTasks");
const statusBox=document.getElementById("tasksStatus");
const filter=document.getElementById("taskFilter");

let currentUser=null;
let tasks=[];
let properties=new Map();
let rooms=new Map();
let profiles=new Map();
let actionsByTask=new Map();
let photoResourcesByExecution=new Map();

const ACTION_KEY_PREFIX="workflow-task-action:";
const statusLabels={
  pending:"Pendiente",active:"En curso",waiting_review:"Esperando revisión",
  accepted:"Aceptada",in_progress:"En curso",waiting_info:"Esperando información",
  submitted:"Enviada",completed:"Completada",cancelled:"Cancelada",failed:"Fallida",rejected:"Rechazada",
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
function errorText(error){
  const message=String(error?.message||"");
  if(message.includes("workflow_action_actor_forbidden"))return "Esta acción solo puede realizarla la persona asignada.";
  if(message.includes("workflow_action_not_allowed"))return "La acción ya no está disponible para el estado actual.";
  if(message.includes("workflow_task_execution_state_mismatch"))return "Tarea y ejecución no están sincronizadas. No se ha aplicado ningún cambio.";
  if(message.includes("workflow_action_request_key_conflict"))return "El identificador de reintento pertenece a otra acción. Recarga la pantalla.";
  if(message.includes("workflow_action_note_required"))return "Esta acción requiere una nota.";
  if(message.includes("workflow_action_not_supported")||message.includes("workflow_action_close_rule_not_supported"))return "Esta transición todavía no está habilitada para esta receta.";
  return "No se pudo aplicar la acción. No se ha confirmado ningún cambio.";
}
function requestKey(task,action){
  const storageKey=ACTION_KEY_PREFIX+task.id+":"+action.action_key+":"+action.from_status;
  let key=sessionStorage.getItem(storageKey);
  if(!key){
    key=globalThis.crypto?.randomUUID?.()||("action-"+Date.now()+"-"+Math.random().toString(36).slice(2));
    sessionStorage.setItem(storageKey,key);
  }
  return {storageKey,key};
}
function actionNote(task){
  if(task.status==="completed")return "Tarea y ejecución completadas de forma sincronizada.";
  if(task.status==="waiting_review")return "La tarea está esperando la revisión definida por la receta.";
  if(task.status==="active")return "La tarea está activa. Quedan pasos de la receta que todavía deben completarse.";
  if(task.status==="rejected")return "La persona asignada rechazó la tarea. El motivo queda registrado en el histórico.";
  return "No hay una acción operativa habilitada para esta receta en el estado actual.";
}
function photoResourceLabel(resource){
  const snapshot=resource.pattern_snapshot||{};
  return snapshot.name||snapshot.target_key||"Fotografía";
}
function workflowPhotoUrl(task,resource){
  const url=new URL("./photo-camera.html",window.location.href);
  url.searchParams.set("mode","verify");
  url.searchParams.set("pattern_id",resource.pattern_id);
  url.searchParams.set("workflow_resource_id",resource.id);
  url.searchParams.set("source_type","workflow_execution");
  url.searchParams.set("source_id",task.source_id);
  return url.href;
}
function renderPhotoResources(task,article){
  if(task.source_kind!=="workflow_execution"||!task.source_id)return;
  const resources=(photoResourcesByExecution.get(task.source_id)||[])
    .slice()
    .sort((a,b)=>a.sort_order-b.sort_order);
  if(!resources.length)return;

  const box=document.createElement("div");
  box.className="task-photo-resources";
  const heading=document.createElement("strong");
  heading.textContent="Evidencia fotográfica";
  box.append(heading);

  resources.forEach(resource=>{
    const row=document.createElement("div");
    row.className="task-photo-resource";
    const info=document.createElement("div");
    const title=document.createElement("span");
    title.textContent=photoResourceLabel(resource);
    const state=document.createElement("small");
    state.textContent=resource.status==="submitted"
      ?"Enviada"
      :resource.status==="capturing"
        ?"Captura iniciada"
        :"Pendiente";
    info.append(title,state);
    row.append(info);

    const canCapture=resource.status!=="submitted"&&(
      task.status==="active"
      || (task.status==="pending"&&!resource.requires_accept)
    );

    if(canCapture){
      const link=document.createElement("a");
      link.className="primary task-photo-button";
      link.href=workflowPhotoUrl(task,resource);
      link.textContent=resource.status==="capturing"?"Continuar foto":"Hacer foto";
      row.append(link);
    }else if(resource.status!=="submitted"&&resource.requires_accept&&task.status==="pending"){
      const note=document.createElement("span");
      note.className="task-photo-wait";
      note.textContent="Acepta primero";
      row.append(note);
    }

    box.append(row);
  });

  article.append(box);
}

function renderActions(task,article){
  if(task.source_kind!=="workflow_execution")return;

  const available=(actionsByTask.get(task.id)||[])
    .filter(action=>action.active&&action.from_status===task.status)
    .sort((a,b)=>(a.sort_order||0)-(b.sort_order||0));

  if(!available.length){
    const note=document.createElement("div");note.className="task-note";
    note.textContent=actionNote(task);
    article.append(note);
    return;
  }

  const box=document.createElement("div");box.className="task-actions";
  const heading=document.createElement("strong");heading.textContent="Acciones";
  box.append(heading);

  available.forEach(action=>{
    const button=document.createElement("button");
    button.type="button";
    button.className=action.action_key==="reject"?"secondary task-action--reject":"primary";
    button.textContent=action.label;
    button.addEventListener("click",()=>applyWorkflowAction(task,action,button));
    box.append(button);

    if(action.to_status==="completed"){
      const note=document.createElement("span");note.className="task-action-note";
      note.textContent="Esta es la única etapa pendiente; al aceptar se cerrarán tarea y ejecución.";
      box.append(note);
    }else if(action.to_status==="waiting_review"){
      const note=document.createElement("span");note.className="task-action-note";
      note.textContent="Después de aceptar quedará pendiente la revisión humana.";
      box.append(note);
    }
  });

  article.append(box);
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

    renderPhotoResources(task,article);
    renderActions(task,article);
    list.append(article);
  });
}

async function applyWorkflowAction(task,action,button){
  let note=null;
  if(action.requires_note){
    note=window.prompt(action.action_key==="reject"?"Indica el motivo del rechazo:":"Añade la nota obligatoria para esta acción:");
    if(note===null)return;
    if(!note.trim()){
      setStatus("Esta acción requiere una nota.",true);
      return;
    }
  }

  const {storageKey,key}=requestKey(task,action);
  const original=button.textContent;
  button.disabled=true;
  button.textContent="Aplicando…";
  setStatus("Aplicando la acción sobre tarea y ejecución en una única transacción…");

  const {data,error}=await supabase.rpc("apply_workflow_task_action_v1",{
    p_task_id:task.id,
    p_action_key:action.action_key,
    p_request_key:key,
    p_note:note
  });

  button.textContent=original;

  if(error){
    button.disabled=false;
    const message=String(error.message||"");
    if(message.includes("workflow_")&&!message.includes("network"))sessionStorage.removeItem(storageKey);
    setStatus(errorText(error),true);
    return;
  }

  sessionStorage.removeItem(storageKey);
  const result=Array.isArray(data)?data[0]:null;
  const label=statusLabels[result?.task_status]||result?.task_status||"actualizado";

  if(result?.applied_new===false){
    setStatus("El reintento recuperó la transición ya aplicada; no se duplicó el histórico.");
  }else{
    setStatus("Tarea y ejecución actualizadas juntas: "+label+".");
  }

  await load(true);
}

async function loadRelated(){
  properties=new Map();
  rooms=new Map();
  profiles=new Map();

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

async function loadPhotoResources(){
  photoResourcesByExecution=new Map();
  const executionIds=[...new Set(tasks
    .filter(task=>task.source_kind==="workflow_execution"&&task.source_id)
    .map(task=>task.source_id))];
  if(!executionIds.length)return;

  const {data,error}=await supabase
    .from("workflow_execution_photo_resources_v2")
    .select("id,execution_id,pattern_id,pattern_version,pattern_snapshot,sort_order,requires_accept,status,photo_run_id")
    .in("execution_id",executionIds)
    .order("sort_order");

  if(error)throw error;

  (data||[]).forEach(resource=>{
    const bucket=photoResourcesByExecution.get(resource.execution_id)||[];
    bucket.push(resource);
    photoResourcesByExecution.set(resource.execution_id,bucket);
  });
}

async function loadActions(){
  actionsByTask=new Map();
  const workflowIds=tasks
    .filter(task=>task.source_kind==="workflow_execution")
    .map(task=>task.id);
  if(!workflowIds.length)return;

  const {data,error}=await supabase
    .from("tenant_task_actions_v2")
    .select("id,task_id,action_key,label,from_status,to_status,requires_note,sort_order,active,actor")
    .in("task_id",workflowIds)
    .eq("active",true)
    .order("sort_order");

  if(error)throw error;

  (data||[]).forEach(action=>{
    const bucket=actionsByTask.get(action.task_id)||[];
    bucket.push(action);
    actionsByTask.set(action.task_id,bucket);
  });
}

async function load(preserveStatus=false){
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

  try{
    await Promise.all([loadRelated(),loadActions(),loadPhotoResources()]);
  }catch{
    list.replaceChildren();
    const empty=document.createElement("article");empty.className="task-empty";
    empty.textContent="No se pudieron cargar todos los datos operativos de las tareas.";
    list.append(empty);
    setStatus("La tarea existe, pero sus datos relacionados no pudieron consultarse.",true);
    return;
  }

  render();

  const workflowCount=tasks.filter(task=>task.source_kind==="workflow_execution").length;
  if(!preserveStatus){
    setStatus(tasks.length+" tarea"+(tasks.length===1?"":"s")+" visible"+(tasks.length===1?"":"s")+(workflowCount?" · "+workflowCount+" generada"+(workflowCount===1?"":"s")+" por workflow.":"."));
  }
}

filter.addEventListener("change",render);
load();
