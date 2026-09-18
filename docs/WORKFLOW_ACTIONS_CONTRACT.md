# Contrato de acciones atómicas de tareas de Flujos de Trabajo

## Propósito

Conectar una tarea materializada con su `workflow_execution_v2` sin permitir estados divergentes.

Cadena:

`Tarea visible → Acción autorizada → Transacción única → Tarea + Ejecución + Históricos`

## 1. Principio principal

Una acción de una tarea de workflow nunca actualiza solo `tenant_tasks_v2`.

Toda transición debe actualizar en la misma transacción:

- `tenant_tasks_v2.status`;
- `workflow_executions_v2.status`;
- `tenant_task_history_v2`;
- `workflow_execution_events_v2`;
- auditoría cuando corresponda.

Si cualquiera de esos pasos falla, la transacción completa falla.

## 2. Separación de RPC legacy

Las tareas legacy continúan usando:

`apply_tenant_task_action_v2(...)`

Una tarea con:

- `task_type='workflow'`; o
- `source_kind='workflow_execution'`

debe ser rechazada por ese RPC con `workflow_task_requires_atomic_action`.

Las tareas de workflow usan:

`apply_workflow_task_action_v1(task_id, action_key, request_key, note)`

## 3. Puerta de decisión Aceptar / Rechazar

Por compatibilidad con las versiones ya publicadas, el campo técnico sigue siendo:

`steps.accept=true`

Su significado de producto es:

**Requerir decisión del asignado: Aceptar / Rechazar.**

Cuando está habilitado, `workflow_seed_task_actions_internal_v1` debe publicar una pareja coherente de acciones desde `pending`:

- `accept`;
- `reject`.

No debe publicarse únicamente una de las dos si el servidor no puede determinar un destino seguro para Aceptar.

### Aceptar

La transición se deriva así:

- si quedan pasos de foto/checklist/documento → `pending → active`;
- si no quedan otros pasos y `closeType=auto` → `pending → completed`;
- si no quedan otros pasos y `closeType=human_review` → `pending → waiting_review`.

Etiquetas:

- `active`: “Aceptar”;
- `completed`: “Aceptar y completar”;
- `waiting_review`: “Aceptar y enviar a revisión”.

### Rechazar

`reject` siempre exige un **motivo obligatorio** y, en este incremento, realiza:

`pending → rejected`

en tarea y ejecución dentro de la misma transacción.

Si la ejecución había congelado recursos fotográficos todavía pendientes, esos recursos pasan a `cancelled`. Un rechazo no genera un run fotográfico ni marca la ejecución como completada.

El histórico conserva el motivo, actor, estado de origen y estado final.

## 4. Autorización

Las acciones `accept` y `reject` pertenecen al actor `assignee`.

El servidor exige:

- usuario autenticado;
- tarea de workflow;
- ejecución vinculada;
- mismo `assigned_user_id` en tarea y ejecución;
- `auth.uid() = assigned_user_id`;
- acción activa para el estado actual;
- tarea y ejecución en el mismo estado antes de transicionar.

ROOT o ADMIN no pueden saltarse la asignación salvo que sean la persona asignada.

## 5. Idempotencia

Cada intención cliente incluye `request_key`.

La ejecución registra `task_action_applied` con:

- `task_id`;
- `action_key`;
- `request_key`.

Existe una restricción única por `execution_id + request_key` para eventos de acción.

Repetir la misma solicitud:

- devuelve el estado ya alcanzado;
- no repite el histórico;
- no repite el evento;
- no vuelve a aplicar la transición.

Reutilizar la misma clave para otra acción se rechaza como conflicto.

## 6. Estados sincronizados

Las tareas de workflow y la ejecución comparten los estados de alto nivel:

- `pending`;
- `active`;
- `waiting_review`;
- `completed`;
- `cancelled`;
- `failed`;
- `rejected`.

Antes de aplicar una acción el servidor exige:

`task.status = execution.status`

Un rechazo queda explícitamente en `rejected`; no se disfraza como `completed`.

## 7. Cierre automático

Si la receta contiene únicamente la puerta de decisión y `closeType=auto`, Aceptar satisface todos los pasos configurados:

`pending → completed`

y fija `workflow_executions_v2.completed_at`.

Rechazar no fija `completed_at`.

## 8. Recetas con otros pasos

Si después de Aceptar quedan fotografía, checklist o documento, la ejecución pasa a `active`.

La evidencia fotográfica ya puede completar su propio paso conforme a `WORKFLOW_PHOTO_EVIDENCE_CONTRACT.md`.

Checklist y documento siguen sin poder simularse mediante una transición genérica.

## 9. Interfaz

`Flujos de Trabajo → Tareas`:

- muestra las acciones activas cuyo `from_status` coincide con el estado actual;
- presenta Aceptar y Rechazar como una decisión del asignado;
- solicita el motivo al pulsar Rechazar;
- usa el RPC atómico;
- conserva la clave de reintento durante errores de resultado incierto;
- recarga la tarea tras una respuesta concluyente;
- no habilita Foto antes de Aceptar cuando la receta exige esta decisión.

El Creador presenta el paso como:

**Requerir decisión del asignado: Aceptar / Rechazar**

aunque el contrato persistente mantenga la clave histórica `steps.accept`.

## 10. Revisión humana

Cuando `closeType=human_review`, completar los pasos operativos no cierra automáticamente el workflow. Tarea + ejecución pasan juntas a:

`waiting_review`

La revisión reutiliza infraestructura existente y distingue dos casos.

### Sin evidencia fotográfica

Para recetas que llegan a `waiting_review` sin recursos Foto, `tenant_task_actions_v2` publica acciones de actor `agency`:

- `review_approve`: **Aprobar revisión** → `waiting_review → completed`;
- `review_reject`: **Rechazar revisión** → `waiting_review → rejected`, con motivo obligatorio.

En este primer incremento, `agency` significa ROOT activo o ADMIN activo de la organización, validado server-side mediante el contrato de gestión de workflows.

El asignado normal puede ver que su tarea espera revisión, pero no adquiere capacidad de aprobarse a sí mismo por ser el asignado.

### Con evidencia fotográfica

Si la ejecución contiene recursos Foto, **no se publican acciones agency genéricas en la tarea**. La decisión se realiza desde la revisión de Fotoverificaciones para que el revisor vea la evidencia real.

`apply_workflow_photo_review_v1` reutiliza `apply_photo_verification_review_v2` y mantiene la transición del workflow en la misma transacción lógica:

- cada run queda `approved` o `rejected`;
- el workflow permanece `waiting_review` mientras exista alguna foto sin decisión;
- cuando todas están revisadas, si todas están aprobadas → tarea + ejecución `completed`;
- cuando todas están revisadas y al menos una está rechazada → tarea + ejecución `rejected`;
- el rechazo conserva los motivos de las evidencias;
- los reintentos de la misma decisión no duplican histórico.

La UI de Tareas enlaza a Fotoverificaciones filtrada por `workflow_execution_id`; no ofrece aprobación “a ciegas” sin mostrar la imagen.

### Historial

El cierre de revisión registra:

- `tenant_task_history_v2` con `review_approve` o `review_reject`;
- `workflow_execution_events_v2`;
- `audit_log_v2`;
- revisor y decisión de cada `photo_verification_run_v2` cuando existe Foto.

## 11. Reasignación y notificaciones

El estado `rejected` deja la ejecución cerrada como rechazo y conserva la Aplicación, por lo que administración puede iniciar una nueva ejecución y asignarla de nuevo sin alterar el histórico rechazado.

La notificación automática al responsable y un asistente específico de reasignación deben reutilizar `notifications_v2` y la infraestructura común cuando se implementen; no se crea un sistema paralelo dentro de esta migración.

## 12. Fuera de este incremento

Siguen pendientes:

- asistente automático de reasignación tras rechazo;
- notificación operativa específica de rechazo;
- checklist;
- documento;
- recurrencia automática;
- adaptadores de dominio.

Ninguna de esas capacidades puede simularse cambiando estados sin contrato.
