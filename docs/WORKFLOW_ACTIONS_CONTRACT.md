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

debe ser rechazada por ese RPC con un error explícito. Así no existe una ruta alternativa capaz de cambiar solo la tarea.

Las tareas de workflow usan:

`apply_workflow_task_action_v1(task_id, action_key, request_key, note)`

## 3. Fuente de acciones visibles

Se reutiliza `tenant_task_actions_v2`.

Las acciones de workflow no proceden de las plantillas legacy `tenant_task_workflow_templates_v2`; se derivan del `spec_snapshot` congelado de la ejecución.

Primer paso soportado:

- `steps.accept=true` → acción del asignado.

La transición de `accept` se deriva así:

- si quedan pasos de foto/checklist/documento → `pending → active`;
- si no quedan otros pasos y `closeType=auto` → `pending → completed`;
- si no quedan otros pasos y `closeType=human_review` → `pending → waiting_review`;
- si no puede determinarse un destino seguro, la acción no se publica todavía.

Etiquetas:

- `completed`: “Aceptar y completar”;
- `waiting_review`: “Aceptar y enviar a revisión”;
- `active`: “Aceptar”.

## 4. Autorización

En este incremento la acción `accept` pertenece al actor `assignee`.

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

El cliente conserva esa clave mientras no tenga una respuesta concluyente.

La ejecución registra el evento:

`task_action_applied`

con:

- `task_id`;
- `action_key`;
- `request_key`.

Existe una restricción única por:

`execution_id + request_key`

para eventos de acción.

Repetir la misma solicitud:

- devuelve el estado ya alcanzado;
- no repite el histórico de tarea;
- no repite el evento;
- no vuelve a aplicar la transición.

Reutilizar la misma clave para otra acción se rechaza como conflicto.

## 6. Estados sincronizados

En esta fase las tareas de workflow usan los mismos estados de alto nivel que la ejecución:

- `pending`;
- `active`;
- `waiting_review`;
- `completed`;
- `cancelled`;
- `failed`.

Antes de aplicar una acción el servidor exige:

`task.status = execution.status`

Si no coincide, se rechaza con un error de integridad operacional; no se intenta “arreglar” silenciosamente.

## 7. Cierre automático

Si la receta contiene únicamente el paso `accept` y `closeType=auto`, aceptar satisface todos los pasos configurados.

Por tanto, la transición válida es:

`pending → completed`

y se fija `workflow_executions_v2.completed_at`.

No se añade una acción “Completar” artificial que no exista en la receta.

## 8. Recetas con pasos todavía no implementados

Si después de aceptar quedan:

- fotografía;
- checklist;
- documento;

la ejecución pasa a `active`.

No se publica una acción de cierre hasta que esos pasos tengan persistencia y validación propias.

Esto impide completar una ejecución ignorando requisitos de la receta.

## 9. Interfaz

La pantalla `Flujos de Trabajo → Tareas`:

- consulta las acciones activas visibles para cada tarea;
- muestra solo acciones cuyo `from_status` coincide con el estado actual;
- utiliza el RPC atómico para tareas de workflow;
- conserva la clave de reintento durante errores de red/resultado incierto;
- elimina la clave después de una respuesta concluyente;
- recarga la tarea tras aplicar la acción.

Cuando una acción implica cierre automático, la etiqueta debe hacerlo explícito.

## 10. Fuera de este incremento

Siguen pendientes:

- captura/evidencia fotográfica;
- checklist;
- documento;
- revisión humana;
- cancelación operativa;
- notificaciones;
- recurrencia automática;
- adaptadores de dominio.

Ninguno de esos pasos puede simularse mediante una transición genérica para hacer avanzar una tarea.
