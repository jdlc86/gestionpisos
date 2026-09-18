# Contrato de materialización de tareas de Flujos de Trabajo

## Propósito

Reutilizar `tenant_tasks_v2` como núcleo de tareas sin inventar un inquilino cuando la ejecución pertenece a una organización, piso o habitación.

Cadena:

`Definición → Versión → Aplicación → Ejecución → Tarea materializada → Pasos/acciones → Recursos/Evidencias → Cierre`

## 1. Decisión de compatibilidad

Se conserva el nombre físico `tenant_tasks_v2` para no romper el producto existente.

La tabla pasa a admitir dos familias:

1. **Tarea legacy de inquilino**
   - `tenant_id IS NOT NULL`;
   - creada por los RPC existentes;
   - conserva su comportamiento actual.

2. **Tarea generada por workflow**
   - `source_kind='workflow_execution'`;
   - `source_id=<workflow_executions_v2.id>`;
   - `tenant_id` puede ser NULL;
   - `assigned_user_id` es obligatorio;
   - `task_type='workflow'`.

No se crea una tabla paralela `workflow_tasks`.

## 2. Invariante de tenant_id

Relajar `tenant_id NOT NULL` no significa hacerlo opcional para todo.

Constraint obligatoria:

- si la tarea NO procede de `workflow_execution`, debe conservar `tenant_id`;
- si procede de workflow, debe tener `source_id` y `assigned_user_id`.

Para ámbito `occupancy`, el materializador puede conservar también el `tenant_id` real si la ocupación lo tiene. Para organización/piso/habitación no se fabrica ninguno.

## 3. Enlace ejecución ↔ tarea

Se reutilizan:

- `source_kind`;
- `source_id`.

Para workflows:

`source_kind = 'workflow_execution'`
`source_id = workflow_executions_v2.id`

Un índice único parcial sobre `source_id` para ese `source_kind` garantiza una sola tarea por ejecución.

La función server-side vuelve a validar que `source_id` corresponde a una ejecución real antes de insertar.

## 4. Materialización idempotente

RPC:

`materialize_workflow_execution_task_v1(execution_id)`

Reglas:

- autenticación obligatoria;
- autorización administrativa para este primer incremento;
- si ya existe la tarea, devuelve la existente;
- si no existe, la crea exactamente una vez;
- deriva organización, ámbito, asignado y snapshot desde la ejecución;
- no acepta esos datos desde el navegador;
- registra histórico de tarea, evento de ejecución y auditoría.

La creación de nuevas ejecuciones debe invocar el mismo helper interno para que “Ejecutar ahora” termine con ejecución + tarea en una única transacción.

La migración materializa de forma idempotente las ejecuciones `pending` que ya existieran antes del cambio.

## 5. Tipo de tarea workflow

Se añade `task_type='workflow'`.

No se reutiliza `generic` porque sus plantillas actuales pertenecen al actor `tenant`; hacerlo para una tarea sin inquilino concedería una semántica incorrecta.

Las acciones específicas de workflow se derivan del `spec_snapshot` congelado de la ejecución.

El primer incremento de acciones soporta `steps.accept=true` conforme a `WORKFLOW_ACTIONS_CONTRACT.md`. Ninguna acción de workflow puede usar el RPC legacy si eso permite cambiar solo la tarea.

## 6. RLS y privilegios

- `anon`: sin acceso a tablas/RPC nuevos.
- `authenticated`: SELECT sujeto a RLS; sin INSERT/UPDATE/DELETE directo.
- ROOT/ADMIN conservan lectura por organización.
- el usuario asignado puede leer su tarea.
- acciones e histórico heredan la visibilidad de la tarea.
- creación y futuras transiciones pasan por RPC.

La visibilidad del botón no concede permisos.

## 7. Pantalla Tareas

`Flujos de Trabajo → Tareas` deja de ser un placeholder.

La primera versión:

- lista tareas visibles por RLS;
- muestra título, origen, ámbito, asignado/propiedad cuando corresponda, estado y fecha;
- identifica las generadas por workflow;
- permite abrir el vínculo conceptual con la ejecución;
- muestra únicamente acciones derivadas de la receta y válidas para el estado actual;
- las acciones de workflow usan un RPC que actualiza tarea + ejecución de forma atómica;
- una receta con pasos todavía no implementados no recibe una acción de cierre artificial.

Esto evita presentar una transición parcialmente conectada como una capacidad terminada.

## 8. Idempotencia

Dos barreras:

1. `workflow_executions_v2(application_id,idempotency_key)`;
2. `tenant_tasks_v2(source_kind='workflow_execution',source_id)` único.

Un reintento técnico no puede producir dos ejecuciones ni dos tareas.

## 9. Factory reset

Las nuevas tablas de workflow y las tareas materializadas son datos operativos de prueba.

El helper de factory reset debe incluir explícitamente:

- `workflow_execution_events_v2`;
- `workflow_executions_v2`;
- `workflow_applications_v2`;
- `workflow_definition_versions_v2`;
- `workflow_definitions_v2`;

en un orden compatible con FKs, sin usar CASCADE indiscriminado.

## 10. Fuera de este incremento

La sincronización atómica del primer paso `accept` ya está definida en `WORKFLOW_ACTIONS_CONTRACT.md`.

Aún no se implementan:

- evidencia fotográfica;
- checklist/documento;
- revisión humana operativa;
- cancelación;
- binding de Banco Fotográfico;
- notificaciones;
- recurrencia automática;
- Historial transversal completo.

El siguiente incremento debe implementar el primer paso de evidencia/recurso sin permitir cerrar una ejecución que conserve requisitos pendientes.
