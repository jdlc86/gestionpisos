import { supabase, getCurrentSession } from "./supabase-client.js";
const $=(id)=>document.getElementById(id); const esc=(v)=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const personName=(p)=>p?.display_name||p?.email||"Usuario sin nombre"; const roles=(p)=>Array.isArray(p?.roles)?p.roles:[];
const card=(title,meta="",badge="")=>`<article class="permission-item"><div><strong>${esc(title)}</strong>${meta?`<span>${esc(meta)}</span>`:""}</div>${badge?`<em>${esc(badge)}</em>`:""}</article>`;
let ctx=null,busy=false;
function modal(title,text,confirmLabel,onConfirm){$("permissionModalTitle").textContent=title;$("permissionModalText").textContent=text;$("permissionModalConfirm").textContent=confirmLabel;$("permissionModalConfirm").onclick=async()=>{closeModal();await onConfirm();};$("permissionModal").hidden=false;}
function closeModal(){$("permissionModal").hidden=true;$("permissionModalConfirm").onclick=null;}
document.querySelectorAll("[data-modal-close]").forEach(el=>el.addEventListener("click",closeModal));
async function rpc(name,args){if(busy)return;busy=true;try{const {data,error}=await supabase.rpc(name,args);if(error)throw error;await load();return data;}catch(e){$("permissionError").textContent=e?.message||"La operación no pudo completarse.";$("permissionError").hidden=false;}finally{busy=false;}}
function render(data){ctx=data;const people=data?.people||[],byId=new Map(people.map(p=>[p.user_id,p])),admins=people.filter(p=>roles(p).includes("admin")),employees=people.filter(p=>roles(p).includes("employee")),holders=data?.capability_holders||[],requests=data?.pending_requests||[],writeHolder=holders.find(h=>h.capability==="write_control"),me=data?.actor?.user_id,myRequest=requests.find(r=>r.capability==="write_control"&&r.requester_user_id===me);
$("adminsList").innerHTML=admins.length?admins.map(p=>card(personName(p),p.email,p.user_id===writeHolder?.holder_user_id?"Control de escritura":"Admin")).join(""):card("Sin administradores","No hay administradores activos.");
$("employeesList").innerHTML=employees.length?employees.map(p=>card(personName(p),p.email,"Empleado")).join(""):card("Sin empleados","No hay empleados activos.");
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
const rows=[writeHolder?card("Control de escritura",personName(byId.get(writeHolder.holder_user_id)),"Titular actual"):card("Control de escritura","No existe titular activo.","Sin titular")];requests.filter(r=>r.capability==="write_control").forEach(r=>rows.push(card("Solicitud pendiente",personName(byId.get(r.requester_user_id)),"Pendiente")));$("capabilitiesList").innerHTML=rows.join("");
const actions=[];
if(data?.actor?.is_admin&&writeHolder?.holder_user_id!==me&&!myRequest) actions.push('<button id="requestWriteControl" class="primary" type="button">Solicitar control de escritura</button>');
if(myRequest) actions.push('<span class="permission-note">Tu solicitud está pendiente de decisión.</span>');
const pendingForHolder=requests.filter(r=>r.capability==="write_control"&&writeHolder?.holder_user_id===me);
pendingForHolder.forEach(r=>actions.push(`<div class="permission-decision"><span><strong>${esc(personName(byId.get(r.requester_user_id)))}</strong> solicita el control</span><button class="ghost reject-request" data-id="${esc(r.id)}">Rechazar</button><button class="primary accept-request" data-id="${esc(r.id)}">Aceptar</button></div>`));
$("writeControlActions").innerHTML=actions.join("");
document.querySelectorAll(".grant-staff-access").forEach(button=>button.addEventListener("click",()=>{
 const propertyId=button.dataset.propertyId,select=document.getElementById(`staff-${propertyId}`),target=byId.get(select?.value),canWrite=document.getElementById(`staff-write-${propertyId}`)?.checked===true;
 if(!select||!target)return;
 modal("Dar acceso a vivienda",`${personName(target)} tendrá ${canWrite?"lectura y escritura":"solo lectura"} en esta vivienda. No se convertirá en responsable.`,"Dar acceso",()=>rpc("grant_property_staff_access_v3",{p_property_id:propertyId,p_employee_user_id:select.value,p_can_write:canWrite}));
}));
document.querySelectorAll(".revoke-staff-access").forEach(button=>button.addEventListener("click",()=>{
 const target=byId.get(button.dataset.userId);
 modal("Revocar acceso a vivienda",`${personName(target)} perderá su acceso adicional a esta vivienda. Esto no modifica al responsable.`,"Revocar acceso",()=>rpc("revoke_property_staff_access_v3",{p_property_id:button.dataset.propertyId,p_employee_user_id:button.dataset.userId}));
}));
document.querySelectorAll(".assign-responsible").forEach(button=>button.addEventListener("click",()=>{
 const select=document.getElementById(`responsible-${button.dataset.propertyId}`);
 const property=(data?.properties||[]).find(p=>p.id===button.dataset.propertyId);
 const target=byId.get(select?.value);
 if(!select||!target||select.value===property?.responsible_user_id)return;
 modal("Cambiar responsable de vivienda",`${personName(target)} pasará a ser el único responsable activo de ${property?.name||"esta vivienda"}. El responsable anterior perderá esa asignación.`,"Cambiar responsable",()=>rpc("assign_property_responsible_v3",{p_property_id:button.dataset.propertyId,p_employee_user_id:select.value}));
}));
$("requestWriteControl")?.addEventListener("click",()=>modal("Solicitar control de escritura","El titular actual deberá aceptar o rechazar la solicitud. Hasta entonces no cambiará ningún permiso.","Solicitar",()=>rpc("request_admin_write_control",{p_organization_id:data.organization_id})));
document.querySelectorAll(".accept-request").forEach(b=>b.addEventListener("click",()=>modal("Transferir control de escritura","Al aceptar, perderás inmediatamente el control de escritura y el administrador solicitante pasará a ser el único titular.","Aceptar transferencia",()=>rpc("decide_admin_write_control_request",{p_request_id:b.dataset.id,p_accept:true}))));
document.querySelectorAll(".reject-request").forEach(b=>b.addEventListener("click",()=>modal("Rechazar solicitud","El titular actual conservará el control de escritura. La decisión quedará registrada.","Rechazar",()=>rpc("decide_admin_write_control_request",{p_request_id:b.dataset.id,p_accept:false}))));
}
async function load(){try{const session=await getCurrentSession();if(!session)return;const {data,error}=await supabase.rpc("get_permission_management_context",{p_organization_id:null});if(error)throw error;render(data);$("permissionContent").hidden=false;$("permissionError").hidden=true;$("permissionStatus").innerHTML="<strong>Contexto cargado.</strong> Las operaciones críticas se validan en backend.";}catch(e){$("permissionError").textContent=e?.message==="not_authorized"?"No tienes autorización para acceder a Gestión de Permisos.":"No se pudo cargar Gestión de Permisos. No se ha realizado ningún cambio.";$("permissionError").hidden=false;}} load();