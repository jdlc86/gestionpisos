const EVENT_DESTINATIONS={
  workflow_task_created:"./workflow-tasks.html",
  workflow_completed:"./workflow-history.html",
  workflow_rejected:"./workflow-history.html",
  workflow_schedule_blocked:"./workflow-definitions.html"
};

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

export async function mountNotificationCenter({supabase,session}={}){
  if(!supabase||!session?.user?.id||document.getElementById("notificationBell"))return;

  const actions=document.querySelector(".topbar .global-actions");
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

  const markAll=document.createElement("button");
  markAll.type="button";
  markAll.className="notification-mark-all";
  markAll.textContent="Marcar todo como leído";
  markAll.hidden=true;

  toolbar.append(summary,markAll);

  const list=document.createElement("div");
  list.className="notification-list";
  list.setAttribute("aria-live","polite");

  card.append(head,toolbar,list);
  dialog.append(card);
  document.body.append(dialog);
  actions.insertBefore(root,actions.firstChild);

  let rows=[];
  let loading=false;

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

      const marker=document.createElement("span");
      marker.className="notification-item-marker";
      marker.setAttribute("aria-hidden","true");

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

      body.append(title,message,meta);
      item.append(marker,body);

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

  function open(){
    trigger.setAttribute("aria-expanded","true");
    if(dialog.showModal)dialog.showModal();
    else dialog.setAttribute("open","");
    load();
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

  await load();
}
