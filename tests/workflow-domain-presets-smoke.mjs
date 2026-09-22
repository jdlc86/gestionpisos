import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  WORKFLOW_DOMAIN_PRESETS,
  domainPresetPatch
} from "../docs/workflow-domain-presets.js";

assert.deepEqual(
  Object.keys(WORKFLOW_DOMAIN_PRESETS).sort(),
  ["checkin","checkout","cleaning","inspection","maintenance"]
);

const cleaning=domainPresetPatch("cleaning",{});
assert.equal(cleaning.scopeType,"property");
assert.equal(cleaning.triggerType,"recurring");
assert.equal(cleaning.recurrence,"weekly");
assert.equal(cleaning.assignmentType,"active_occupants_rotation");
assert.equal(cleaning.stepAccept,true);
assert.equal(cleaning.closeType,"domain_adapter");
assert.equal("scheduledAt" in cleaning,false);

const inspection=domainPresetPatch("inspection",{});
assert.equal(inspection.scopeType,"property");
assert.equal(inspection.triggerType,"manual");
assert.equal(inspection.assignmentType,"property_responsible");
assert.equal(inspection.stepPhoto,true);
assert.equal(inspection.closeType,"human_review");

const preserved=domainPresetPatch(
  "inspection",
  {scopeType:"room",triggerType:"manual",stepPhoto:false},
  new Set(["stepPhoto"])
);
assert.equal("scopeType" in preserved,false);
assert.equal("triggerType" in preserved,false);
assert.equal("stepPhoto" in preserved,false);
assert.equal(preserved.assignmentType,"property_responsible");
assert.equal(preserved.closeType,"human_review");

assert.equal(domainPresetPatch("maintenance",{}).eventType,"incident.created");
assert.equal(domainPresetPatch("checkin",{}).eventType,"occupancy.created");
assert.equal(domainPresetPatch("checkout",{}).eventType,"occupancy.offboarded");

for(const flowType of ["custom","rent_payment","rent_claim","deposit_receipt","deposit_review","damage_claim"]){
  assert.deepEqual(domainPresetPatch(flowType,{}),{});
}

const builderSource=readFileSync(
  new URL("../docs/workflow-builder.js",import.meta.url),
  "utf8"
);
const applyDraftStart=builderSource.indexOf("function applyDraft(");
const applyDraftEnd=builderSource.indexOf("\nfunction restoreLocalDraft",applyDraftStart);
assert.ok(applyDraftStart>=0&&applyDraftEnd>applyDraftStart);
assert.equal(
  builderSource.slice(applyDraftStart,applyDraftEnd).includes("applySelectedDomainPreset"),
  false
);
assert.match(
  builderSource,
  /if\(event\.target===field\("flowType"\)\)\{\s*applySelectedDomainPreset\(\)/
);

for(const preset of Object.values(WORKFLOW_DOMAIN_PRESETS)){
  assert.equal("scheduledAt" in preset,false);
  assert.equal("scheduledTimezone" in preset,false);
  assert.equal("scheduledAtUtc" in preset,false);
}

console.log("workflow-domain-presets smoke: ok");
