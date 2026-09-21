#!/usr/bin/env bash
set -euo pipefail
trap 'echo "incidents-smoke failed at line $LINENO: $BASH_COMMAND" >&2' ERR

test -s docs/incidents.html
test -s docs/incidents.css
test -s docs/incidents.js
node --check docs/incidents.js
node --check docs/workflow-builder.js
node --check docs/workflow-tasks.js
node --check docs/workflow-history.js

# La pantalla opera con sesión y RPC server-side; no escribe directamente el expediente.
grep -Fq './auth-guard.js' docs/incidents.html
grep -Fq 'supabase.rpc("open_workflow_incident_v1"' docs/incidents.js
grep -Fq 'supabase.rpc("submit_incident_information_v1"' docs/incidents.js
grep -Fq 'supabase.from("incidents_v2")' docs/incidents.js
grep -Fq 'supabase.from("incident_updates_v2")' docs/incidents.js
! grep -Eq 'from\("incidents_v2"\)\.(insert|update|delete)' docs/incidents.js
! grep -Eq 'from\("incident_updates_v2"\)\.(insert|update|delete)' docs/incidents.js
grep -Fq 'incident.status!=="waiting_info"' docs/incidents.js
grep -Fq 'result?.created_new===false' docs/incidents.js
grep -Fq 'result?.applied_new===false' docs/incidents.js

# Mantenimiento e inspección se configuran mediante los eventos y recursos comunes.
grep -Fq 'value="incident.created"' docs/workflow-builder.html
grep -Fq 'value="incident.resolved"' docs/workflow-builder.html
grep -Fq 'id="wf05StepNote"' docs/workflow-builder.html
grep -Fq 'if(maintenance)eventType.value="incident.created"' docs/workflow-builder.js
grep -Fq 'data.eventType==="incident.resolved"&&!inspectionEvidence' docs/workflow-builder.js
grep -Fq 'const wf05Event=["incident.created","incident.resolved"].includes(data.eventType)' docs/workflow-builder.js
grep -Fq 'if(eventType==="incident.created")return "Incidencia abierta"' docs/workflow-definitions.js
grep -Fq 'if(eventType==="incident.resolved")return "Incidencia resuelta"' docs/workflow-applications.js

# La misma tarjeta transversal presenta las acciones y el histórico WF-05.
grep -Fq 'action.action_key==="request_info"' docs/workflow-tasks.js
grep -Fq 'action.action_key==="continue"' docs/workflow-tasks.js
grep -Fq 'action.action_key==="resolve"' docs/workflow-tasks.js
grep -Fq 'workflow_wf05_subject_not_current' docs/workflow-tasks.js
grep -Fq 'workflow_wf05_information_response_required' docs/workflow-tasks.js
grep -Fq 'case "wf05_domain_action"' docs/workflow-history.js

# Persistencia, dispatcher e idempotencia permanecen versionados y cubiertos.
test -s supabase/migrations/20260921062822_wf05_incident_domain_core.sql
test -s supabase/migrations/20260921064050_wf05_incident_event_workflow_link.sql
test -s supabase/migrations/20260921065433_wf05_incident_domain_actions.sql
test -s tests/workflow-wf05-domain-regression.sql
grep -Fq "'incident.created'" supabase/migrations/20260921064050_wf05_incident_event_workflow_link.sql
grep -Fq "'incident.resolved'" supabase/migrations/20260921064050_wf05_incident_event_workflow_link.sql
grep -Fq 'apply_workflow_task_action_v1' supabase/migrations/20260921065433_wf05_incident_domain_actions.sql
grep -Fq 'workflow-wf05-domain-regression.sql' tests/database-regression-v2.sh

echo "incidents-smoke: ok"
