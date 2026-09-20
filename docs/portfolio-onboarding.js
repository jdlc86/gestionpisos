import { supabase } from "./supabase-client.js";

const $=id=>document.getElementById(id);
let ownerSubmitDecision=null;
let refreshTimer=null;
let refreshRunning=false;
let lastOrganizationId=null;
let editingExternalContext=null;
let externalEmailChangeBypass=false;

function normalizeEmail(value){return String(value||"").trim().toLowerCase();}
function showEditorEmailError(message){
  const error=$("editorError");
  if(error){error.textContent=message;error.hidden=false;}
  setPortfolioStatus(message,"Cambio de email bloqueado.");
}
function resumeEditorSubmit(){
  const form=$("editorForm");if(!form)return;
  externalEmailChangeBypass=true;
  form.requestSubmit();
  queueMicrotask(()=>{externalEmailChangeBypass=false;});
}

function activeView(){return document.querySelector(".segment.is-active")?.dataset.view||"owners";}
async function effectiveOrganizationId(){
  const selected=$("organizationSelect")?.value;
  if(selected)return selected;
  const {data}=await supabase.auth.getUser();
  return data?.user?.app_metadata?.organization_id||null;
}
function setPortfolioStatus(text,strong="Bienvenida"){
  const status=$("portfolioStatus");if(!status)return;
  status.replaceChildren();const s=document.createElement("strong");s.textContent=strong;status.append(s,document.createTextNode(" "+text));
}
function ensureOwnerWelcomeDialog(){
  let dialog=$("ownerWelcomeDialog");if(dialog)return dialog;
  dialog=document.createElement("dialog");dialog.id="ownerWelcomeDialog";
  dialog.innerHTML=`<section class="editor"><div class="editor-head"><div><p class="eyebrow">CONFIRMAR ALTA</p><h3>Bienvenida del propietario</h3></div></div><p id="ownerWelcomeText"></p><dl class="confirmation-summary"><div><dt>Propietario</dt><dd id="ownerWelcomeName"></dd></div><div><dt>Email</dt><dd id="ownerWelcomeEmail"></dd></div></dl><p class="muted small">Puedes guardar la ficha sin crear acceso todavía. Si envías la bienvenida, el propietario creará su propia contraseña.</p><div class="editor-actions welcome-actions"><button id="ownerWelcomeCancel" type="button" class="ghost">Cancelar</button><button id="ownerWelcomeSave" type="button" class="ghost">Guardar sin enviar</button><button id="ownerWelcomeSend" type="button" class="primary">Guardar y enviar bienvenida</button></div></section>`;
  document.body.appendChild(dialog);
  $("ownerWelcomeCancel").addEventListener("click",()=>{ownerSubmitDecision=null;dialog.close();});
  $("ownerWelcomeSave").addEventListener("click",()=>continueOwnerSave(false));
  $("ownerWelcomeSend").addEventListener("click",()=>continueOwnerSave(true));
  return dialog;
}

let pendingOwnerCreate=null;
function continueOwnerSave(send){
  const dialog=$("ownerWelcomeDialog");
  ownerSubmitDecision=send?"send":"save";
  dialog?.close();
  const snapshot=pendingOwnerCreate;
  $("editorForm")?.requestSubmit();
  if(send&&snapshot)pollOwnerAndSend(snapshot);
  queueMicrotask(()=>{ownerSubmitDecision=null;pendingOwnerCreate=null;});
}

document.addEventListener("submit",event=>{
  if(event.target!==$("editorForm"))return;
  if(activeView()!=="owners")return;
  if(!$("editorTitle")?.textContent?.startsWith("Nuevo"))return;
  if(ownerSubmitDecision)return;
  const form=event.target;
  const email=String(form.elements.namedItem("email")?.value||"").trim().toLowerCase();
  if(!email)return;
  event.preventDefault();event.stopImmediatePropagation();
  const name=String(form.elements.namedItem("fullName")?.value||"").trim();
  pendingOwnerCreate={email,name,startedAt:new Date(Date.now()-5000).toISOString()};
  const dialog=ensureOwnerWelcomeDialog();
  $("ownerWelcomeName").textContent=name;
  $("ownerWelcomeEmail").textContent=email;
  $("ownerWelcomeText").textContent=`Vas a dar de alta a ${name}. El acceso solo se creará si eliges enviar la bienvenida.`;
  dialog.showModal();
},true);

document.addEventListener("click",event=>{
  const target=event.target.closest("button");
  if(!target)return;
  if(target.id==="newItemBtn"){editingExternalContext=null;return;}
  if(target.dataset.action!=="edit")return;
  const view=activeView();
  if(view==="owners")editingExternalContext={subjectType:"owner",recordId:target.dataset.id};
  else if(view==="occupancies")editingExternalContext={subjectType:"tenant",occupancyId:target.dataset.id};
  else editingExternalContext=null;
},true);

async function resolveEditingExternalSubject(){
  const context=editingExternalContext;
  if(!context)return null;
  if(context.subjectType==="owner"){
    const {data,error}=await supabase.from("owners").select("id,organization_id,email,status,archived_at").eq("id",context.recordId).maybeSingle();
    if(error)throw error;
    if(!data)return null;
    return {subjectType:"owner",subjectId:String(data.id),organizationId:String(data.organization_id),currentEmail:normalizeEmail(data.email)};
  }
  const {data:occupancy,error:occupancyError}=await supabase.from("occupancies_v2").select("tenant_id,organization_id").eq("id",context.occupancyId).maybeSingle();
  if(occupancyError)throw occupancyError;
  if(!occupancy?.tenant_id)return null;
  const {data:tenant,error:tenantError}=await supabase.from("tenants_v2").select("id,organization_id,email,status,archived_at").eq("id",occupancy.tenant_id).maybeSingle();
  if(tenantError)throw tenantError;
  if(!tenant)return null;
  return {subjectType:"tenant",subjectId:String(tenant.id),organizationId:String(tenant.organization_id||occupancy.organization_id),currentEmail:normalizeEmail(tenant.email)};
}

async function currentOnboardingForSubject(subject){
  const {data,error}=await supabase.rpc("get_external_onboarding_statuses",{p_organization_id:subject.organizationId});
  if(error)throw error;
  const rows=Array.isArray(data)?data:[];
  return rows.find(row=>row.subject_type===subject.subjectType&&String(row.subject_id)===subject.subjectId)||null;
}

async function revokeInvitationForEmailChange(subject,newEmail){
  const {data,error}=await supabase.functions.invoke("revoke-external-welcome",{body:{subject_type:subject.subjectType,subject_id:subject.subjectId,new_email:newEmail}});
  if(error)throw error;
  if(data?.ok!==true)throw new Error("external_onboarding_revoke_failed");
  scheduleRefresh(250);
  return data;
}

document.addEventListener("submit",async event=>{
  if(event.target!==$("editorForm"))return;
  if(externalEmailChangeBypass||!editingExternalContext)return;
  if(!$("editorTitle")?.textContent?.startsWith("Editar"))return;
  const view=activeView();
  if(!["owners","occupancies"].includes(view))return;
  event.preventDefault();
  event.stopImmediatePropagation();
  const form=event.target;
  const newEmail=normalizeEmail(form.elements.namedItem("email")?.value);
  try{
    const subject=await resolveEditingExternalSubject();
    if(!subject){showEditorEmailError("No se pudo comprobar la identidad asociada antes de guardar.");return;}
    if(subject.currentEmail===newEmail){resumeEditorSubmit();return;}
    const onboarding=await currentOnboardingForSubject(subject);
    if(!onboarding){resumeEditorSubmit();return;}
    if(typeof onboarding.email!=="string"){
      showEditorEmailError("La protección del cambio de email todavía no está disponible en esta sesión. Actualiza la aplicación y vuelve a intentarlo.");
      return;
    }
    const onboardingEmail=normalizeEmail(onboarding.email);
    if(newEmail===onboardingEmail){resumeEditorSubmit();return;}
    if(onboarding.status==="active"){
      showEditorEmailError("Este acceso ya está activado. Para cambiar su email hace falta un flujo específico de cambio de cuenta; no se modificó la ficha.");
      return;
    }
    if(onboarding.status!=="pending"){resumeEditorSubmit();return;}
    const destination=newEmail||"sin email";
    const confirmed=window.confirm("Cambiar el email invalidará la invitación enviada a "+onboardingEmail+". El enlace anterior dejará de ser válido y "+destination+" quedará sin invitación hasta que envíes una nueva bienvenida. ¿Continuar?");
    if(!confirmed)return;
    await revokeInvitationForEmailChange(subject,newEmail);
    setPortfolioStatus("La invitación anterior quedó revocada. Guardando el nuevo email; después podrás enviar una nueva bienvenida.","Invitación invalidada.");
    resumeEditorSubmit();
  }catch(error){
    const code=await functionErrorCode(error);
    console.error("external_email_change_guard_failed",error);
    showEditorEmailError(friendlyWelcomeError(code||"external_onboarding_revoke_failed"));
  }
},true);

async function functionErrorCode(error){
  try{if(error?.context instanceof Response){const body=await error.context.clone().json();return String(body?.error||"");}}catch{}
  return String(error?.message||"");
}
function friendlyWelcomeError(code){
  if(code.includes("email_internal_identity_conflict"))return "Ese email ya está vinculado a un empleado o administrador. No se ha mezclado ninguna identidad.";
  if(code.includes("email_external_identity_conflict"))return "Ese email ya está vinculado a otro propietario o inquilino. No se ha mezclado ninguna identidad.";
  if(code.includes("email_auth_identity_conflict"))return "Ese email ya pertenece a otra cuenta de acceso. Revisa la identidad antes de continuar.";
  if(code.includes("external_account_already_active"))return "La cuenta ya está activada; no necesita otra invitación de alta.";
  if(code.includes("owner_email_required"))return "Añade un email al propietario antes de enviar la bienvenida.";
  if(code.includes("tenant_not_active"))return "El inquilino debe estar en estado Alta antes de enviar la bienvenida.";
  if(code.includes("invitation_cooldown"))return "La invitación se acaba de solicitar. Espera aproximadamente un minuto antes de reenviarla.";
  if(code.includes("external_welcome_permission_required"))return "Tu usuario no tiene permiso para enviar esta bienvenida.";
  if(code.includes("external_active_account_email_change_requires_account_flow"))return "Ese acceso ya está activado. El email de acceso no puede cambiarse desde la ficha; necesita un flujo específico de cambio de cuenta.";
  if(code.includes("external_onboarding_revoke_failed")||code.includes("external_stale_onboarding_revoke_failed"))return "No se pudo invalidar de forma segura la invitación anterior. El email no se ha cambiado.";
  return "No se pudo enviar la bienvenida. La ficha no se ha cruzado con ninguna otra identidad.";
}

async function sendWelcome(subjectType,subjectId,button=null){
  if(button)button.disabled=true;
  try{
    const {data,error}=await supabase.functions.invoke("send-external-welcome",{body:{subject_type:subjectType,subject_id:subjectId}});
    if(error)throw error;
    const status=data?.invitation_status;
    if(data?.restored_identity===true)setPortfolioStatus("La identidad existente quedó reactivada. El inquilino puede volver a entrar con su cuenta anterior.","Acceso reactivado.");
    else if(status==="sent")setPortfolioStatus("Correo de bienvenida enviado. La cuenta seguirá pendiente hasta que el usuario cree su contraseña.","Invitación enviada.");
    else if(status==="not_configured")setPortfolioStatus("La identidad quedó preparada, pero el proveedor profesional de correo todavía no está configurado. Podrás reenviar la invitación después.","Correo pendiente.");
    else if(status==="failed")setPortfolioStatus("La identidad quedó preparada, pero el proveedor de correo no confirmó el envío. Usa Reenviar bienvenida cuando se resuelva.","Envío no confirmado.");
    else setPortfolioStatus("La invitación está preparada.","Bienvenida.");
    scheduleRefresh(250);
    return data;
  }catch(error){
    const code=await functionErrorCode(error);
    setPortfolioStatus(friendlyWelcomeError(code),"Bienvenida no enviada.");
    scheduleRefresh(250);
    throw error;
  }finally{if(button)button.disabled=false;}
}

async function pollOwnerAndSend(snapshot){
  for(let attempt=0;attempt<25;attempt++){
    const org=await effectiveOrganizationId();
    if(org){
      const {data}=await supabase.from("owners").select("id,created_at,status").eq("organization_id",org).eq("email",snapshot.email).eq("full_name",snapshot.name).eq("status","active").gte("created_at",snapshot.startedAt).order("created_at",{ascending:false}).limit(1);
      if(data?.[0]){await sendWelcome("owner",data[0].id).catch(()=>{});return;}
    }
    await new Promise(resolve=>setTimeout(resolve,300));
  }
  setPortfolioStatus("La ficha se guardó, pero no se pudo identificar de forma segura el alta para enviar la bienvenida. Usa el botón Enviar bienvenida de la tarjeta.","Alta guardada.");
}

async function pollTenantAndSend(snapshot){
  for(let attempt=0;attempt<30;attempt++){
    const org=await effectiveOrganizationId();
    if(org){
      const {data}=await supabase.from("tenants_v2").select("id,status").eq("organization_id",org).eq("email",snapshot.email).eq("document_type",snapshot.documentType).eq("document_number",snapshot.documentNumber).eq("status","active").limit(1);
      if(data?.[0]){await sendWelcome("tenant",data[0].id).catch(()=>{});return;}
    }
    await new Promise(resolve=>setTimeout(resolve,300));
  }
  setPortfolioStatus("El alta se guardó, pero no se pudo preparar la bienvenida automáticamente. Usa el botón Enviar bienvenida de la tarjeta.","Alta guardada.");
}

document.addEventListener("click",event=>{
  const target=event.target.closest("button");
  if(!target)return;
  if(target.id==="welcomeSendBtn"){
    const form=$("editorForm");
    const email=String(form?.elements.namedItem("email")?.value||"").trim().toLowerCase();
    const documentType=String(form?.elements.namedItem("documentType")?.value||"").trim();
    const documentNumber=String(form?.elements.namedItem("documentNumber")?.value||"").trim().toUpperCase();
    if(email&&documentType&&documentNumber)pollTenantAndSend({email,documentType,documentNumber});
    return;
  }
  const action=target.dataset.externalWelcome;
  if(action){event.preventDefault();event.stopPropagation();sendWelcome(target.dataset.subjectType,target.dataset.subjectId,target).catch(()=>{});}
},true);

function onboardingBadge(row,currentEmail){
  if(!row)return {label:"Sin invitación",button:"Enviar bienvenida"};
  if(row.status==="pending"){
    if(typeof row.email==="string"&&normalizeEmail(row.email)!==normalizeEmail(currentEmail)){
      return {label:"Email cambiado · nueva invitación necesaria",button:"Enviar nueva bienvenida"};
    }
    const delivery=row.last_delivery_status;
    return {
      label:delivery==="sent"?"Pendiente de activación":delivery==="not_configured"?"Correo pendiente":delivery==="failed"?"Envío no confirmado":"Invitación pendiente",
      button:"Reenviar bienvenida"
    };
  }
  return {label:"Acceso activado",button:null};
}
function decorateCard(card,subjectType,subjectId,row,currentEmail,canSend=true){
  card.querySelectorAll("[data-external-onboarding-ui]").forEach(element=>element.remove());
  const meta=card.querySelector(".record-meta");
  const actions=card.querySelector(".record-actions");
  if(!meta||!actions)return;
  const state=onboardingBadge(row,currentEmail);
  const badge=document.createElement("span");badge.className="relation-chip";badge.dataset.externalOnboardingUi="1";badge.textContent=`Acceso: ${state.label}`;meta.appendChild(badge);
  if(state.button&&canSend){const button=document.createElement("button");button.type="button";button.className="secondary";button.dataset.externalOnboardingUi="1";button.dataset.externalWelcome="1";button.dataset.subjectType=subjectType;button.dataset.subjectId=subjectId;button.textContent=state.button;actions.appendChild(button);}
}

async function refreshExternalOnboarding(){
  if(refreshRunning)return;refreshRunning=true;
  try{
    const view=activeView();if(!["owners","occupancies"].includes(view))return;
    const org=await effectiveOrganizationId();if(!org)return;lastOrganizationId=org;
    const {data:statuses,error:statusError}=await supabase.rpc("get_external_onboarding_statuses",{p_organization_id:org});
    if(statusError)return;
    const rows=Array.isArray(statuses)?statuses:[];
    const statusByKey=new Map(rows.map(row=>[`${row.subject_type}:${row.subject_id}`,row]));
    const cards=[...document.querySelectorAll("#records .record-card")];
    if(view==="owners"){
      for(const card of cards){const id=card.querySelector('button[data-action="edit"]')?.dataset.id;if(!id)continue;const text=card.querySelector("p")?.textContent||"";const email=text.split(" · ")[0].trim();decorateCard(card,"owner",id,statusByKey.get(`owner:${id}`),email,email.includes("@"));}
    }else{
      const occupancyIds=cards.map(card=>card.querySelector('button[data-action="edit"]')?.dataset.id).filter(Boolean);
      if(!occupancyIds.length)return;
      const {data:occupancies}=await supabase.from("occupancies_v2").select("id,tenant_id,status").in("id",occupancyIds);
      const byOccupancy=new Map((occupancies||[]).map(row=>[row.id,row]));
      for(const card of cards){const id=card.querySelector('button[data-action="edit"]')?.dataset.id;const oc=byOccupancy.get(id);if(!oc?.tenant_id)continue;const text=card.querySelector("p")?.textContent||"";const email=text.split(" · ")[0].trim();decorateCard(card,"tenant",oc.tenant_id,statusByKey.get(`tenant:${oc.tenant_id}`),email,oc.status==="active");}
    }
  }finally{refreshRunning=false;}
}
function scheduleRefresh(delay=100){clearTimeout(refreshTimer);refreshTimer=setTimeout(refreshExternalOnboarding,delay);}

document.addEventListener("gestionpisos:portfolio-rendered",()=>scheduleRefresh(0));
document.querySelectorAll(".segment").forEach(button=>button.addEventListener("click",()=>scheduleRefresh(100)));
$("organizationSelect")?.addEventListener("change",()=>scheduleRefresh(200));
scheduleRefresh(700);
