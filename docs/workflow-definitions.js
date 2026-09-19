import { supabase } from "./supabase-client.js";

const list=document.getElementById("workflowDefinitions");
const status=document.getElementById("definitionsStatus");
const params=new URLSearchParams(window.location.search);
const highlightedDefinition=params.get("published")||"";
let versionsByDefinition=new Map();
let revisionDraftByDefinition=new Map();

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
function errorText(error){
  const message=String(error?.message||"");
  if(message.includes("workflow_revision_requires_published_definition"))return "Solo una receta publicada puede iniciar una nueva versión.";
  if(message.includes("workflow_author_role_required"))return "Tu sesión no tiene autorización para editar esta receta.";
  if(message.includes("workflow_definition_not_found"))return "No se encontró la receta publicada.";
  return "No se pudo preparar la nueva versión. La versión publicada no se ha modificado.";
}

async function startRevision(row,button){
  button.disabled=true;
  const original=button.textContent;
  button.textContent="Preparando…";
  setStatus("Creando un borrador desde la versión publicada…");
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

function card(row){
  const version=latestVersion(row);
  const spec=publishedSpec(row);
  const draft=revisionDraftByDefinition.get(row.id)||null;

  const article=document.createElement("article");article.className="definition-card";
  if(row.id===highlightedDefinition)article.classList.add("is-highlighted");

  const head=document.createElement("div");head.className="definition-card-head";
  const title=document.createElement("h3");title.textContent=String(spec.flowName||row.name||"Flujo");
  const badge=document.createElement("span");badge.className="definition-badge definition-badge--complete";
  badge.textContent="Publicado · v"+(version?.version||"?");
  head.append(title,badge);

  const details=document.createElement("div");details.className="definition-meta";
  details.append(
    meta("Tipo",text("flowType",String(spec.flowType||""))),
    meta("Ámbito lógico",text("scopeType",String(spec.scopeType||""))),
    meta("Activación",activationText(row)),
    meta("Asignación",text("assignmentType",String(spec.assignmentType||""))),
    meta("Cierre",String(spec.closeType||"").replace("human_review","Revisión humana").replace("auto","Automático").replace("domain_adapter","Regla especializada")),
    meta("Publicada",dateTime(version?.published_at))
  );

  article.append(head,details);

  if(draft){
    const note=document.createElement("div");note.className="definition-draft-note";
    note.textContent="Nueva v"+(Number(draft.base_version)+1)+" en borrador · revisión "+draft.revision+". La v"+version.version+" sigue operativa.";
    article.append(note);
  }

  const actions=document.createElement("div");actions.className="definition-actions";
  const applications=document.createElement("a");
  applications.className="primary";
  applications.href="./workflow-applications.html?definition="+encodeURIComponent(row.id);
  applications.textContent="Usar flujo";
  actions.append(applications);

  if(draft){
    const resume=document.createElement("a");
    resume.className="secondary";
    resume.href="./workflow-builder.html?id="+encodeURIComponent(row.id)+"&revision=1";
    resume.textContent="Continuar nueva versión";
    actions.append(resume);
  }else{
    const revise=document.createElement("button");
    revise.type="button";
    revise.className="secondary";
    revise.textContent="Crear nueva versión";
    revise.addEventListener("click",()=>startRevision(row,revise));
    actions.append(revise);
  }

  article.append(actions);
  return article;
}

function emptyState(){
  const article=document.createElement("article");article.className="definitions-empty";
  const h=document.createElement("h3");h.textContent="Todavía no hay flujos publicados";
  const p=document.createElement("p");p.textContent="Los borradores viven en el Creador de Flujos. Publica uno para que aparezca aquí.";
  const link=document.createElement("a");link.className="primary definitions-create";link.href="./workflow-builder.html";link.textContent="Abrir Creador";
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
    article.textContent="Las recetas publicadas solo pueden consultarlas ROOT o ADMIN autorizados.";
    list.append(article);
    setStatus("Acceso administrativo requerido.",true);
    return;
  }

  const {data,error}=await supabase
    .from("workflow_definitions_v2")
    .select("id,name,status,organization_id")
    .eq("status","published")
    .order("updated_at",{ascending:false});

  if(error){
    list.replaceChildren();
    setStatus("Error al consultar las recetas publicadas.",true);
    return;
  }

  const rows=data||[];
  versionsByDefinition=new Map();
  revisionDraftByDefinition=new Map();

  if(rows.length){
    const ids=rows.map(row=>row.id);
    const [versionResult,draftResult]=await Promise.all([
      supabase
        .from("workflow_definition_versions_v2")
        .select("id,definition_id,version,spec,published_at")
        .in("definition_id",ids)
        .order("version",{ascending:false}),
      supabase
        .from("workflow_definition_revision_drafts_v2")
        .select("definition_id,base_version,revision,authoring_complete,updated_at,published_at")
        .in("definition_id",ids)
        .is("published_at",null)
    ]);

    if(versionResult.error||draftResult.error){
      setStatus("No se pudieron consultar las versiones publicadas y sus borradores.","error");
      return;
    }

    (versionResult.data||[]).forEach(version=>{
      const bucket=versionsByDefinition.get(version.definition_id)||[];
      bucket.push(version);
      versionsByDefinition.set(version.definition_id,bucket);
    });
    (draftResult.data||[]).forEach(draft=>revisionDraftByDefinition.set(draft.definition_id,draft));
  }

  const publishedRows=rows.filter(row=>latestVersion(row));
  list.replaceChildren();
  if(!publishedRows.length){
    list.append(emptyState());
    setStatus("No hay recetas publicadas en tu ámbito.");
    return;
  }

  publishedRows.forEach(row=>list.append(card(row)));
  const withDraft=publishedRows.filter(row=>revisionDraftByDefinition.has(row.id)).length;
  setStatus(
    publishedRows.length+" flujo"+(publishedRows.length===1?"":"s")+" publicado"+(publishedRows.length===1?"":"s")
    +(withDraft?" · "+withDraft+" con nueva versión en borrador.":".")
  );
}

load();
