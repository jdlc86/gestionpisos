export const WORKFLOW_DOMAIN_PRESETS=Object.freeze({
  cleaning:Object.freeze({
    scopeType:"property",
    triggerType:"recurring",
    recurrence:"weekly",
    assignmentType:"active_occupants_rotation",
    stepAccept:true,
    closeType:"domain_adapter"
  }),
  inspection:Object.freeze({
    scopeType:"property",
    triggerType:"manual",
    assignmentType:"property_responsible",
    stepPhoto:true,
    closeType:"human_review"
  }),
  maintenance:Object.freeze({
    scopeType:"property",
    triggerType:"event",
    eventType:"incident.created",
    assignmentType:"property_responsible",
    stepAccept:true,
    closeType:"domain_adapter"
  }),
  checkin:Object.freeze({
    scopeType:"property",
    triggerType:"event",
    eventType:"occupancy.created",
    assignmentType:"property_responsible",
    stepAccept:true,
    closeType:"domain_adapter"
  }),
  checkout:Object.freeze({
    scopeType:"property",
    triggerType:"event",
    eventType:"occupancy.offboarded",
    assignmentType:"property_responsible",
    stepAccept:true,
    closeType:"domain_adapter"
  })
});

function blank(value){
  return value===null
    ||value===undefined
    ||(typeof value==="string"&&value.trim()==="");
}

export function domainPresetPatch(flowType,current={},touchedFields=[]){
  const preset=WORKFLOW_DOMAIN_PRESETS[flowType];
  if(!preset)return {};

  const touched=touchedFields instanceof Set
    ?touchedFields
    :new Set(touchedFields||[]);
  const patch={};

  for(const [key,suggested] of Object.entries(preset)){
    if(touched.has(key))continue;

    if(typeof suggested==="boolean"){
      if(current[key]!==suggested)patch[key]=suggested;
      continue;
    }

    if(blank(current[key]))patch[key]=suggested;
  }

  return patch;
}
