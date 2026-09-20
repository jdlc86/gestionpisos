import { supabase } from "./supabase-client.js";

const entry=document.getElementById("cleaningEntry");
const taskSection=document.getElementById("cleaningTask");
const checklist=document.getElementById("checklist");
const taskMeta=document.getElementById("taskMeta");
const message=document.getElementById("cleaningMessage");
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function setMessage(text){message.textContent=text||"";}

function statusMessage(data){
  if(data.task.operational_status==="waiting_review")return "Las fotografías están enviadas y esperan revisión.";
  if(data.task.operational_status==="completed")return "La limpieza está finalizada.";
  if(data.task.operational_status==="rejected")return "La limpieza está cerrada como rechazada.";
  if(data.checklist.every(item=>item.completed))return "Todas las fotografías solicitadas están completadas.";
  return "Completa las zonas pendientes.";
}

function render(data){
  checklist.replaceChildren();
  const date=data.task.task_date||"fecha asignada";
  taskMeta.textContent=`Limpieza del ${date} · ${data.checklist.length} zona(s) solicitada(s)`;

  for(const item of data.checklist){
    const card=document.createElement("article");
    card.className="card";

    const title=document.createElement("strong");
    title.textContent=item.pattern.name;

    const state=document.createElement("span");
    state.textContent=item.completed
      ?"Foto enviada"
      :data.read_only
        ?"Sin fotografía enviada"
        :item.kind==="cleaning"
          ?"Pendiente"
          :"Comprobación adicional";

    card.append(title,state);

    if(!item.completed&&!data.read_only&&item.capture_url){
      const link=document.createElement("a");
      link.className="primary";
      link.href=item.capture_url;
      link.textContent="Hacer foto";
      card.append(link);
    }

    checklist.append(card);
  }

  entry.hidden=true;
  taskSection.hidden=false;
  setMessage(statusMessage(data));
}

function errorText(code){
  if(code==="workflow_task_not_assigned_to_user"||code==="task_not_assigned_to_user")return "Esta limpieza no está asignada a tu usuario.";
  if(code==="workflow_accept_required")return "Acepta primero la tarea desde Tareas para comenzar la limpieza.";
  if(code==="workflow_task_not_cleaning")return "La tarea seleccionada no corresponde a un flujo de Limpieza.";
  if(code==="workflow_task_reference_required")return "Esta limpieza pertenece a un workflow. Ábrela desde su tarjeta en Tareas.";
  if(code==="workflow_cleaning_domain_missing"||code==="workflow_cleaning_identity_mismatch"||code==="workflow_cleaning_state_mismatch"){
    return "La limpieza no está sincronizada correctamente con su tarea. No se ha permitido continuar.";
  }
  if(code==="no_active_cleaning_patterns")return "Este piso todavía no tiene suficientes patrones de foto preparados.";
  if(code==="workflow_task_not_found"||code==="task_not_found")return "La tarea de limpieza ya no está disponible.";
  return "No se pudo abrir esta tarea de limpieza.";
}

async function load({workflowTaskId=null,legacyTaskId=null}={}){
  if(workflowTaskId&&!uuid.test(workflowTaskId)){
    setMessage("La referencia de la tarea no es válida.");
    entry.hidden=false;
    return;
  }
  if(legacyTaskId&&!uuid.test(legacyTaskId)){
    setMessage("La referencia de la limpieza no es válida.");
    entry.hidden=false;
    return;
  }

  setMessage("Cargando tu limpieza…");
  const body=workflowTaskId
    ?{workflow_task_id:workflowTaskId}
    :{task_id:legacyTaskId};

  const {data,error}=await supabase.functions.invoke("my-cleaning-checklist",{body});
  if(error||!data?.ok){
    console.error("cleaning checklist failed",error,data);
    taskSection.hidden=true;
    entry.hidden=false;
    setMessage(errorText(data?.error));
    return;
  }

  const params=new URLSearchParams();
  if(workflowTaskId)params.set("workflow_task_id",workflowTaskId);
  else if(legacyTaskId)params.set("task_id",legacyTaskId);
  history.replaceState(null,"",`?${params.toString()}`);
  render(data);
}

const params=new URLSearchParams(location.search);
const workflowTaskId=params.get("workflow_task_id");
const legacyTaskId=params.get("task_id");

if(workflowTaskId){
  load({workflowTaskId});
}else if(legacyTaskId){
  load({legacyTaskId});
}else{
  entry.hidden=false;
  taskSection.hidden=true;
  setMessage("Selecciona una tarea de Limpieza desde Tareas.");
}
