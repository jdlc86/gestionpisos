import { supabase } from "./supabase-client.js";

const esc=(v)=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const personName=(p)=>p?.display_name||p?.email||"Usuario sin nombre";
const roles=(p)=>Array.isArray(p?.roles)?p.roles:[];
const NOTICE_KEY="permissions-responsibility-flow-notice";
let flowBusy=false;

function ensureDialog(){
  let root=document.getElementById("responsibilityFlow");
  if(root)return root;
  root=document.createElement("div");
  root.id="responsibilityFlow";
  root.className="responsibility-flow";
  root.hidden=true;
  root.innerHTML=`<div class="responsibility-flow-backdrop" data-responsibility-close></div><section class="responsibility-flow-card" role="dialog" aria-modal="true" aria-labelledby="responsibilityFlowTitle"><h3 id="responsibilityFlowTitle"></h3><p id="responsibilityFlowSummary" class="responsibility-flow-summary"></p><div id="responsibilityFlowBody"></div><div id="responsibilityFlowActions" class="responsibility-flow-actions"></div></section>`;
  document.body.appendChild(root);
  root.addEventListener("click",(event)=>{if(event.target.closest("[data-responsibility-close]")&&!flowBusy)closeDialog();});
  return root;
}

function closeDialog(){
  const root=document.getElementById("responsibilityFlow");
  if(!root)return;
  root.hidden=true;
  document.getElementById("responsibilityFlowBody").innerHTML="";
  document.getElementById("responsibilityFlowActions").innerHTML="";
}

function openDialog({title,summary,bodyHtml="",actions=[]}){
  const root=ensureDialog();
  document.getElementById("responsibilityFlowTitle").textContent=title;
  document.getElementById("responsibilityFlowSummary").textContent=summary;
  document.getElementById("responsibilityFlowBody").innerHTML=bodyHtml;
  const actionBox=document.getElementById("responsibilityFlowActions");
  actionBox.innerHTML="";
  for(const action of actions){
    const button=document.createElement("button");
    button.type="button";
    button.textContent=action.label;
    button.className=action.className||"ghost";
    button.disabled=action.disabled===true;
    button.addEventListener("click",action.onClick);
    actionBox.appendChild(button);
  }
  root.hidden=false;
}

function setDialogBusy(isBusy,label="Guardando…"){
  flowBusy=isBusy;
  document.querySelectorAll("#responsibilityFlowActions button").forEach(button=>{
    button.disabled=isBusy;
    if(isBusy&&button.classList.contains("primary"))button.dataset.previousLabel=button.textContent;
    if(isBusy&&button.classList.contains("primary"))button.textContent=label;
    if(!isBusy&&button.dataset.previousLabel){button.textContent=button.dataset.previousLabel;delete button.dataset.previousLabel;}
  });
}

function setPageError(message){
  const error=document.getElementById("permissionError");
  if(error){error.hidden=false;error.textContent=message;}
}

function storeNotice(type,message){
  sessionStorage.setItem(NOTICE_KEY,JSON.stringify({type,message}));
}

function restoreNotice(){
  const raw=sessionStorage.getItem(NOTICE_KEY);
  if(!raw)return;
  let notice;
  try{notice=JSON.parse(raw);}catch{return sessionStorage.removeItem(NOTICE_KEY);}
  let attempts=0;
  const timer=setInterval(()=>{
    attempts+=1;
    const status=document.getElementById("permissionStatus");
    const ready=status?.textContent?.includes("Contexto cargado")||attempts>=35;
    if(!ready)return;
    clearInterval(timer);
    sessionStorage.removeItem(NOTICE_KEY);
    if(notice.type==="warning")setPageError(notice.message);
    if(status)status.innerHTML=notice.type==="warning"?"<strong>Usuario desactivado con advertencia.</strong> Revisa el aviso superior.":`<strong>Operación completada.</strong> ${esc(notice.message)}`;
  },300);
}

async function getContext(){
  const {data:organizationId,error:organizationError}=await supabase.rpc("get_effective_organization_id");
  if(organizationError)throw organizationError;
  if(!organizationId)throw new Error("organization_missing");
  const {data,error}=await supabase.rpc("get_permission_management_context",{p_organization_id:organizationId});
  if(error)throw error;
  return {organizationId,data};
}

async function disableInternalStaffAuth(userId){
  const {data,error}=await supabase.functions.invoke("disable-internal-staff-auth",{body:{target_user_id:userId}});
  if(error)throw error;
  if(!data?.ok)throw new Error(data?.error||"auth_disable_failed");
  return data;
}

function enhanceResponsibleSelects(){
  document.querySelectorAll('select[id^="responsible-"]').forEach(select=>{
    if(select.dataset.unassignedEnhanced==="1")return;
    const explicit=[...select.options].find(option=>option.hasAttribute("selected"));
    const current=explicit?.value||"";
    const option=document.createElement("option");
    option.value="";
    option.textContent="NO ASIGNADO";
    select.prepend(option);
    select.dataset.currentResponsible=current;
    select.dataset.unassignedEnhanced="1";
    if(!current)select.value="";
  });
}

function watchResponsibleSelects(){
  enhanceResponsibleSelects();
  const target=document.getElementById("propertiesList")||document.body;
  new MutationObserver(()=>enhanceResponsibleSelects()).observe(target,{childList:true,subtree:true});
}

function propertyNameFromButton(button){
  return button.closest(".property-responsible-item")?.querySelector("strong")?.textContent?.trim()||"esta vivienda";
}

async function unassignProperty(button,select){
  if((select.dataset.currentResponsible||"")==="")return;
  const propertyId=button.dataset.propertyId;
  const propertyName=propertyNameFromButton(button);
  openDialog({
    title:"Dejar vivienda sin responsable",
    summary:`${propertyName} quedará temporalmente como NO ASIGNADO. La vivienda y su historial se conservan.`,
    actions:[
      {label:"Cancelar",className:"ghost",onClick:()=>closeDialog()},
      {label:"Dejar sin asignar",className:"primary",onClick:async()=>{
        setDialogBusy(true,"Guardando…");
        try{
          const {error}=await supabase.rpc("assign_property_responsible_v3",{p_property_id:propertyId,p_employee_user_id:null});
          if(error)throw error;
          storeNotice("success",`${propertyName} ha quedado sin responsable.`);
          window.location.reload();
        }catch(error){
          setDialogBusy(false);
          setPageError(`No se pudo dejar la vivienda sin responsable. ${String(error?.message||"").slice(0,140)}`);
        }
      }}
    ]
  });
}

function responsibilitiesSummary(name,properties){
  const count=properties.length;
  if(count===1)return `${name} es responsable de ${properties[0]?.name||"1 vivienda"}. Elige qué ocurrirá con esa responsabilidad antes de eliminar el usuario.`;
  if(count<=3){
    const names=properties.map(p=>p.name||"Vivienda").join(", ");
    return `${name} es responsable de ${count} viviendas: ${names}. Elige qué ocurrirá con ellas antes de eliminar el usuario.`;
  }
  return `${name} es responsable de ${count} viviendas. Elige qué ocurrirá con esas responsabilidades antes de eliminar el usuario.`;
}

function responsibilityDetails(properties){
  if(properties.length<=3)return "";
  return `<details><summary>Ver viviendas (${properties.length})</summary><ul>${properties.map(property=>`<li>${esc(property.name||"Vivienda")}</li>`).join("")}</ul></details>`;
}

async function removeResponsibleStaff(targetId){
  if(flowBusy)return;
  flowBusy=true;
  try{
    const {organizationId,data}=await getContext();
    const people=data?.people||[];
    const target=people.find(person=>person.user_id===targetId);
    if(!target)throw new Error("target_not_found");
    const name=personName(target);
    const writeHolder=(data?.capability_holders||[]).find(holder=>holder.capability==="write_control");
    if(writeHolder?.holder_user_id===targetId){
      flowBusy=false;
      openDialog({title:"No se puede eliminar todavía",summary:`${name} tiene el control administrativo. Primero transfiere o revoca ese control desde Supervisión ROOT.`,actions:[{label:"Cerrar",className:"primary",onClick:()=>closeDialog()}]});
      return;
    }

    const properties=(data?.properties||[]).filter(property=>property.responsible_user_id===targetId);
    if(!properties.length){
      flowBusy=false;
      window.location.reload();
      return;
    }
    const accessCount=(data?.properties||[]).reduce((total,property)=>total+(property.staff_access||[]).filter(access=>access.employee_user_id===targetId).length,0);
    const candidates=people.filter(person=>person.user_id!==targetId&&roles(person).some(role=>role==="employee"||role==="admin"));
    const selectHtml=candidates.length?`<div class="responsibility-flow-field"><label for="responsibilityReplacement">Nuevo responsable para todas</label><select id="responsibilityReplacement">${candidates.map(person=>`<option value="${esc(person.user_id)}">${esc(personName(person))}</option>`).join("")}</select></div>`:`<span class="responsibility-flow-note">No hay otro empleado o administrador activo disponible para una reasignación masiva.</span>`;
    const accessNote=accessCount?`<span class="responsibility-flow-note">Además tiene ${accessCount} acceso${accessCount===1?"":"s"} adicional${accessCount===1?"":"es"}; se revocará${accessCount===1?"":"n"} automáticamente al eliminarlo.</span>`:"";
    const bodyHtml=`${responsibilityDetails(properties)}${accessNote}${selectHtml}<span class="responsibility-flow-note">La decisión se aplicará a todas estas viviendas y, en la misma operación de base de datos, se desactivará al usuario.</span>`;

    const executeRemoval=async(mode,replacementUserId=null)=>{
      setDialogBusy(true,mode==="reassign"?"Reasignando…":"Eliminando…");
      try{
        const {data:result,error}=await supabase.rpc("deactivate_internal_staff_user_v2",{
          p_organization_id:organizationId,
          p_target_user_id:targetId,
          p_responsibility_mode:mode,
          p_replacement_user_id:replacementUserId
        });
        if(error)throw error;
        let authDisabled=true;
        try{await disableInternalStaffAuth(targetId);}catch{authDisabled=false;}
        if(authDisabled){
          const resolved=Number(result?.resolved_responsibilities||properties.length);
          storeNotice("success",`${name} ha sido eliminado. Se resolvieron ${resolved} responsabilidad${resolved===1?"":"es"} de vivienda.`);
        }else{
          storeNotice("warning",`${name} perdió sus permisos y responsabilidades, pero no se pudo bloquear su cuenta de autenticación. Revisa el backend antes de considerarlo completamente cerrado.`);
        }
        window.location.reload();
      }catch(error){
        setDialogBusy(false);
        setPageError(`No se pudo completar la eliminación. ${String(error?.message||"").slice(0,160)}`);
      }
    };

    flowBusy=false;
    openDialog({
      title:`Antes de eliminar a ${name}`,
      summary:responsibilitiesSummary(name,properties),
      bodyHtml,
      actions:[
        {label:"Cancelar",className:"ghost",onClick:()=>closeDialog()},
        {label:"Dejar sin asignar",className:"ghost danger-action",onClick:()=>executeRemoval("unassign",null)},
        ...(candidates.length?[{label:"Reasignar y eliminar",className:"primary",onClick:()=>{
          const replacement=document.getElementById("responsibilityReplacement")?.value;
          if(replacement)executeRemoval("reassign",replacement);
        }}]:[])
      ]
    });
  }catch(error){
    flowBusy=false;
    setPageError(`No se pudo preparar la eliminación. ${String(error?.message||"").slice(0,160)}`);
  }
}

document.addEventListener("click",event=>{
  const assignButton=event.target.closest(".assign-responsible");
  if(assignButton){
    const select=document.getElementById(`responsible-${assignButton.dataset.propertyId}`);
    if(select?.value===""){
      event.preventDefault();
      event.stopImmediatePropagation();
      unassignProperty(assignButton,select);
      return;
    }
  }

  const removeButton=event.target.closest(".remove-staff");
  if(!removeButton)return;
  const targetId=removeButton.dataset.userId;
  const isResponsible=[...document.querySelectorAll('select[id^="responsible-"]')].some(select=>select.value===targetId);
  if(!isResponsible)return;
  event.preventDefault();
  event.stopImmediatePropagation();
  removeResponsibleStaff(targetId);
},true);

watchResponsibleSelects();
restoreNotice();
