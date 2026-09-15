import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const cors={ "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type" };
const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(req.method!=="GET"&&req.method!=="POST") return json(405,{error:"method_not_allowed"});

  const auth=req.headers.get("Authorization");
  if(!auth?.startsWith("Bearer ")) return json(401,{error:"missing_authorization"});

  const url=Deno.env.get("SUPABASE_URL")!;
  const anon=Deno.env.get("SUPABASE_ANON_KEY")!;
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}}});
  const admin=createClient(url,service);

  const {data:{user},error:userError}=await userClient.auth.getUser();
  if(userError||!user) return json(401,{error:"invalid_session"});

  let taskId:string|null=null;
  if(req.method==="GET") taskId=new URL(req.url).searchParams.get("task_id");
  else {
    const body=await req.json().catch(()=>({}));
    taskId=typeof body?.task_id==="string"?body.task_id:null;
  }

  const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if(!taskId||!uuid.test(taskId)) return json(400,{error:"invalid_task_id"});

  const {data:task,error:taskError}=await admin.from("cleaning_tasks_v2")
    .select("id,organization_id,property_id,room_id,task_date,status,assigned_user_id")
    .eq("id",taskId).maybeSingle();
  if(taskError) return json(500,{error:"task_lookup_failed"});
  if(!task) return json(404,{error:"task_not_found"});
  if(task.assigned_user_id!==user.id) return json(403,{error:"task_not_assigned_to_user"});
  if(["cancelled","swapped","missed"].includes(task.status)) return json(409,{error:"task_not_actionable"});

  const {data:requests,error:requestError}=await admin.schema("private")
    .rpc("ensure_cleaning_photo_requests_v2",{p_cleaning_task_id:task.id});
  if(requestError){
    console.error(requestError);
    return json(409,{error:requestError.message?.includes("no_active_cleaning_patterns")?"no_active_cleaning_patterns":"checklist_failed"});
  }

  const patternIds=[...new Set((requests||[]).map((r:any)=>r.pattern_id))];
  const {data:patterns,error:patternError}=patternIds.length
    ? await admin.from("photo_patterns_v2").select("id,name,target_key").in("id",patternIds)
    : {data:[],error:null};
  if(patternError) return json(500,{error:"pattern_lookup_failed"});
  const byId=new Map((patterns||[]).map((p:any)=>[p.id,p]));

  const checklist=(requests||[]).map((r:any)=>{
    const p=byId.get(r.pattern_id) as any;
    return {
      request_id:r.id,
      kind:r.request_kind,
      ordinal:r.ordinal,
      completed:Boolean(r.completed_at),
      completed_at:r.completed_at,
      pattern:{id:r.pattern_id,name:p?.name||"Zona",target_key:p?.target_key||null},
      capture_url:`./photo-camera.html?mode=verify&pattern_id=${encodeURIComponent(r.pattern_id)}&source_type=cleaning_task&source_id=${encodeURIComponent(task.id)}&purpose=cleaning`
    };
  });

  return json(200,{ok:true,task:{id:task.id,property_id:task.property_id,room_id:task.room_id,task_date:task.task_date,status:task.status},checklist});
});
