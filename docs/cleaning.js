import { supabase } from "./supabase-client.js";

const form=document.getElementById("taskForm");
const input=document.getElementById("taskId");
const lookup=document.getElementById("taskLookup");
const taskSection=document.getElementById("cleaningTask");
const checklist=document.getElementById("checklist");
const taskMeta=document.getElementById("taskMeta");
const message=document.getElementById("cleaningMessage");
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function setMessage(text){message.textContent=text||"";}

function render(data){
  checklist.replaceChildren();
  taskMeta.textContent=`Limpieza del ${data.task.task_date} · ${data.checklist.length} zona(s) solicitada(s)`;
  for(const item of data.checklist){
    const card=document.createElement("article");
    card.className="card";
    const title=document.createElement("strong");
    title.textContent=item.pattern.name;
    const state=document.createElement("span");
    state.textContent=item.completed ? "Foto enviada" : (item.kind==="cleaning" ? "Pendiente" : "Comprobación adicional");
    card.append(title,state);
    if(!item.completed){
      const a=document.createElement("a");
      a.className="primary";
      a.href=item.capture_url;
      a.textContent="Hacer foto";
      card.append(a);
    }
    checklist.append(card);
  }
  lookup.hidden=true;
  taskSection.hidden=false;
  setMessage(data.checklist.every(x=>x.completed)
    ? "Todas las fotografías solicitadas están completadas."
    : "Completa las zonas pendientes.");
}

async function load(taskId){
  if(!uuid.test(taskId)){setMessage("El identificador de tarea no es válido.");return;}
  setMessage("Cargando tu limpieza…");
  const {data,error}=await supabase.functions.invoke("my-cleaning-checklist",{body:{task_id:taskId}});
  if(error||!data?.ok){
    console.error("cleaning checklist failed",error,data);
    const code=data?.error;
    setMessage(code==="task_not_assigned_to_user"
      ? "Esta tarea no está asignada a tu usuario."
      : code==="no_active_cleaning_patterns"
        ? "Este piso todavía no tiene suficientes patrones de foto preparados."
        : "No se pudo abrir esta tarea de limpieza.");
    return;
  }
  history.replaceState(null,"",`?task_id=${encodeURIComponent(taskId)}`);
  render(data);
}

form.addEventListener("submit",e=>{e.preventDefault();load(input.value.trim());});
const initial=new URLSearchParams(location.search).get("task_id");
if(initial){input.value=initial;load(initial);}
