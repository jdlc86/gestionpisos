# Contrato de evidencia fotográfica en Flujos de Trabajo

## Propósito

Integrar el paso `steps.photo=true` con el Banco Fotográfico y la infraestructura de fotoverificación ya existente, sin crear una segunda cámara, bucket, histórico ni sistema de revisión.

Cadena:

`Definición lógica → Aplicación concreta → Patrones vinculados → Ejecución → Snapshot de patrones → Tarea → Captura → photo_verification_run → Cierre del paso`

## 1. Dónde se elige el patrón

La definición publicada solo expresa que existe un paso de **Fotografía**.

No guarda el UUID de un patrón real porque los patrones pertenecen a pisos concretos.

Los patrones se seleccionan al crear la **Aplicación** sobre un piso/habitación/ocupación real.

Tabla:

`workflow_application_photo_resources_v2`

Reglas:

- uno o varios patrones;
- todos pertenecen a la misma organización y piso de la aplicación;
- deben estar activos;
- deben tener silueta manual guardada;
- no existen selecciones automáticas implícitas;
- el orden se conserva;
- una aplicación con ejecuciones ya creadas no puede cambiar silenciosamente sus recursos.

## 2. Ámbitos

En este incremento Fotografía necesita un piso concreto.

Se admite cuando la aplicación resuelve:

- piso;
- habitación;
- ocupación.

Una definición de ámbito organización con `steps.photo=true` no puede crear aplicación todavía, porque no existe un piso del que resolver patrones. Se rechaza explícitamente en vez de inventar uno.

## 3. Snapshot en la ejecución

Al crear una ejecución se congelan los patrones efectivos en:

`workflow_execution_photo_resources_v2`

Cada snapshot conserva:

- patrón original;
- versión;
- nombre/tipo/etiqueta;
- ruta de referencia;
- `contour_data` completo;
- orden;
- si la receta exige aceptar antes de capturar.

Modificar después el Banco Fotográfico no altera la guía de una ejecución ya creada.

El item de evidencia sigue enlazando al `pattern_id` real para trazabilidad histórica.

## 4. Protección del patrón

`private.photo_pattern_usage_v2` incorpora:

- aplicaciones de workflow;
- ejecuciones de workflow.

Un patrón ligado a una aplicación configurada o ejecución activa cuenta como uso activo. El ciclo de vida del Banco Fotográfico no puede eliminarlo mientras siga siendo recurso operativo.

## 5. Inicio del paso

RPC:

`start_workflow_photo_verification_v1(execution_photo_resource_id)`

Solo puede usarlo la persona asignada a la tarea/ejecución.

### Con paso Aceptar

Si `steps.accept=true`, la ejecución debe estar `active`. La captura no puede saltarse Aceptar.

### Sin paso Aceptar

Si la receta tiene Foto pero no Aceptar, la primera captura mueve de forma atómica:

`tarea pending → active`
`ejecución pending → active`

y deja histórico/evento.

## 6. Run fotográfico

Se reutiliza:

- `photo_verification_runs_v2`;
- `photo_verification_items_v2`;
- bucket privado `photo-verification`.

Se añade:

`source_type='workflow_execution'`

Un cliente authenticated no puede insertar directamente un run con ese source_type. Debe usar el RPC server-side del workflow.

El run conserva:

- actor asignado;
- organización/piso/habitación;
- `source_id=workflow_execution.id`;
- `purpose='general'` en este primer incremento;
- `verification_mode='manual'`.

Limpieza mantiene su semántica propia y no se reinterpreta.

## 7. Guía congelada

La cámara sigue siendo `photo-camera.html`.

Cuando recibe `workflow_resource_id`, la guía se construye desde `pattern_snapshot.contour_data`, no desde el patrón mutable actual.

Así la cámara reproduce exactamente la silueta congelada al crear la ejecución.

## 8. Envío transaccional

RPC:

`submit_workflow_photo_verification_v1(run_id,item_id,request_key)`

Valida en servidor:

- usuario asignado;
- identidad run ↔ ejecución ↔ recurso;
- patrón esperado;
- storage_path exacto;
- existencia del JPEG privado;
- propietario del objeto;
- estado de tarea/ejecución sincronizado.

En una única transacción:

1. run pasa a `submitted`;
2. recurso fotográfico pasa a `submitted`;
3. se registra evento de evidencia;
4. si era la última foto, se decide el siguiente estado;
5. tarea + ejecución se actualizan juntas cuando corresponde;
6. se registra histórico/auditoría.

## 9. Idempotencia

Cada envío usa `request_key`.

Un reintento no puede:

- duplicar transición;
- duplicar evento;
- duplicar cierre.

El estado `submitted` del recurso y el evento único constituyen barreras adicionales.

## 10. Cierre después de fotografías

Cuando se han enviado todas las fotografías:

- si quedan checklist/documento → continúa `active`;
- si no quedan otros pasos y `closeType=auto` → tarea + ejecución `completed`;
- si no quedan otros pasos y `closeType=human_review` → tarea + ejecución `waiting_review`;
- reglas especializadas todavía no soportadas permanecen activas.

No se completa un flujo ignorando pasos pendientes.

## 11. Tareas

`workflow-tasks.html` consulta los snapshots visibles por RLS.

Para cada foto muestra:

- nombre del patrón congelado;
- estado pendiente/capturando/enviada;
- “Hacer foto” o “Continuar foto” cuando corresponde;
- “Acepta primero” si la receta exige aceptación.

No se crea una acción artificial `complete`.

## 12. Seguridad

- RLS en tablas de bindings/snapshots.
- Sin INSERT/UPDATE/DELETE directo para authenticated.
- Aplicaciones: ROOT/ADMIN autorizados.
- Snapshot de ejecución: visible al asignado y administración autorizada.
- Inicio/envío: solo asignado.
- `source_type=workflow_execution` no es insertable directamente por cliente.
- Organización, piso, patrón, run y recurso se derivan/validan server-side.

## 13. Fuera de este incremento

Todavía no se implementa:

- revisión humana del workflow;
- reacción del workflow a aprobar/rechazar una foto;
- IA de estado;
- checklist;
- documento;
- notificaciones;
- recurrencias automáticas;
- adaptador de Limpieza al motor transversal.

La evidencia existente de Limpieza permanece intacta.
