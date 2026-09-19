import { supabase } from "./supabase-client.js";

const list=document.getElementById("workflowDefinitions");
const status=document.getElementById("definitionsStatus");
const params=new URLSearchParams(window.location.search);
const highlightedDefinition=params.get("published")||"";

let versionsByDefinition=new Map();
let revisionDraftByDefinition=new Map();
let applicationsByDefinition=new Map();
let executionsByDefinition=new Map();
let propertyById=new Map();
let roomById=new Map();
let occupancyById=new Map();

const labels={
  flowType:{cleaning:"Limpieza",inspection:"Inspección",maintenance:"Mantenimiento",checkin:"Check-in",checkout:"Check-out",custom:"Personalizado"},
  scopeType:{property:"Un piso",organization:"Toda la organización",room:"Una habitación",occupancy:"Una ocupación / inquilino"},
  triggerType:{manual:"Manual",recurring:"Recurrente",scheduled_once:"Fecha concreta",event:"Por evento"},
  recurrence:{weekly:"Cada semana",biweekly:"Cada 2 semanas",monthly:"Cada mes",custom:"Personalizada"},
  customUnit:{day:"día(s)",week:"semana(s)",month:"mes(es)"},
  assignmentType:{property_responsible:"Responsable operativo del piso",active_occupants_rotation:"Ocupantes activos en rotación",fixed_person:"Persona fija",role:"Rol o capacidad",manual:"Se decide al iniciar"}
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
function publishedSpec(row){return latestVersion(row)?.spec||{}}
function applicationsFor(row){return applicationsByDefinition.get(row.id)||[]}
function executionsFor(row){return executionsByDefinition.get(row.id)||[]}
function hasHistory(row){return executionsFor(row).length>0}
function currentApplication(row){
  const latest=latestVersion(row);
  const apps=applicationsFor(row);
  return apps.find(app=>app.status==="configured"&&app.definition_version_id===latest?.id)
    || apps.find(app=>app.status==="configured")
    || null;
}
function activationText(row){
  const spec=publishedSpec(row);
  const trigger=String(spec.triggerType||"");
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
function meta(label,value){
  const box=document.createElement("div");box.className="definition-meta-item";
  const strong=document.createElement("strong");strong.textContent=label;
  const span=document.createElement("span");span.textContent=value||"—";
  box.append(strong,span);return box;
}
function targetText(app){
  if(!app)return "Sin destino configurado";
  if(app.scope_type==="organization")return "Toda la organización";
  const property=propertyById.get(app.property_id);
  if(app.scope_type==="property")return property?.name||"Piso";
  if(app.scope_type==="room"){
    const room=roomById.get(app.room_id);
    return [property?.name,room?.label||"Habitación"].filter(Boolean).join(" · ");
  }
  if(app.scope_type==="occupancy"){
    const occupancy=occupancyById.get(app.occupancy_id);
    const person=occupancy?.tenants_v2?.full_name||occupancy?.occupant_email||"Ocupación";
    return [property?.name,person].filter(Boolean).join(" · ");
  }
  return "Destino";
}
function errorText(error){
  const message=String(error?.message||"");
  if(message.includes("aal2_required"))return "Esta operación requiere MFA (sesión AAL2).";
  if(message.includes("workflow_definition_has_history"))return "Este flujo ya tiene historial y no puede eliminarse.";
  if(message.includes("workflow_unexecuted_delete_instead"))return "Este flujo nunca se ha ejecutado; elimínalo en lugar de archivarlo.";
  if(message.includes("workflow_definition_delete_forbidden")||message.includes("workflow_definition_archive_forbidden"))return "No tienes permiso para realizar esta operación.";
  if(message.includes("workflow_revision_requires_published_definition"))return "Este flujo ya no está disponible para edición.";
  if(message.includes("workflow_author_role_required"))return "Tu sesión no tiene autorización para editar flujos.";
  return "No se pudo completar la operación.";
}

async function startRevision(row,button){
  button.disabled=true;
  const original=button.textContent;
  button.textContent="Preparando…";
  setStatus("Preparando la edición sin alterar el historial actual…");
  const {data,error}=await supabase.rpc("start_workflow_definition_revision_v1",{p_definition_id:row.id});
  if(error){
    button.disabled=false;
    button.textContent=original;
    setStatus(errorText(error),true);
    return;
  }
  const result=Array.isArray(data)?data[0]:null;
  window.location.href="./workflow-builder.html?id="+encodeURIComponent(row.id)+"&revision=1&base="+encodeURIComponent(result?.base_version||"");
}

async function deleteDefinition(row,button){
  if(!window.confirm("Este flujo nunca se ha ejecutado. Eliminarlo lo quitará definitivamente de Mis Flujos y no se conservará como historial. ¿Eliminar?"))return;
  button.disabled=true;
  const original=button.textContent;
  button.textContent="Eliminando…";
  setStatus("Eliminando flujo sin ejecuciones…");
  const {error}=await supabase.rpc("delete_unexecuted_workflow_v1",{p_definition_id:row.id});
  if(error){
    button.disabled=false;
    button.textContent=original;
    setStatus(errorText(error),true);
    return;
  }
  setStatus("Flujo eliminado. No existían tareas ni ejecuciones que conservar.");
  await load();
}

async function archiveDefinition(row,button){
  if(!window.confirm("Este flujo ya tiene historial. Se conservarán sus versiones, ejecuciones y tareas, pero dejará de estar disponible para nuevas ejecuciones. ¿Archivar?"))return;
  button.disabled=true;
  const original=button.textContent;
  button.textContent="Archivando…";
  setStatus("Archivando flujo y conservando su historial…");
  const {error}=await supabase.rpc("archive_workflow_definition_v1",{p_definition_id:row.id});
  if(error){
    button.disabled=false;
    button.textContent=original;
    setStatus(errorText(error),true);
    return;
  }
  setStatus("Flujo archivado. Su historial permanece intacto.");
  await load();
}

function card(row){
  const version=latestVersion(row);
  const spec=publishedSpec(row);
  const draft=revisionDraftByDefinition.get(row.id)||null;
  const app=currentApplication(row);
  const history=hasHistory(row);
  const executionCount=executionsFor(row).length;

  const article=document.createElement("article");article.className="definition-card";
  if(row.id===highlightedDefinition)article.classList.add("is-highlighted");

  const head=document.createElement("div");head.className="definition-card-head";
  const title=document.createElement("h3");title.textContent=String(spec.flowName||row.name||"Flujo");
  const badge=document.createElement("span");
  badge.className="definition-badge "+(history?"definition-badge--complete":"definition-badge--incomplete");
  badge.textContent=history?"Con historial":"Sin ejecuciones";
  head.append(title,badge);

  const details=document.createElement("div");details.className="definition-meta";
  details.append(
    meta("Tipo",text("flowType",String(spec.flowType||""))),
    meta("Destino",targetText(app)),
    meta("Activación",activationText(row)),
    meta("Asignación",text("assignmentType",String(spec.assignmentType||""))),
    meta("Versión actual","v"+(version?.version||"?")),
    meta("Ejecuciones",String(executionCount))
  );

  article.append(head,details);

  if(history&&draft){
    const note=document.createElement("div");note.className="definition-draft-note";
    note.textContent="Edición en curso. La configuración publicada y su historial siguen intactos.";
    article.append(note);
  }

  const actions=document.createElement("div");actions.className="definition-actions";

  const execute=document.createElement("a");
  execute.className="primary";
  execute.textContent="Ejecutar";
  execute.href="./workflow-applications.html?definition="+encodeURIComponent(row.id)
    +"&setup=1&intent=execute&from=mis-flujos"
    +(app?"&application="+encodeURIComponent(app.id):"");
  actions.append(execute);

  if(history){
    if(draft){
      const edit=document.createElement("a");
      edit.className="secondary";
      edit.href="./workflow-builder.html?id="+encodeURIComponent(row.id)+"&revision=1";
      edit.textContent="Editar";
      actions.append(edit);
    }else{
      const edit=document.createElement("button");
      edit.type="button";
      edit.className="secondary";
      edit.textContent="Editar";
      edit.addEventListener("click",()=>startRevision(row,edit));
      actions.append(edit);
    }

    const archive=document.createElement("button");
    archive.type="button";
    archive.className="danger-soft";
    archive.textContent="Archivar";
    archive.addEventListener("click",()=>archiveDefinition(row,archive));
    actions.append(archive);
  }else{
    const edit=document.createElement("a");
    edit.className="secondary";
    edit.href="./workflow-builder.html?id="+encodeURIComponent(row.id)+"&edit=1";
    edit.textContent="Editar";
    actions.append(edit);

    const remove=document.createElement("button");
    remove.type="button";
    remove.className="danger-soft";
    remove.textContent="Eliminar";
    remove.addEventListener("click",()=>deleteDefinition(row,remove));
    actions.append(remove);
  }

  article.append(actions);
  return article;
}

function emptyState(){
  const article=document.createElement("article");article.className="definitions-empty";
  const h=document.createElement("h3");h.textContent="Todavía no hay flujos";
  const p=document.createElement("p");p.textContent="Los flujos aparecen aquí cuando completas el Creador y eliges Publicar o Ejecutar.";
  const link=document.createElement("a");link.className="primary definitions-create";link.href="./workflow-builder.html";link.textContent="Crear flujo";
  article.append(h,p,link);return article;
}

async function load(){
  const {data:userData,error:userError}=await supabase.auth.getUser();
  if(userError||!userData?.user){
    list.replaceChildren();
    setStatus("No se pudo validar la sesión.",true);
    return;
  }

  const {data:roleRows,error:roleError}=await supabase
    .from("user_roles")
    .select("role,organization_id,revoked_at")
    .eq("user_id",userData.user.id)
    .is("revoked_at",null);
  if(roleError||!(roleRows||[]).some(row=>["root","admin"].includes(row.role))){
    list.replaceChildren();
    const article=document.createElement("article");article.className="definitions-empty";
    article.textContent="Mis Flujos requiere acceso ROOT o ADMIN autorizado.";
    list.append(article);
    setStatus("Acceso administrativo requerido.",true);
    return;
  }

  const {data,error}=await supabase
    .from("workflow_definitions_v2")
    .select("id,name,status,organization_id,revision,updated_at")
    .eq("status","published")
    .order("updated_at",{ascending:false});

  if(error){
    list.replaceChildren();
    setStatus("Error al consultar Mis Flujos.",true);
    return;
  }

  const rows=data||[];
  versionsByDefinition=new Map();
  revisionDraftByDefinition=new Map();
  applicationsByDefinition=new Map();
  executionsByDefinition=new Map();
  propertyById=new Map();
  roomById=new Map();
  occupancyById=new Map();

  if(rows.length){
    const ids=rows.map(row=>row.id);
    const [versionResult,draftResult,applicationResult]=await Promise.all([
      supabase
        .from("workflow_definition_versions_v2")
        .select("id,definition_id,version,spec,published_at")
        .in("definition_id",ids)
        .order("version",{ascending:false}),
      supabase
        .from("workflow_definition_revision_drafts_v2")
        .select("definition_id,base_version,revision,authoring_complete,updated_at,published_at")
        .in("definition_id",ids)
        .is("published_at",null),
      supabase
        .from("workflow_applications_v2")
        .select("id,definition_id,definition_version_id,scope_type,property_id,room_id,occupancy_id,status,created_at")
        .in("definition_id",ids)
        .order("created_at",{ascending:false})
    ]);

    if(versionResult.error||draftResult.error||applicationResult.error){
      setStatus("No se pudieron consultar las versiones, ediciones o destinos.",true);
      return;
    }

    (versionResult.data||[]).forEach(version=>{
      const bucket=versionsByDefinition.get(version.definition_id)||[];
      bucket.push(version);
      versionsByDefinition.set(version.definition_id,bucket);
    });
    (draftResult.data||[]).forEach(draft=>revisionDraftByDefinition.set(draft.definition_id,draft));
    (applicationResult.data||[]).forEach(app=>{
      const bucket=applicationsByDefinition.get(app.definition_id)||[];
      bucket.push(app);
      applicationsByDefinition.set(app.definition_id,bucket);
    });

    const applications=applicationResult.data||[];
    const applicationIds=applications.map(app=>app.id);
    const appToDefinition=new Map(applications.map(app=>[app.id,app.definition_id]));

    if(applicationIds.length){
      const {data:executionData,error:executionError}=await supabase
        .from("workflow_executions_v2")
        .select("id,application_id,status,created_at")
        .in("application_id",applicationIds)
        .order("created_at",{ascending:false});
      if(executionError){
        setStatus("No se pudo comprobar el historial de ejecución.",true);
        return;
      }
      (executionData||[]).forEach(execution=>{
        const definitionId=appToDefinition.get(execution.application_id);
        if(!definitionId)return;
        const bucket=executionsByDefinition.get(definitionId)||[];
        bucket.push(execution);
        executionsByDefinition.set(definitionId,bucket);
      });
    }

    const propertyIds=[...new Set(applications.map(app=>app.property_id).filter(Boolean))];
    const roomIds=[...new Set(applications.map(app=>app.room_id).filter(Boolean))];
    const occupancyIds=[...new Set(applications.map(app=>app.occupancy_id).filter(Boolean))];

    const [propertyResult,roomResult,occupancyResult]=await Promise.all([
      propertyIds.length
        ?supabase.from("properties_v2").select("id,name,address_line").in("id",propertyIds)
        :Promise.resolve({data:[],error:null}),
      roomIds.length
        ?supabase.from("rooms_v2").select("id,property_id,label").in("id",roomIds)
        :Promise.resolve({data:[],error:null}),
      occupancyIds.length
        ?supabase.from("occupancies_v2").select("id,property_id,occupant_email,tenants_v2(full_name,email)").in("id",occupancyIds)
        :Promise.resolve({data:[],error:null})
    ]);
    if(propertyResult.error||roomResult.error||occupancyResult.error){
      setStatus("No se pudieron resolver algunos destinos.",true);
      return;
    }
    (propertyResult.data||[]).forEach(item=>propertyById.set(item.id,item));
    (roomResult.data||[]).forEach(item=>roomById.set(item.id,item));
    (occupancyResult.data||[]).forEach(item=>occupancyById.set(item.id,item));
  }

  const publishedRows=rows.filter(row=>latestVersion(row));
  list.replaceChildren();
  if(!publishedRows.length){
    list.append(emptyState());
    setStatus("No hay flujos publicados en tu ámbito.");
    return;
  }

  publishedRows.forEach(row=>list.append(card(row)));
  const withHistory=publishedRows.filter(hasHistory).length;
  const withoutHistory=publishedRows.length-withHistory;
  setStatus(
    publishedRows.length+" flujo"+(publishedRows.length===1?"":"s")
    +" · "+withoutHistory+" sin ejecutar"
    +" · "+withHistory+" con historial."
  );
}

load();
