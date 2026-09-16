window.__permissionsBooted=true;
import { supabase, getCurrentSession } from "./supabase-client.js";
const $=(id)=>document.getElementById(id); const esc=(v)=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const personName=(p)=>p?.display_name||p?.email||"Usuario sin nombre"; const roles=(p)=>Array.isArray(p?.roles)?p.roles:[];
const card=(title,meta="",badge="")=>`<article class="permission-item"><div><strong>${esc(title)}</strong>${meta?`<span>${esc(meta)}</span>`:""}</div>${badge?`<em>${esc(badge)}</em>`:""}</article>`;
const staffCard=(p,badge,canRemove)=>`<article class="permission-item"><div><strong>${esc(personName(p))}</strong>${p?.email?`<span>${esc(p.email)}</span>`:""}</div><div class="staff-card-actions"><em>${esc(badge)}</em>${canRemove?`<button class="ghost remove-staff" type="button" data-user-id="${esc(p.user_id)}">Eliminar</button>`:""}</div></article>`;
let ctx=null,busy=false;
async function createOrganizationUser(payload){const {data,error}=await supabase.functions.invoke("create-organization-user",{body:payload});if(error)throw error;return data;}
async function disableInternalStaffAuth(userId){const {data,error}=await supabase.functions.invoke("disable-internal-staff-auth",{body:{target_user_id:userId}});if(error)throw error;if(!data?.ok)throw new Error(data?.error||"auth_disable_failed");return data;}
function modal(title,text,confirmLabel,onConfirm){$("permissionModalTitle").textContent=title;$("permissionModalText").textContent=text;const confirm=$("permissionModalConfirm");confirm.textContent=confirmLabel;confirm.disabled=false;confirm.onclick=async()=>{if(confirm.disabled)return;confirm.disabled=true;confirm.textContent="Guardando…";try{await onConfirm();closeModal();}catch(e){confirm.disabled=false;confirm.textContent=confirmLabel;}};$("permissionModal").hidden=false;}
function closeModal(){$("permissionModal").hidden=true;$("permissionModalConfirm").onclick=null;}
document.querySelectorAll("[data-modal-close]").forEach(el=>el.addEventListener("click",closeModal));
$("createUserForm")?.addEventListener("submit",async(e)=>{e.preventDefault();if(busy)return;const name=$("newUserName").value.trim(),email=$("newUserEmail").value.trim(),role=$("newUserRole").value;if(!name||!email)return;modal("Crear usuario",`Se creará ${name} (${email}) con rol ${role} dentro de esta organización.`,`Crear`,async()=>{busy=true;const button=$("createUserButton");button.disabled=true;$("createUserNote").textContent="Creando usuario…";try{await createOrganizationUser({display_name:name,email,role});$("createUserForm").reset();$("createUserNote").textContent="Usuario creado correctamente.";await load();}catch(err){$("createUserNote").textContent="No se pudo crear el usuario.";$("permissionError").textContent=err?.message||"No se pudo crear el usuario.";$("permissionError").hidden=false;}finally{busy=false;button.disabled=false;}});});
async function rpc(name,args,statusText="Guardando cambios…",reloadAfter=true){if(busy)throw new Error("operation_in_progress");busy=true;$("permissionStatus").innerHTML=`<strong>${esc(statusText)}</strong> Espera un momento.`;$("permissionError").hidden=true;try{const {data,error}=await supabase.rpc(name,args);if(error)throw error;if(reloadAfter)await load();return data;}catch(e){const code=String(e?.code||"").replace(/[^A-Za-z0-9_.-]/g,"").slice(0,48),message=String(e?.message||"La operación no pudo completarse.").split("\\n").join(" ").slice(0,160);$("permissionError").textContent=`No se pudo guardar el cambio.${code?` Diagnóstico: ${code} · ${message}`:` ${message}`}`;$("permissionError").hidden=false;$("permissionStatus").innerHTML="<strong>Cambio no guardado.</strong> La configuración conserva su estado anterior.";throw e;}finally{busy=false;}}
function render(data){ctx=data;
const people=data?.people||[],byId=new Map(people.map(p=>[p.user_id,p])),admins=people.filter(p=>roles(p).includes("admin")),employees=people.filter(p=>roles(p).includes("employee")),holders=data?.capability_holders||[],requests=data?.pending_requests||[],writeHolder=holders.find(h=>h.capability==="write_control"),me=data?.actor?.user_id,myRequest=requests.find(r=>r.capability==="write_control"&&r.requester_user_id===me);
const canCreate=data?.actor?.is_root||writeHolder?.holder_user_id===me,canManageStaff=canCreate;if($("createUserForm"))$("createUserForm").hidden=!canCreate;if($("createUserNote")&&!canCreate)$("createUserNote").textContent="Solo ROOT o el administrador titular del control administrativo puede crear usuarios.";
$("adminsList").innerHTML=admins.length?admins.map(p=>staffCard(p,p.user_id===writeHolder?.holder_user_id?"Control administrativo":"Admin",canManageStaff&&p.user_id!==me)).join(""):card("Sin administradores","No hay administradores activos.");
$("employeesList").innerHTML=employees.length?employees.map(p=>staffCard(p,"Empleado",canManageStaff&&p.user_id!==me)).join(""):card("Sin empleados","No hay empleados activos.");
const canAssignResponsible=data?.actor?.is_root||writeHolder?.holder_user_id===me;
const eligible=people.filter(p=>roles(p).some(r=>r==="employee"||r==="admin"));
$("propertiesList").innerHTML=(data?.properties||[]).length?data.properties.map(p=>{
 const current=p.responsible_user_id?personName(byId.get(p.responsible_user_id)):"Sin responsable";
 const accessRows=(p.staff_access||[]).map(a=>`<div class="staff-access-row"><span><strong>${esc(personName(byId.get(a.employee_user_id)))}</strong> · ${a.can_write?"Lectura y escritura":"Solo lectura"}</span>${canAssignResponsible?`<button class="ghost revoke-staff-access" type="button" data-property-id="${esc(p.id)}" data-user-id="${esc(a.employee_user_id)}">Revocar</button>`:""}</div>`).join("");
 const accessCandidates=eligible.filter(person=>person.user_id!==p.responsible_user_id&&!(p.staff_access||[]).some(a=>a.employee_user_id===person.user_id));
 const accessControls=canAssignResponsible&&accessCandidates.length?`<div class="staff-access-add"><select id="staff-${esc(p.id)}">${accessCandidates.map(person=>`<option value="${esc(person.user_id)}">${esc(personName(person))}</option>`).join("")}</select><label><input id="staff-write-${esc(p.id)}" type="checkbox"> Permitir escritura</label><button class="ghost grant-staff-access" type="button" data-property-id="${esc(p.id)}">Dar acceso</button></div>`:"";
 const controls=canAssignResponsible&&eligible.length?`<div class="responsible-controls"><label for="responsible-${esc(p.id)}">Responsable</label><select id="responsible-${esc(p.id)}" data-property-id="${esc(p.id)}">${eligible.map(person=>`<option value="${esc(person.user_id)}" ${person.user_id===p.responsible_user_id?"selected":""}>${esc(personName(person))}</option>`).join("")}</select><button class="ghost assign-responsible" type="button" data-property-id="${esc(p.id)}">Cambiar responsable</button></div>`:"";
 return `<article class="permission-item property-responsible-item"><div><strong>${esc(p.name||"Vivienda")}</strong><span>${esc([p.address_line,p.city].filter(Boolean).join(" · "))}</span><em>${esc(`Responsable: ${current}`)}</em></div><div class="property-access-management">${controls}<div class="staff-access-list">${accessRows||'<span class="permission-note">Sin accesos adicionales.</span>'}</div>${accessControls}</div></article>`;
}).join(""):card("Sin viviendas","No hay viviendas activas.");
const rows=[writeHolder?card("Control administrativo de escritura",personName(byId.get(writeHolder.holder_user_id)),"Titular actual"):card("Control administrativo de escritura","No existe titular activo.","Sin titular")];requests.filter(r=>r.capability==="write_control").forEach(r=>rows.push(card("Solicitud pendiente",personName(byId.get(r.requester_user_id)),"Pendiente")));$("capabilitiesList").innerHTML=rows.join("");
const actions=[];
if(data?.actor?.is_root&&!writeHolder&&admins.length) actions.push(`<div class="permission-decision"><span><strong>Asignar primer titular</strong></span><select id="initialWriteControlAdmin">${admins.map(p=>`<option value="${esc(p.user_id)}">${esc(personName(p))}</option>`).join("")}</select><button id="assignInitialWriteControl" class="primary" type="button">Asignar control</button></div>`);
const rootTransferCandidates=admins.filter(p=>p.user_id!==writeHolder?.holder_user_id);
if(data?.actor?.is_root&&writeHolder) actions.push(`<div class="permission-decision"><span><strong>Supervisión ROOT</strong> Puedes transferir o revocar el control administrativo actual.</span>${rootTransferCandidates.length?`<select id="rootWriteControlAdmin">${rootTransferCandidates.map(p=>`<option value="${esc(p.user_id)}">${esc(personName(p))}</option>`).join("")}</select><button id="rootTransferWriteControl" class="primary" type="button">Transferir control</button>`:""}<button id="rootRevokeWriteControl" class="ghost" type="button">Revocar control</button></div>`);
if(data?.actor?.is_admin&&writeHolder?.holder_user_id!==me&&!myRequest) actions.push('<button id="requestWriteControl" class="primary" type="button">Solicitar control de escritura</button>');
if(myRequest) actions.push('<span class="permission-note">Tu solicitud está pendiente de decisión.</span>');
const pendingForDecision=requests.filter(r=>r.capability==="write_control"&&(data?.actor?.is_root||writeHolder?.holder_user_id===me));
pendingForDecision.forEach(r=>actions.push(`<div class="permission-decision"><span><strong>${esc(personName(byId.get(r.requester_user_id)))}</strong> solicita el control</span><button class="ghost reject-request" data-id="${esc(r.id)}">Rechazar</button><button class="primary accept-request" data-id="${esc(r.id)}">Aceptar</button></div>`));
$("writeControlActions").innerHTML=actions.join("");
document.querySelectorAll(".remove-staff").forEach(button=>button.addEventListener("click",()=>{
 const target=byId.get(button.dataset.userId);if(!target)return;
 const responsibleProperty=(data?.properties||[]).find(p=>p.responsible_user_id===target.user_id);
 if(target.user_id===writeHolder?.holder_user_id){modal("No se puede eliminar todavía",`${personName(target)} tiene el control administrativo. Primero transfiere o revoca ese control desde Supervisión ROOT.`,"Cerrar",async()=>{});return;}
 if(responsibleProperty){modal("Reasigna la vivienda primero",`${personName(target)} es responsable de ${responsibleProperty.name||"una vivienda"}. Cambia el responsable antes de eliminar este usuario.`,"Cerrar",async()=>{});return;}
 modal("Eliminar usuario",`${personName(target)} será desactivado como personal interno. Se revocarán sus accesos adicionales y solicitudes pendientes, pero se conservará el historial y la auditoría.`,"Eliminar",async()=>{
   const result=await rpc("deactivate_internal_staff_user",{p_organization_id:data.organization_id,p_target_user_id:target.user_id},"Eliminando usuario…",false);
   let authDisabled=true;
   try{await disableInternalStaffAuth(target.user_id);}catch(e){authDisabled=false;}
   await load();
   if(authDisabled){$("permissionStatus").innerHTML=`<strong>Usuario eliminado.</strong> ${esc(personName(target))} ya no tiene acceso como personal interno.`;}
   else{$("permissionError").hidden=false;$("permissionError").textContent="El usuario fue desactivado y perdió sus permisos, pero no se pudo bloquear su cuenta de autenticación. Revisa el backend antes de considerarlo completamente cerrado.";$("permissionStatus").innerHTML="<strong>Usuario desactivado con advertencia.</strong> Los permisos internos fueron revocados.";}
   return result;
 });
}));
document.querySelectorAll(".grant-staff-access").forEach(button=>button.addEventListener("click",()=>{
 const propertyId=button.dataset.propertyId,select=document.getElementById(`staff-${propertyId}`),target=byId.get(select?.value),canWrite=document.getElementById(`staff-write-${propertyId}`)?.checked===true;
 if(!select||!target)return;
 modal("Dar acceso a vivienda",`${personName(target)} tendrá ${canWrite?"lectura y escritura":"solo lectura"} en esta vivienda. No se convertirá en responsable.`,"Dar acceso",async()=>{const userId=select.value;$("permissionStatus").innerHTML="<strong>Confirmación recibida.</strong> Enviando acceso al servidor…";const result=await rpc("grant_property_staff_access_v3",{p_property_id:propertyId,p_employee_user_id:userId,p_can_write:canWrite},"Enviando al servidor…",false);if(!result)throw new Error("grant_returned_empty");$("permissionStatus").innerHTML="<strong>Acceso guardado.</strong> Actualizando Gestión de Permisos…";await load();return result;});
}));
document.querySelectorAll(".revoke-staff-access").forEach(button=>button.addEventListener("click",()=>{
 const target=byId.get(button.dataset.userId);
 modal("Revocar acceso a vivienda",`${personName(target)} perderá su acceso adicional a esta vivienda. Esto no modifica al responsable.`,"Revocar acceso",()=>rpc("revoke_property_staff_access_v3",{p_property_id:button.dataset.propertyId,p_employee_user_id:button.dataset.userId},"Revocando acceso…"));
}));
document.querySelectorAll(".assign-responsible").forEach(button=>button.addEventListener("click",()=>{
 const select=document.getElementById(`responsible-${button.dataset.propertyId}`);
 const property=(data?.properties||[]).find(p=>p.id===button.dataset.propertyId);
 const target=byId.get(select?.value);
 if(!select||!target||select.value===property?.responsible_user_id)return;
 modal("Cambiar responsable de vivienda",`${personName(target)} pasará a ser el único responsable activo de ${property?.name||"esta vivienda"}. El responsable anterior perderá esa asignación.`,"Cambiar responsable",()=>rpc("assign_property_responsible_v3",{p_property_id:button.dataset.propertyId,p_employee_user_id:select.value}));
}));
$("assignInitialWriteControl")?.addEventListener("click",()=>{const select=$("initialWriteControlAdmin"),target=byId.get(select?.value);if(!select||!target)return;modal("Asignar control administrativo",`${personName(target)} pasará a ser el primer administrador titular del control de escritura. ROOT conservará su autoridad de supervisión.`,"Asignar control",()=>rpc("assign_initial_admin_write_control",{p_organization_id:data.organization_id,p_admin_user_id:select.value},"Asignando control administrativo…"));});
$("rootTransferWriteControl")?.addEventListener("click",()=>{const select=$("rootWriteControlAdmin"),target=byId.get(select?.value);if(!select||!target)return;modal("Transferir control administrativo",`${personName(target)} sustituirá a ${personName(byId.get(writeHolder?.holder_user_id))} como único titular del control administrativo de escritura.`,"Transferir control",()=>rpc("root_set_admin_write_control",{p_organization_id:data.organization_id,p_admin_user_id:select.value},"Transfiriendo control administrativo…"));});
$("rootRevokeWriteControl")?.addEventListener("click",()=>modal("Revocar control administrativo",`${personName(byId.get(writeHolder?.holder_user_id))} dejará de ser titular del control administrativo. ROOT seguirá pudiendo asignar un nuevo titular.`,"Revocar control",()=>rpc("root_set_admin_write_control",{p_organization_id:data.organization_id,p_admin_user_id:null},"Revocando control administrativo…")));
$("requestWriteControl")?.addEventListener("click",()=>modal("Solicitar control de escritura",writeHolder?"El titular actual deberá aceptar o rechazar la solicitud. Hasta entonces no cambiará ningún permiso.":"No existe titular actual. ROOT podrá aceptar o rechazar la solicitud. Hasta entonces no cambiará ningún permiso.","Solicitar",()=>rpc("request_admin_write_control",{p_organization_id:data.organization_id})));
document.querySelectorAll(".accept-request").forEach(b=>b.addEventListener("click",()=>modal("Transferir control de escritura",data?.actor?.is_root?"Al aceptar, el administrador solicitante pasará a ser el único titular del control administrativo de escritura.":"Al aceptar, perderás inmediatamente el control de escritura y el administrador solicitante pasará a ser el único titular.","Aceptar transferencia",()=>rpc("decide_admin_write_control_request",{p_request_id:b.dataset.id,p_accept:true}))));
document.querySelectorAll(".reject-request").forEach(b=>b.addEventListener("click",()=>modal("Rechazar solicitud","La decisión quedará registrada y el titular actual no cambiará.","Rechazar",()=>rpc("decide_admin_write_control_request",{p_request_id:b.dataset.id,p_accept:false}))));
}
async function withTimeout(promise,ms,label){let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error(label)),ms);})]);}finally{clearTimeout(timer);}}
async function load(){
  $("permissionStatus").innerHTML="<strong>Conectando…</strong> Cargando contexto autorizado.";
  try{
    const session=await withTimeout(getCurrentSession(),8000,"session_timeout");
    if(!session) throw new Error("session_missing");
    const {data:organizationId,error:organizationError}=await withTimeout(supabase.rpc("get_effective_organization_id"),8000,"organization_timeout");
    if(organizationError) throw organizationError;
    if(!organizationId) throw new Error("organization_missing");
    const {data,error}=await withTimeout(supabase.rpc("get_permission_management_context",{p_organization_id:organizationId}),12000,"permissions_timeout");
    if(error)throw error;
    render(data);
    $("permissionContent").hidden=false;
    $("permissionError").hidden=true;
    $("permissionStatus").innerHTML="<strong>Contexto cargado.</strong> Las operaciones críticas se validan en backend.";
  }catch(e){
    const code=e?.message||"";
    const safeCode=String(e?.code||"").replace(/[^A-Za-z0-9_.-]/g,"").slice(0,48);
    const safeMessage=String(code).split("\\n").join(" ").split("\\r").join(" ").replace(/[<>]/g," ").slice(0,160);
    $("permissionContent").hidden=true;
    $("permissionError").textContent=code==="not_authorized"?"No tienes autorización para acceder a Gestión de Permisos.":code==="session_missing"?"Tu sesión no está disponible. Vuelve a Inicio e inicia sesión de nuevo.":code==="session_timeout"?"No se pudo comprobar tu sesión. Revisa la conexión e inténtalo de nuevo.":code==="permissions_timeout"?"El servidor tardó demasiado en cargar Gestión de Permisos. Inténtalo de nuevo.":"No se pudo cargar Gestión de Permisos. No se ha realizado ningún cambio.";
    if(!["not_authorized","session_missing","session_timeout","permissions_timeout"].includes(code)){
      const diagnostic=[safeCode,safeMessage].filter(Boolean).join(" · ");
      if(diagnostic) $("permissionError").textContent += " Diagnóstico: "+diagnostic;
    }
    $("permissionError").hidden=false;
    $("permissionStatus").innerHTML="<strong>Carga detenida.</strong> No se ha realizado ningún cambio.";
  }
}
load();