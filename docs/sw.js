const CACHE='gestionpisos-shell-v2';
const ASSETS=['./','./index.html','./app.css','./app.js','./login.html','./auth.css','./login.js','./reset-password.html','./reset-password.js','./mfa-common.js','./mfa-setup.html','./mfa-setup.js','./mfa-challenge.html','./mfa-challenge.js','./supabase-client.js','./auth-guard.js','./workflows.html','./workflow-builder.html','./workflow-builder.css','./workflow-builder.js','./manifest.webmanifest'];

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
