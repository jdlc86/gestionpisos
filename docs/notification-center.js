const EVENT_DESTINATIONS={
  workflow_task_created:"./workflow-tasks.html",
  workflow_completed:"./workflow-history.html",
  workflow_rejected:"./workflow-history.html",
  workflow_schedule_blocked:"./workflow-definitions.html"
};

const NOTIFICATION_STYLE_VERSION="2026092001";

function fmtDate(value){
  if(!value)return "";
  try{
    return new Intl.DateTimeFormat("es-ES",{
      day:"2-digit",
      month:"short",
      hour:"2-digit",
      minute:"2-digit"
    }).format(new Date(value));
  }catch{return value}
}

function unread(row){
  return row.status!=="read"&&!row.read_at;
}

function routeFor(row){
  const href=EVENT_DESTINATIONS[row.event_type]||null;
  return href?new URL(href,window.location.href).href:null;
}

function bellIcon(){
  return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6.5 17h11l-1.3-1.7V10a4.2 4.2 0 0 0-8.4 0v5.3L6.5 17Z"/><path d="M10 20h4"/></svg>';
}

function closeIcon(){
  return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m7 7 10 10M17 7 7 17"/></svg>';
}

function notificationIcon(row){
  const type=String(row?.event_type||"");
  if(type==="workflow_completed"){
    return '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8"/><path d="m8.5 12 2.2 2.2 4.8-5"/></svg>';
  }
  if(type==="workflow_rejected"){
    return '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8"/><path d="m9 9 6 6M15 9l-6 6"/></svg>';
  }
  if(type==="workflow_schedule_blocked"){
    return '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8"/><path d="M12 8v4l2.5 1.5"/><path d="M18 6l2-2"/></svg>';
  }
  if(type==="workflow_task_created"){
    return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 5h10v14H7z"/><path d="M9.5 9h5M9.5 13h5"/></svg>';
  }
  return bellIcon();
}

function chevronIcon(){
  return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg>';
}

function ensureStyles(){
  if([...document.querySelectorAll('link[rel="stylesheet"]')].some(link=>String(link.href||"").includes("notification-center.css")))return;
  const link=document.createElement("link");
  link.rel="stylesheet";
  link.href="./notification-center.css?v="+NOTIFICATION_STYLE_VERSION;
  link.dataset.notificationCenterStyle="1";
  document.head.append(link);
}

function notificationActionsHost(){
  const existing=document.querySelector(
    ".topbar .global-actions, .topbar .toolbar-actions, #definitionsNormalHeader .definitions-header-actions"
  );
  if(existing){
    existing.classList.add("notification-actions-host");
    return existing;
  }
  const topbar=document.querySelector(".topbar");
  if(!topbar)return null;
  const host=document.createElement("div");
  host.className="global-actions notification-actions-host";
  topbar.append(host);
  return host;
}

function pushSupported(){
  return Boolean(
    window.isSecureContext
    && "serviceWorker" in navigator
    && "PushManager" in window
    && "Notification" in window
  );
}

function base64UrlToUint8Array(value){
  const padding="=".repeat((4-value.length%4)%4);
  const base64=(value+padding).replace(/-/g,"+").replace(/_/g,"/");
  const raw=atob(base64);
  return Uint8Array.from([...raw].map(char=>char.charCodeAt(0)));
}

function pushPayload(subscription){
  const data=subscription.toJSON();
  return {
    endpoint:String(data.endpoint||subscription.endpoint||""),
    p256dh:String(data.keys?.p256dh||""),
    auth:String(data.keys?.auth||"")
  };
}

export async function mountNotificationCenter({supabase,session}={}){
  if(!supabase||!session?.user?.id||document.getElementById("notificationBell"))return;

  ensureStyles();
  const actions=notificationActionsHost();
  if(!actions)return;

  const root=document.createElement("div");
  root.className="notification-center";

  const trigger=document.createElement("button");
  trigger.id="notificationBell";
  trigger.type="button";
  trigger.className="global-icon notification-bell";
  trigger.setAttribute("aria-label","Notificaciones");
  trigger.setAttribute("aria-haspopup","dialog");
  trigger.setAttribute("aria-expanded","false");
  trigger.title="Notificaciones";
  trigger.innerHTML=bellIcon();

  const count=document.createElement("span");
  count.className="notification-bell-count";
  count.hidden=true;
  trigger.append(count);
  root.append(trigger);

  const dialog=document.createElement("dialog");
  dialog.id="notificationCenterDialog";
  dialog.className="notification-sheet";
  dialog.setAttribute("aria-labelledby","notificationCenterTitle");

  const card=document.createElement("section");
  card.className="notification-sheet-card";

  const head=document.createElement("div");
  head.className="notification-sheet-head";

  const heading=document.createElement("div");
  heading.innerHTML='<p class="eyebrow">ACTIVIDAD</p><h2 id="notificationCenterTitle">Notificaciones</h2>';

  const close=document.createElement("button");
  close.type="button";
  close.className="notification-sheet-close";
  close.setAttribute("aria-label","Cerrar notificaciones");
  close.innerHTML=closeIcon();

  head.append(heading,close);

  const toolbar=document.createElement("div");
  toolbar.className="notification-toolbar";

  const summary=document.createElement("span");
  summary.className="notification-summary";
  summary.textContent="Cargando…";

  const toolbarActions=document.createElement("div");
  toolbarActions.className="notification-toolbar-actions";

  const pushAction=document.createElement("button");
  pushAction.type="button";
  pushAction.className="notification-push-action";
  pushAction.textContent="Avisos Android";
  pushAction.hidden=true;
  pushAction.setAttribute("aria-pressed","false");

  const markAll=document.createElement("button");
  markAll.type="button";
  markAll.className="notification-mark-all";
  markAll.textContent="Marcar todo como leído";
  markAll.hidden=true;

  toolbarActions.append(pushAction,markAll);
  toolbar.append(summary,toolbarActions);

  const list=document.createElement("div");
  list.className="notification-list";
  list.setAttribute("aria-live","polite");

  card.append(head,toolbar,list);
  dialog.append(card);
  document.body.append(dialog);

  const homeAccount=actions.querySelector(":scope > #homeAccount");
  if(homeAccount){
    actions.insertBefore(root,homeAccount);
  }else{
    actions.append(root);
  }

  let rows=[];
  let loading=false;
  let currentPushSubscription=null;
  let pushBusy=false;

  function syncCount(){
    const pending=rows.filter(unread).length;
    count.hidden=pending===0;
    count.textContent=pending>99?"99+":String(pending);
    trigger.setAttribute(
      "aria-label",
      pending?("Notificaciones · "+pending+" sin leer"):"Notificaciones"
    );
    summary.textContent=pending
      ?pending+" sin leer"
      :"Todo al día";
    markAll.hidden=pending===0;
  }

  function empty(message){
    const box=document.createElement("div");
    box.className="notification-empty";
    box.innerHTML='<strong>Sin notificaciones</strong><p></p>';
    box.querySelector("p").textContent=message;
    return box;
  }

  async function markRead(row){
    if(!unread(row))return true;
    const {error}=await supabase.rpc("mark_notification_read",{
      p_notification_id:row.id
    });
    if(error)return false;
    row.status="read";
    row.read_at=row.read_at||new Date().toISOString();
    syncCount();
    return true;
  }

  async function acknowledgePushNavigation(){
    const url=new URL(window.location.href);
    const notificationId=String(url.searchParams.get("push_notification")||"").trim();
    if(!notificationId)return;
    await supabase.rpc("mark_notification_read",{p_notification_id:notificationId});
    url.searchParams.delete("push_notification");
    history.replaceState(history.state,"",url.href);
  }

  function render(){
    list.replaceChildren();

    if(!rows.length){
      list.append(empty("Cuando un flujo genere actividad relevante aparecerá aquí."));
      syncCount();
      return;
    }

    rows.forEach(row=>{
      const item=document.createElement("button");
      item.type="button";
      item.className="notification-item"+(unread(row)?" is-unread":"");
      item.dataset.notificationId=row.id;

      const visual=document.createElement("span");
      visual.className="notification-item-visual";
      visual.setAttribute("aria-hidden","true");
      visual.innerHTML=notificationIcon(row);

      const marker=document.createElement("span");
      marker.className="notification-item-marker";
      visual.append(marker);

      const body=document.createElement("span");
      body.className="notification-item-body";

      const title=document.createElement("strong");
      title.textContent=row.title||"Notificación";

      const message=document.createElement("span");
      message.className="notification-item-message";
      message.textContent=row.body||"";

      const meta=document.createElement("span");
      meta.className="notification-item-meta";
      meta.textContent=fmtDate(row.created_at);

      const chevron=document.createElement("span");
      chevron.className="notification-item-chevron";
      chevron.setAttribute("aria-hidden","true");
      chevron.innerHTML=chevronIcon();

      body.append(title,message,meta);
      item.append(visual,body,chevron);

      item.addEventListener("click",async()=>{
        item.disabled=true;
        await markRead(row);
        const route=routeFor(row);
        if(route){
          window.location.assign(route);
          return;
        }
        item.disabled=false;
        item.classList.remove("is-unread");
        render();
      });

      list.append(item);
    });

    syncCount();
  }

  async function load(){
    if(loading)return;
    loading=true;
    const {data,error}=await supabase
      .from("notifications_v2")
      .select("id,event_type,title,body,status,channel_in_app,source_kind,source_id,event_key,created_at,read_at")
      .eq("recipient_user_id",session.user.id)
      .eq("channel_in_app",true)
      .order("created_at",{ascending:false})
      .limit(30);

    loading=false;
    if(error){
      list.replaceChildren(empty("No se pudieron cargar los avisos. Vuelve a intentarlo."));
      summary.textContent="No disponible";
      markAll.hidden=true;
      return;
    }

    rows=data||[];
    render();
  }

  async function registerPushSubscription(subscription){
    const payload=pushPayload(subscription);
    if(!payload.endpoint||!payload.p256dh||!payload.auth)throw new Error("push_subscription_incomplete");
    const {error}=await supabase.rpc("register_web_push_subscription_v1",{
      p_endpoint:payload.endpoint,
      p_p256dh:payload.p256dh,
      p_auth_secret:payload.auth,
      p_user_agent:navigator.userAgent||null
    });
    if(error)throw error;
  }

  async function syncPushState({rebind=false}={}){
    if(!pushSupported()){
      pushAction.hidden=false;
      pushAction.disabled=true;
      pushAction.textContent="Avisos no compatibles";
      pushAction.title="Este navegador no admite Web Push.";
      return;
    }

    if(Notification.permission==="denied"){
      currentPushSubscription=null;
      pushAction.hidden=false;
      pushAction.disabled=true;
      pushAction.textContent="Avisos bloqueados";
      pushAction.title="Activa las notificaciones para Allaiso desde los permisos de Android o del navegador.";
      pushAction.setAttribute("aria-pressed","false");
      return;
    }

    try{
      const registration=await navigator.serviceWorker.ready;
      currentPushSubscription=await registration.pushManager.getSubscription();
      if(currentPushSubscription&&Notification.permission==="granted"&&rebind){
        await registerPushSubscription(currentPushSubscription);
      }
      pushAction.hidden=false;
      pushAction.disabled=false;
      pushAction.classList.toggle("is-active",Boolean(currentPushSubscription));
      pushAction.setAttribute("aria-pressed",currentPushSubscription?"true":"false");
      pushAction.textContent=currentPushSubscription?"Android activo":"Activar Android";
      pushAction.title=currentPushSubscription
        ?"Toca para desactivar las notificaciones de Android en este dispositivo."
        :"Toca para recibir notificaciones de Allaiso en Android.";
    }catch(error){
      console.error("web_push_state_failed",error);
      pushAction.hidden=false;
      pushAction.disabled=false;
      pushAction.textContent="Activar Android";
      pushAction.setAttribute("aria-pressed","false");
    }
  }

  async function enablePush(){
    if(pushBusy||!pushSupported())return;
    pushBusy=true;
    pushAction.disabled=true;
    pushAction.textContent="Activando…";
    try{
      const permission=Notification.permission==="granted"
        ?"granted"
        :await Notification.requestPermission();
      if(permission!=="granted"){
        await syncPushState();
        return;
      }

      const {data,error}=await supabase.functions.invoke("web-push",{
        body:{action:"config"}
      });
      if(error||!data?.public_key)throw error||new Error("web_push_public_key_missing");

      const registration=await navigator.serviceWorker.ready;
      const existing=await registration.pushManager.getSubscription();
      currentPushSubscription=existing||await registration.pushManager.subscribe({
        userVisibleOnly:true,
        applicationServerKey:base64UrlToUint8Array(String(data.public_key))
      });
      await registerPushSubscription(currentPushSubscription);
      await syncPushState();
    }catch(error){
      console.error("web_push_enable_failed",error);
      pushAction.textContent="No se pudo activar";
      pushAction.title="No se pudo activar ahora. Toca para reintentar.";
      pushAction.disabled=false;
    }finally{
      pushBusy=false;
    }
  }

  async function disablePush(){
    if(pushBusy||!currentPushSubscription)return;
    pushBusy=true;
    pushAction.disabled=true;
    pushAction.textContent="Desactivando…";
    const endpoint=currentPushSubscription.endpoint;
    try{
      await currentPushSubscription.unsubscribe();
      await supabase.rpc("unregister_web_push_subscription_v1",{p_endpoint:endpoint});
      currentPushSubscription=null;
      await syncPushState();
    }catch(error){
      console.error("web_push_disable_failed",error);
      await syncPushState();
    }finally{
      pushBusy=false;
    }
  }

  function open(){
    trigger.setAttribute("aria-expanded","true");
    if(dialog.showModal)dialog.showModal();
    else dialog.setAttribute("open","");
    load();
    syncPushState();
  }

  function closeSheet(){
    trigger.setAttribute("aria-expanded","false");
    if(dialog.open&&dialog.close)dialog.close();
    else dialog.removeAttribute("open");
  }

  trigger.addEventListener("click",open);
  close.addEventListener("click",closeSheet);
  dialog.addEventListener("close",()=>{
    trigger.setAttribute("aria-expanded","false");
    trigger.focus();
  });
  dialog.addEventListener("click",event=>{
    if(event.target===dialog)closeSheet();
  });

  pushAction.addEventListener("click",()=>{
    if(currentPushSubscription)disablePush();
    else enablePush();
  });

  markAll.addEventListener("click",async()=>{
    const pending=rows.filter(unread);
    if(!pending.length)return;
    markAll.disabled=true;
    markAll.textContent="Marcando…";

    for(const row of pending){
      await markRead(row);
    }

    markAll.disabled=false;
    markAll.textContent="Marcar todo como leído";
    render();
  });

  const refreshWhenVisible=()=>{
    if(document.visibilityState==="visible")load();
  };
  document.addEventListener("visibilitychange",refreshWhenVisible);
  window.addEventListener("focus",load);

  await acknowledgePushNavigation();
  await Promise.all([load(),syncPushState({rebind:true})]);
}
