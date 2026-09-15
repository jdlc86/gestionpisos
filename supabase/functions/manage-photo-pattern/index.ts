import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const h={"Access-Control-Allow-Origin":"https://jdlc86.github.io","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Content-Type":"application/json"};
const reply=(status:number,body:Record<string,unknown>)=>new Response(JSON.stringify(body),{status,headers:h});

Deno.serve(async(req)=>{
 if(req.method==="OPTIONS") return new Response("ok",{headers:h});
 if(req.method!=="POST") return reply(405,{error:"method_not_allowed"});
 const url=Deno.env.get("SUPABASE_URL");
 const key=Deno.env.get(["SUPABASE","SERVICE","ROLE","KEY"].join("_"));
 const authorization=req.headers.get("Authorization");
 if(!url||!key||!authorization) return reply(401,{error:"authentication_required"});
 const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const token=authorization.replace(/^Bearer\s+/i,"").trim();
 const {data:{user},error:ue}=await admin.auth.getUser(token);
 if(ue||!user) return reply(401,{error:"invalid_session"});
 const body=await req.json().catch(()=>({}));
 const patternId=typeof body.pattern_id==="string"?body.pattern_id.trim():"";
 if(!/^[0-9a-f-]{36}$/i.test(patternId)) return reply(400,{error:"invalid_pattern_id"});
 const {data:pattern,error:pe}=await admin.from("photo_patterns_v2").select("id,organization_id,property_id,name").eq("id",patternId).maybeSingle();
 if(pe) return reply(500,{error:"pattern_lookup_failed"});
 if(!pattern) return reply(404,{error:"pattern_not_found"});
 const role=String(user.app_metadata?.role||"");
 let allowed=role==="root";
 if(role==="admin"){
   const org=String(user.app_metadata?.organization_id||"");
   allowed=!org||org===String(pattern.organization_id);
 } else if(!allowed) {
   const {data:grants,error:ge}=await admin.from("property_staff_access_v3").select("valid_from,valid_until").eq("property_id",pattern.property_id).eq("employee_user_id",user.id).eq("can_write",true).is("revoked_at",null);
   if(ge) return reply(500,{error:"permission_lookup_failed"});
   const now=Date.now();
   allowed=(grants||[]).some((g:any)=>(!g.valid_from||Date.parse(g.valid_from)<=now)&&(!g.valid_until||Date.parse(g.valid_until)>now));
 }
 if(!allowed) return reply(403,{error:"insufficient_write_permission"});
 const {data:result,error:re}=await admin.schema("private").rpc("delete_or_retire_photo_pattern_v2",{p_pattern_id:patternId});
 if(re) return reply(500,{error:"pattern_lifecycle_failed"});
 return reply(200,{result,pattern:{id:pattern.id,name:pattern.name}});
});