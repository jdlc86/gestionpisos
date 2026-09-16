import { supabase } from "./supabase-client.js";

const form=document.getElementById("activationForm");
const password=document.getElementById("newPassword");
const confirmPassword=document.getElementById("confirmPassword");
const button=document.getElementById("activationBtn");
const backToLogin=document.getElementById("backToLogin");
const message=document.getElementById("authMessage");
let activationReady=false;
let passwordUpdated=false;

function show(text,error=false){message.textContent=text;message.classList.toggle("is-error",error);}
function setFormEnabled(enabled){password.disabled=!enabled;confirmPassword.disabled=!enabled;button.disabled=!enabled;}
async function onboardingState(){const {data,error}=await supabase.rpc("get_my_external_account_onboarding");if(error)throw error;return data;}

async function validateActivationSession(){
  try{
    const {data:sessionData,error:sessionError}=await supabase.auth.getSession();
    if(sessionError)throw sessionError;
    if(!sessionData.session){activationReady=false;setFormEnabled(false);show("La invitación no es válida o ha caducado. Solicita una nueva a tu gestoría.",true);return;}
    const state=await onboardingState();
    if(!state){activationReady=false;setFormEnabled(false);show("Esta cuenta no tiene una activación pendiente.",true);return;}
    if(state.status==="active"){
      activationReady=true;passwordUpdated=true;password.disabled=true;confirmPassword.disabled=true;button.disabled=false;button.textContent="Completar activación";
      show("Tu cuenta está preparada. Pulsa Completar activación para terminar de sincronizar el acceso.");return;
    }
    activationReady=true;setFormEnabled(true);
    const roleLabel=state.intended_role==="owner"?"propietario":"inquilino";
    show(`Identidad verificada. Crea una contraseña de al menos 12 caracteres para activar tu acceso como ${roleLabel}.`);
    password.focus();
  }catch{activationReady=false;setFormEnabled(false);show("No se pudo validar la activación. Comprueba tu conexión o solicita una invitación nueva.",true);}
}

supabase.auth.onAuthStateChange((event,session)=>{
  if((event==="PASSWORD_RECOVERY"||event==="SIGNED_IN")&&session){sessionStorage.setItem("allaiso-external-onboarding","1");validateActivationSession();}
});

backToLogin.addEventListener("click",async()=>{
  sessionStorage.removeItem("allaiso-external-onboarding");
  await supabase.auth.signOut({scope:"local"}).catch(()=>{});
  window.location.replace("./login.html");
});

form.addEventListener("submit",async event=>{
  event.preventDefault();if(!activationReady)return;
  if(!passwordUpdated){
    if(password.value!==confirmPassword.value){show("Las dos contraseñas no coinciden.",true);confirmPassword.focus();return;}
    if(password.value.length<12){show("La contraseña debe tener al menos 12 caracteres.",true);password.focus();return;}
  }
  setFormEnabled(false);show(passwordUpdated?"Completando activación…":"Guardando contraseña y activando cuenta…");
  try{
    if(!passwordUpdated){const {error}=await supabase.auth.updateUser({password:password.value});if(error)throw error;passwordUpdated=true;}
    const {data:completion,error:completionError}=await supabase.functions.invoke("complete-external-onboarding",{body:{}});
    if(completionError)throw completionError;
    if(!completion?.ok||completion?.status!=="active"||completion?.auth_metadata_synced!==true)throw new Error("external_activation_not_completed");
    sessionStorage.removeItem("allaiso-external-onboarding");
    const {error:signOutError}=await supabase.auth.signOut();
    if(signOutError)await supabase.auth.signOut({scope:"local"}).catch(()=>{});
    show("Cuenta activada correctamente. Redirigiendo al acceso…");
    setTimeout(()=>window.location.replace("./login.html?activated=1"),900);
  }catch(error){
    activationReady=true;button.disabled=false;
    if(!passwordUpdated){password.disabled=false;confirmPassword.disabled=false;show("No se pudo guardar la contraseña. Revisa los datos e inténtalo de nuevo.",true);}
    else{password.disabled=true;confirmPassword.disabled=true;button.textContent="Reintentar activación";show("La contraseña ya quedó guardada, pero falta completar la activación. Pulsa Reintentar activación.",true);}
    console.error("external_onboarding_activation_failed",error);
  }
});

validateActivationSession();
