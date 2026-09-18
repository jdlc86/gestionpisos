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

Las acciones específicas de workflow se derivarán de la versión publicada.

En este incremento solo se materializa el trabajo y se hace visible. No se habilita una transición que pueda dejar `tenant_tasks_v2.status` y `workflow_executions_v2.status` desincronizados.

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
- **no permite todavía completar/aceptar** una tarea de workflow hasta que la sincronización de estados esté implementada.

Esto evita presentar una acción parcialmente conectada como una capacidad terminada.

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

Aún no se implementan:

- sincronización de acciones tarea ↔ estado de ejecución;
- pasos de checklist/documento;
- binding de Banco Fotográfico;
- cierre/revisión;
- notificaciones;
- recurrencia automática;
- Historial transversal completo.

El siguiente incremento deberá hacer que las acciones permitidas por la receta muevan tarea y ejecución de forma atómica.
