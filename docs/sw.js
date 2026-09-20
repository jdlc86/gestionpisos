const CACHE='gestionpisos-shell-v44';
const ASSETS=['./','./index.html','./app.css','./app.js','./login.html','./auth.css','./login.js','./reset-password.html','./reset-password.js','./mfa-common.js','./mfa-code-input.js','./mfa-setup.html','./mfa-setup.js','./mfa-challenge.html','./mfa-challenge.js','./supabase-client.js','./auth-guard.js','./notification-center.js','./notification-center.css','./bottom-nav.js','./bottom-nav.css','./workflows.html','./workflow-builder.html','./workflow-builder.css','./workflow-builder.js','./workflow-definitions.html','./workflow-definitions.css','./workflow-definitions.js','./workflow-applications.html','./workflow-applications.css','./workflow-applications.js','./workflow-tasks.html','./workflow-tasks.css','./workflow-tasks.js','./workflow-history.html','./workflow-history.css','./workflow-history.js','./manifest.webmanifest','./legal.html','./privacy.html'];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate',event=>{
  event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))));
  self.clients.claim();
});

self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET') return;

  const url=new URL(event.request.url);
  if(url.origin!==self.location.origin) return;

  event.respondWith((async()=>{
    try{
      return await fetch(event.request);
    }catch{
      const cached=await caches.match(event.request,{ignoreSearch:true});
      if(cached) return cached;
      if(event.request.mode==='navigate'){
        const login=await caches.match('./login.html');
        if(login) return login;
      }
      return Response.error();
    }
  })());
});

self.addEventListener('push',event=>{
  let payload={};
  try{
    payload=event.data?event.data.json():{};
  }catch{
    payload={body:event.data?event.data.text():""};
  }

  const title=String(payload.title||'Allaiso');
  const body=String(payload.body||'Tienes una nueva notificación.');
  const tag=String(payload.tag||('allaiso-'+Date.now()));
  const url=String(payload.url||'./');
  const notificationId=String(payload.notificationId||'');

  event.waitUntil(
    self.registration.showNotification(title,{
      body,
      tag,
      data:{url,notificationId}
    })
  );
});

self.addEventListener('notificationclick',event=>{
  event.notification.close();

  const data=event.notification.data||{};
  const target=new URL(String(data.url||'./'),self.registration.scope);
  if(data.notificationId)target.searchParams.set('push_notification',String(data.notificationId));

  event.waitUntil((async()=>{
    const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
    for(const client of windows){
      if(!String(client.url||'').startsWith(self.registration.scope))continue;
      try{
        await client.navigate(target.href);
      }catch{}
      await client.focus();
      return;
    }
    if(self.clients.openWindow)await self.clients.openWindow(target.href);
  })());
});
