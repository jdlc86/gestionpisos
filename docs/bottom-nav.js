const EXCLUDED_PAGES=new Set([
  "login.html",
  "reset-password.html",
  "activate-account.html",
  "activate-external-account.html",
  "mfa-setup.html",
  "mfa-challenge.html",
  "photo-camera.html",
  "photo-pattern-editor.html"
]);

const FLOW_PAGES=new Set([
  "workflows.html",
  "workflow-builder.html",
  "workflow-definitions.html",
  "workflow-applications.html",
  "photo-patterns.html",
  "photo-verifications.html"
]);

const MORE_PAGES=new Set([
  "operations.html",
  "incidents.html",
  "cleaning.html",
  "permissions.html",
  "configuration-resources.html",
  "factory-reset.html"
]);

const ICONS={
  home:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 10.5 12 3l8.5 7.5v9a1.5 1.5 0 0 1-1.5 1.5h-5v-6H10v6H5a1.5 1.5 0 0 1-1.5-1.5z"/></svg>',
  portfolio:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 21V9l8-5 8 5v12M8 21v-7h8v7M7 10h.01M17 10h.01"/></svg>',
  flows:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 7h9a4 4 0 0 1 4 4v1M17 4l3 3-3 3M17 17H8a4 4 0 0 1-4-4v-1M7 20l-3-3 3-3"/></svg>',
  tasks:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5h11M9 12h11M9 19h11M4 5l1 1 2-2M4 12l1 1 2-2M4 19l1 1 2-2"/></svg>',
  more:'<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/></svg>',
  operations:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/></svg>',
  incidents:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3 2.8 20h18.4zM12 9v5M12 17h.01"/></svg>',
  cleaning:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m14 3 7 7M16.5 5.5 7 15l-4 6 6-4 9.5-9.5M7 15l2 2"/></svg>',
  permissions:'<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="10" width="18" height="11" rx="2"/><path d="M7 10V7a5 5 0 0 1 10 0v3M12 14v3"/></svg>',
  settings:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 15.2a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 0 0 0 6.4z"/><path d="M19.4 15a1.7 1.7 0 0 0 .34 1.87l.06.06-2.83 2.83-.06-.06A1.7 1.7 0 0 0 15 19.36a1.7 1.7 0 0 0-1 .64 1.7 1.7 0 0 0-.36 1.06V21h-4v-.08A1.7 1.7 0 0 0 8.6 19.4a1.7 1.7 0 0 0-1.87.34l-.06.06-2.83-2.83.06-.06A1.7 1.7 0 0 0 4.24 15a1.7 1.7 0 0 0-.64-1A1.7 1.7 0 0 0 2.54 13H2.5V9h.08A1.7 1.7 0 0 0 4.1 8a1.7 1.7 0 0 0-.34-1.87l-.06-.06 2.83-2.83.06.06A1.7 1.7 0 0 0 8.46 3a1.7 1.7 0 0 0 1-.64A1.7 1.7 0 0 0 9.82 1.3V1.2h4v.08A1.7 1.7 0 0 0 14.86 2.8a1.7 1.7 0 0 0 1.87-.34l.06-.06 2.83 2.83-.06.06A1.7 1.7 0 0 0 19.22 7a1.7 1.7 0 0 0 .64 1 1.7 1.7 0 0 0 1.06.36H21v4h-.08A1.7 1.7 0 0 0 19.4 15z"/></svg>'
};

function pageName(){
  return window.location.pathname.split("/").pop()||"index.html";
}

function activeTab(page){
  if(page==="index.html"||page==="")return "home";
  if(page==="portfolio.html")return "portfolio";
  if(page==="workflow-tasks.html")return "tasks";
  if(FLOW_PAGES.has(page))return "flows";
  if(MORE_PAGES.has(page))return "more";
  return "";
}

function icon(name){
  return '<span class="app-bottom-nav-icon">'+ICONS[name]+'</span>';
}

function navLink({key,label,href,current}){
  const a=document.createElement("a");
  a.className="app-bottom-nav-item"+(current===key?" is-active":"");
  a.href=href;
  a.dataset.bottomNav=key;
  if(current===key)a.setAttribute("aria-current","page");
  a.innerHTML=icon(key)+'<span class="app-bottom-nav-label">'+label+"</span>";
  return a;
}

function sheetLink({label,detail,href,iconName}){
  const a=document.createElement("a");
  a.className="app-more-link";
  a.href=href;
  a.innerHTML=icon(iconName)+'<span><strong>'+label+'</strong><small>'+detail+"</small></span>";
  return a;
}

function ensureStylesheet(){
  if(document.querySelector('link[data-bottom-nav-style]'))return;
  const link=document.createElement("link");
  link.rel="stylesheet";
  link.href="./bottom-nav.css?v=2026091901";
  link.dataset.bottomNavStyle="";
  document.head.append(link);
}

async function activeRoles(supabase,userId){
  try{
    const {data,error}=await supabase
      .from("user_roles")
      .select("role")
      .eq("user_id",userId)
      .is("revoked_at",null);
    if(error)return new Set();
    return new Set((data||[]).map(row=>String(row.role||"").toLowerCase()));
  }catch{
    return new Set();
  }
}

function syncKeyboard(nav){
  const viewport=window.visualViewport;
  if(!viewport)return()=>{};
  const update=()=>{
    const keyboardLikelyOpen=viewport.height<window.innerHeight*.74;
    nav.classList.toggle("is-keyboard-hidden",keyboardLikelyOpen);
  };
  viewport.addEventListener("resize",update);
  viewport.addEventListener("scroll",update);
  update();
  return()=>{
    viewport.removeEventListener("resize",update);
    viewport.removeEventListener("scroll",update);
  };
}

export async function mountBottomNavigation({supabase,session}={}){
  if(document.getElementById("appBottomNav"))return;
  const page=pageName();
  if(EXCLUDED_PAGES.has(page))return;

  ensureStylesheet();

  const current=activeTab(page);
  const nav=document.createElement("nav");
  nav.id="appBottomNav";
  nav.className="app-bottom-nav";
  nav.setAttribute("aria-label","Navegación principal");

  const inner=document.createElement("div");
  inner.className="app-bottom-nav-inner";
  inner.append(
    navLink({key:"home",label:"Inicio",href:"./",current}),
    navLink({key:"portfolio",label:"Cartera",href:"./portfolio.html",current}),
    navLink({key:"flows",label:"Flujos",href:"./workflows.html",current}),
    navLink({key:"tasks",label:"Tareas",href:"./workflow-tasks.html",current})
  );

  const more=document.createElement("button");
  more.type="button";
  more.className="app-bottom-nav-item"+(current==="more"?" is-active":"");
  more.dataset.bottomNav="more";
  more.setAttribute("aria-label","Más opciones");
  more.setAttribute("aria-haspopup","dialog");
  more.setAttribute("aria-expanded","false");
  more.innerHTML=icon("more")+'<span class="app-bottom-nav-label">Más</span>';
  inner.append(more);
  nav.append(inner);

  const dialog=document.createElement("dialog");
  dialog.id="appMoreSheet";
  dialog.className="app-more-sheet";
  dialog.setAttribute("aria-labelledby","appMoreSheetTitle");

  const card=document.createElement("section");
  card.className="app-more-sheet-card";
  const head=document.createElement("div");
  head.className="app-more-sheet-head";
  head.innerHTML='<div><p class="eyebrow">Navegación</p><h2 id="appMoreSheetTitle">Más</h2></div>';
  const close=document.createElement("button");
  close.type="button";
  close.className="app-more-sheet-close";
  close.setAttribute("aria-label","Cerrar menú");
  close.textContent="×";
  head.append(close);

  const links=document.createElement("div");
  links.className="app-more-links";
  links.append(
    sheetLink({label:"Incidencias",detail:"Reportes y seguimiento",href:"./incidents.html",iconName:"incidents"}),
    sheetLink({label:"Limpieza",detail:"Turnos y fotoverificación",href:"./cleaning.html",iconName:"cleaning"})
  );

  card.append(head,links);
  dialog.append(card);

  document.body.append(dialog,nav);
  document.body.classList.add("has-bottom-nav");

  const roles=await activeRoles(supabase,session?.user?.id);
  const manager=roles.has("root")||roles.has("admin");
  const root=roles.has("root");

  if(manager){
    links.prepend(sheetLink({
      label:"Centro Operativo",
      detail:"Notificaciones, pagos y métricas",
      href:"./operations.html",
      iconName:"operations"
    }));
    links.append(sheetLink({
      label:"Gestión de Permisos",
      detail:"Roles, responsables y accesos",
      href:"./permissions.html",
      iconName:"permissions"
    }));
  }
  if(root){
    links.append(sheetLink({
      label:"Configuración y Recursos",
      detail:"Seguridad y estado técnico global",
      href:"./configuration-resources.html",
      iconName:"settings"
    }));
  }

  const openSheet=()=>{
    more.setAttribute("aria-expanded","true");
    if(dialog.showModal)dialog.showModal();
    else dialog.setAttribute("open","");
  };
  const closeSheet=()=>{
    more.setAttribute("aria-expanded","false");
    if(dialog.open&&dialog.close)dialog.close();
    else dialog.removeAttribute("open");
  };

  more.addEventListener("click",openSheet);
  close.addEventListener("click",closeSheet);
  dialog.addEventListener("close",()=>more.setAttribute("aria-expanded","false"));
  dialog.addEventListener("click",event=>{
    if(event.target===dialog)closeSheet();
  });

  syncKeyboard(nav);
}
