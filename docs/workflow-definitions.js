import { supabase } from "./supabase-client.js";

const list=document.getElementById("workflowDefinitions");
const status=document.getElementById("definitionsStatus");
let versionsByDefinition=new Map();

const labels={
  flowType:{cleaning:"Limpieza",inspection:"Inspección",maintenance:"Mantenimiento",checkin:"Check-in",checkout:"Check-out",custom:"Personalizado"},
  scopeType:{property:"Un piso",organization:"Toda la organización",room:"Una habitación",occupancy:"Una ocupación / inquilino"},
  triggerType:{manual:"Manual",recurring:"Recurrente",scheduled_once:"Fecha concreta",event:"Por evento"},
  recurrence:{weekly:"Cada semana",biweekly:"Cada 2 semanas",monthly:"Cada mes",custom:"Personalizada"},
  customUnit:{day:"día(s)",week:"semana(s)",month:"mes(es)"},
  assignmentType:{property_responsible:"Responsable operativo del piso",active_occupants_rotation:"Ocupantes activos en rotación",fixed_person:"Persona fija",role:"Rol o capacidad",manual:"Se decide al iniciar"},
  status:{draft:"Borrador",published:"Publicado",paused:"Pausado",archived:"Archivado"}
};

function text(group,key){return labels[group]?.[key]||key||"Pendiente"}
function setStatus(message,error=false){
  const span=status?.querySelector("span:last-child");
  if(span)span.textContent=message;
  status?.classList.toggle("error",error);
}
function dateTime(value){
  if(!value)return "—";
  try{return new Intl.DateTimeFormat("es-ES",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value))}catch{return value}
}
function latestVersion(row){return versionsByDefinition.get(row.id)?.[0]||null}
function activationText(row){
  const spec=row.status==="published"?(latestVersion(row)?.spec||{}):(row.draft_spec&&typeof row.draft_spec==="object"?row.draft_spec:{});
  const trigger=String(spec.triggerType||row.trigger_type||"");
  const base=text("triggerType",trigger);
  if(trigger==="recurring"){
    const recurrence=String(spec.recurrence||"");
    if(!recurrence)return base;
    if(recurrence==="custom"){
      const every=String(spec.customEvery||"").trim();
      const unit=String(spec.customUnit||"");
      return every&&unit?base+" · Cada "+every+" "+text("customUnit",unit):base+" · "+text("recurrence",recurrence);
    }
    return base+" · "+text("recurrence",recurrence);
  }
  if(trigger==="scheduled_once"){
    const scheduledAt=String(spec.scheduledAt||"").trim();
    return scheduledAt?base+" · "+dateTime(scheduledAt):base;
  }
  return base;
}
function errorText(error){
  const message=String(error?.message||"");
  if(message.includes("aal2_required"))return "Para publicar debes completar MFA (sesión AAL2). El borrador no se ha modificado.";
  if(message.includes("workflow_authoring_incomplete"))return "El borrador todavía no tiene toda la configuración explícita.";
  if(message.includes("workflow_draft_conflict"))return "El borrador cambió en otra sesión. Recarga antes de publicar.";
  if(message.includes("workflow_publish_not_authorized"))return "Tu sesión no tiene autorización para publicar este flujo.";
  return "No se pudo publicar. El borrador conserva su estado anterior.";
}
function meta(label,value){
  const box=document.createElement("div");box.className="definition-meta-item";
  const strong=document.createElement("strong");strong.textContent=label;
  const span=document.createElement("span");span.textContent=value||"Pendiente";
  box.append(strong,span);return box;
}

async function publishDefinition(row,button){
  if(!window.confirm("¿Publicar esta receta? Se creará una versión inmutable. El piso, habitación u ocupación concreta se seleccionará después en Aplicaciones."))return;
  button.disabled=true;
  const original=button.textContent;
  button.textContent="Publicando…";
  setStatus("Validando y publicando la receta…");
  const {data,error}=await supabase.rpc("publish_workflow_definition_v1",{
    p_definition_id:row.id,
    p_expected_revision:row.revision
  });
  if(error){
    button.disabled=false;
    button.textContent=original;
    setStatus(errorText(error),true);
    return;
  }
  const published=Array.isArray(data)?data[0]:null;
  setStatus("Versión v"+(published?.version||1)+" publicada. Ahora puedes aplicarla a un destino real.");
  await load();
}

function card(row){
  const article=document.createElement("article");article.className="definition-card";
  const head=document.createElement("div");head.className="definition-card-head";
  const title=document.createElement("h3");title.textContent=row.name;
  const badge=document.createElement("span");badge.className="definition-badge";
  if(row.status==="draft"){
    badge.textContent=row.authoring_complete?"Borrador configurado":"Borrador incompleto";
    badge.classList.toggle("definition-badge--complete",Boolean(row.authoring_complete));
    badge.classList.toggle("definition-badge--incomplete",!row.authoring_complete);
  }else{
    badge.textContent=text("status",row.status);
    badge.classList.toggle("definition-badge--complete",row.status==="published");
  }
  head.append(title,badge);

  const version=latestVersion(row);
  const details=document.createElement("div");details.className="definition-meta";
  details.append(
    meta("Configuración",row.authoring_complete?"Completa":"Pendiente"),
    meta("Tipo",text("flowType",row.flow_type)),
    meta("Ámbito lógico",text("scopeType",row.scope_type)),
    meta("Activación",activationText(row)),
    meta("Asignación",text("assignmentType",row.assignment_type)),
    meta(row.status==="published"?"Versión publicada":"Revisión",row.status==="published"?"v"+(version?.version||"?"):String(row.revision||1)),
    meta("Último cambio",dateTime(row.updated_at))
  );

  const actions=document.createElement("div");actions.className="definition-actions";
  if(row.status==="draft"){
    const edit=document.createElement("a");
    edit.className="secondary";
    edit.href="./workflow-builder.html?id="+encodeURIComponent(row.id);
    edit.textContent=row.authoring_complete?"Revisar borrador":"Completar borrador";
    actions.append(edit);

    if(row.authoring_complete){
      const publish=document.createElement("button");
      publish.type="button";
      publish.className="primary";
      publish.textContent="Publicar versión";
      publish.addEventListener("click",()=>publishDefinition(row,publish));
      actions.append(publish);
    }
  }else if(row.status==="published"){
    const applications=document.createElement("a");
    applications.className="primary";
    applications.href="./workflow-applications.html?definition="+encodeURIComponent(row.id);
    applications.textContent="Aplicaciones";
    actions.append(applications);
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
    .select("id,name,flow_type,scope_type,trigger_type,assignment_type,status,revision,authoring_complete,updated_at,draft_spec")
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

  const rows=data||[];
  versionsByDefinition=new Map();
  if(rows.length){
    const {data:versionData,error:versionError}=await supabase
      .from("workflow_definition_versions_v2")
      .select("id,definition_id,version,spec,published_at")
      .in("definition_id",rows.map(row=>row.id))
      .order("version",{ascending:false});
    if(versionError){
      setStatus("No se pudieron consultar las versiones publicadas.",true);
      return;
    }
    (versionData||[]).forEach(version=>{
      const bucket=versionsByDefinition.get(version.definition_id)||[];
      bucket.push(version);
      versionsByDefinition.set(version.definition_id,bucket);
    });
  }

  list.replaceChildren();
  if(!rows.length){
    list.append(emptyState());
    setStatus("No hay definiciones guardadas en tu ámbito.");
    return;
  }
  rows.forEach(row=>list.append(card(row)));
  const incomplete=rows.filter(row=>row.status==="draft"&&!row.authoring_complete).length;
  const published=rows.filter(row=>row.status==="published").length;
  setStatus(
    rows.length+" definición"+(rows.length===1?"":"es")+" visible"+(rows.length===1?"":"s")
    +(published?" · "+published+" publicada"+(published===1?"":"s"):"")
    +(incomplete?" · "+incomplete+" borrador"+(incomplete===1?"":"es")+" incompleto"+(incomplete===1?"":"s")+".":".")
  );
}

load();
