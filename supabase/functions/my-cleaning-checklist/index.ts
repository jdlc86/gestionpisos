import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const cors={ "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type" };
const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async(req)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  if(req.method!=="GET"&&req.method!=="POST") return json(405,{error:"method_not_allowed"});

  const auth=req.headers.get("Authorization");
  if(!auth?.startsWith("Bearer ")) return json(401,{error:"missing_authorization"});

  const url=Deno.env.get("SUPABASE_URL")!;
  const anon=Deno.env.get("SUPABASE_ANON_KEY")!;
  const privilegedKey=Deno.env.get(["SUPABASE","SERVICE","ROLE","KEY"].join("_"))!;
  const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}}});
  const admin=createClient(url,privilegedKey);

  const {data:{user},error:userError}=await userClient.auth.getUser();
  if(userError||!user) return json(401,{error:"invalid_session"});

  let workflowTaskId:string|null=null;
  let cleaningTaskId:string|null=null;
  if(req.method==="GET"){
    const params=new URL(req.url).searchParams;
    workflowTaskId=params.get("workflow_task_id");
    cleaningTaskId=params.get("task_id");
  }else{
    const body=await req.json().catch(()=>({}));
    workflowTaskId=typeof body?.workflow_task_id==="string"?body.workflow_task_id:null;
    cleaningTaskId=typeof body?.task_id==="string"?body.task_id:null;
  }

  if(workflowTaskId&&cleaningTaskId) return json(400,{error:"ambiguous_task_reference"});
  if(workflowTaskId&&!uuid.test(workflowTaskId)) return json(400,{error:"invalid_workflow_task_id"});
  if(cleaningTaskId&&!uuid.test(cleaningTaskId)) return json(400,{error:"invalid_task_id"});
  if(!workflowTaskId&&!cleaningTaskId) return json(400,{error:"missing_task_reference"});

  let task:any=null;
  let workflowTask:any=null;
  let workflowExecution:any=null;
  let readOnly=false;

  if(workflowTaskId){
    const {data:operationalTask,error:operationalError}=await admin.from("tenant_tasks_v2")
      .select("id,organization_id,property_id,room_id,status,assigned_user_id,source_kind,source_id,removed_at")
      .eq("id",workflowTaskId)
      .maybeSingle();
    if(operationalError) return json(500,{error:"workflow_task_lookup_failed"});
    if(!operationalTask||operationalTask.removed_at) return json(404,{error:"workflow_task_not_found"});
    if(operationalTask.assigned_user_id!==user.id) return json(403,{error:"workflow_task_not_assigned_to_user"});
    if(operationalTask.source_kind!=="workflow_execution"||!uuid.test(String(operationalTask.source_id||""))){
      return json(409,{error:"workflow_task_not_cleaning"});
    }

    const {data:execution,error:executionError}=await admin.from("workflow_executions_v2")
      .select("id,organization_id,property_id,room_id,status,assigned_user_id,spec_snapshot")
      .eq("id",operationalTask.source_id)
      .maybeSingle();
    if(executionError) return json(500,{error:"workflow_execution_lookup_failed"});
    if(!execution) return json(409,{error:"workflow_execution_not_found"});

    const spec=(execution.spec_snapshot||{}) as Record<string,unknown>;
    if(spec.flowType!=="cleaning"||spec.closeType!=="domain_adapter"){
      return json(409,{error:"workflow_task_not_cleaning"});
    }
    if(
      execution.organization_id!==operationalTask.organization_id
      || execution.property_id!==operationalTask.property_id
      || execution.room_id!==operationalTask.room_id
      || execution.assigned_user_id!==operationalTask.assigned_user_id
      || execution.status!==operationalTask.status
    ){
      return json(409,{error:"workflow_cleaning_state_mismatch"});
    }

    if(operationalTask.status==="pending") return json(409,{error:"workflow_accept_required"});
    if(!["active","waiting_review","completed","rejected"].includes(operationalTask.status)){
      return json(409,{error:"task_not_actionable"});
    }

    const {data:domainTask,error:domainError}=await admin.from("cleaning_tasks_v2")
      .select("id,organization_id,property_id,room_id,task_date,status,assigned_user_id,workflow_execution_id")
      .eq("workflow_execution_id",execution.id)
      .maybeSingle();
    if(domainError) return json(500,{error:"task_lookup_failed"});
    if(!domainTask) return json(409,{error:"workflow_cleaning_domain_missing"});
    if(
      domainTask.workflow_execution_id!==execution.id
      || domainTask.organization_id!==execution.organization_id
      || domainTask.property_id!==execution.property_id
      || domainTask.room_id!==execution.room_id
      || domainTask.assigned_user_id!==user.id
    ){
      return json(409,{error:"workflow_cleaning_identity_mismatch"});
    }

    const expectedDomainStates:Record<string,string[]>={
      active:["accepted","in_progress","submitted"],
      waiting_review:["submitted"],
      completed:["approved"],
      rejected:["rejected"]
    };
    if(!(expectedDomainStates[operationalTask.status]||[]).includes(domainTask.status)){
      return json(409,{error:"workflow_cleaning_state_mismatch"});
    }

    workflowTask=operationalTask;
    workflowExecution=execution;
    task=domainTask;
    readOnly=operationalTask.status!=="active"||domainTask.status==="submitted";
  }else{
    const {data:legacyTask,error:taskError}=await admin.from("cleaning_tasks_v2")
      .select("id,organization_id,property_id,room_id,task_date,status,assigned_user_id,workflow_execution_id")
      .eq("id",cleaningTaskId)
      .maybeSingle();
    if(taskError) return json(500,{error:"task_lookup_failed"});
    if(!legacyTask) return json(404,{error:"task_not_found"});
    if(legacyTask.assigned_user_id!==user.id) return json(403,{error:"task_not_assigned_to_user"});
    if(["cancelled","swapped","missed"].includes(legacyTask.status)) return json(409,{error:"task_not_actionable"});

    task=legacyTask;
    readOnly=["submitted","approved","rejected"].includes(legacyTask.status);
  }

  let requests:any[]=[];
  if(readOnly){
    const {data,error}=await admin.from("cleaning_photo_requests_v2")
      .select("id,pattern_id,request_kind,ordinal,completed_run_id,completed_at")
      .eq("cleaning_task_id",task.id)
      .order("ordinal");
    if(error) return json(500,{error:"checklist_lookup_failed"});
    requests=data||[];
  }else{
    const {data,error}=await admin.schema("private")
      .rpc("ensure_cleaning_photo_requests_v2",{p_cleaning_task_id:task.id});
    if(error){
      console.error(error);
      return json(409,{error:error.message?.includes("no_active_cleaning_patterns")?"no_active_cleaning_patterns":"checklist_failed"});
    }
    requests=data||[];
  }

  const patternIds=[...new Set(requests.map((r:any)=>r.pattern_id))];
  const {data:patterns,error:patternError}=patternIds.length
    ? await admin.from("photo_patterns_v2").select("id,name,target_key").in("id",patternIds)
    : {data:[],error:null};
  if(patternError) return json(500,{error:"pattern_lookup_failed"});
  const byId=new Map((patterns||[]).map((p:any)=>[p.id,p]));

  const returnTarget=workflowTaskId
    ? `./cleaning.html?workflow_task_id=${encodeURIComponent(workflowTaskId)}`
    : `./cleaning.html?task_id=${encodeURIComponent(task.id)}`;

  const checklist=requests.map((r:any)=>{
    const p=byId.get(r.pattern_id) as any;
    const captureUrl=`./photo-camera.html?mode=verify&pattern_id=${encodeURIComponent(r.pattern_id)}&source_type=cleaning_task&source_id=${encodeURIComponent(task.id)}&purpose=cleaning&return_to=${encodeURIComponent(returnTarget)}`;
    return {
      request_id:r.id,
      kind:r.request_kind,
      ordinal:r.ordinal,
      completed:Boolean(r.completed_at),
      completed_at:r.completed_at,
      pattern:{id:r.pattern_id,name:p?.name||"Zona",target_key:p?.target_key||null},
      capture_url:readOnly?null:captureUrl
    };
  });

  return json(200,{
    ok:true,
    entry_kind:workflowTaskId?"workflow_task":"legacy_cleaning_task",
    read_only:readOnly,
    workflow_task_id:workflowTask?.id||null,
    workflow_execution_id:workflowExecution?.id||task.workflow_execution_id||null,
    task:{
      id:task.id,
      property_id:task.property_id,
      room_id:task.room_id,
      task_date:task.task_date,
      status:task.status,
      operational_status:workflowTask?.status||null
    },
    checklist
  });
});
