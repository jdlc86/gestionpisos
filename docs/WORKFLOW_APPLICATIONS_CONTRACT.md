# Contrato de aplicaciones de Flujos de Trabajo

## Propósito

Separar de forma explícita la **receta reutilizable** del **destino real** donde se instala esa receta.

Cadena canónica:

`Definición → Versión publicada → Aplicación concreta → Disparador → Ejecución → Asignación → Tareas → Recursos → Evidencias → Revisión/Cierre → Historial`

## 1. Definición y versión publicada

La definición expresa lógica reutilizable.

Ejemplo:

- nombre: `Limpieza semanal`;
- ámbito lógico: `property`;
- disparador: semanal;
- asignación: responsable operativo del piso;
- pasos: aceptar + evidencia fotográfica;
- cierre: automático.

`scopeType=property` significa **“esta receta se ejecuta sobre un piso”**. No contiene el UUID de un piso concreto.

La configuración terminada se representa en `workflow_definition_versions_v2`. Mientras la definición no tenga ejecuciones puede actualizarse en sitio; desde la primera ejecución la versión utilizada queda congelada para historial.

## 2. Aplicación concreta

Una aplicación vincula una versión publicada a una entidad real.

Ejemplos:

- `Limpieza semanal v1 → Piso Gran Vía`;
- `Inspección habitación v2 → Piso Alcalá → Habitación 3`;
- `Check-out v1 → ocupación vigente de una persona`;
- `Cierre mensual v1 → toda la organización`.

La entidad se identifica siempre por UUID real y se valida server-side contra organización, relaciones y estado vigente. Un nombre visible nunca es una credencial.

Tabla: `workflow_applications_v2`.

En este incremento una aplicación solo puede estar:

- `configured`: vínculo válido y preparado, pero **todavía no genera ejecuciones**;
- `archived`: vínculo retirado sin borrar histórico.

No existe todavía un estado `active` porque el motor transversal de ejecución/recurrencia aún no está implementado.

## 3. Forma del ámbito

La versión publicada determina el tipo de selector permitido.

### Organización

No requiere entidad adicional.

### Piso

Requiere un `property_id` de `properties_v2` perteneciente a la misma organización y no archivado.

### Habitación

La UI selecciona primero un piso y después una habitación de ese piso.

Persistencia:

- `property_id`;
- `room_id`.

El servidor valida `rooms_v2.property_id = property_id`.

### Ocupación / inquilino

La UI puede usar el piso como filtro de navegación y después seleccionar una ocupación vigente.

Persistencia:

- `property_id`;
- `occupancy_id`.

El servidor valida organización, pertenencia al piso y vigencia de la ocupación.

## 4. Flujo terminado y destino actual

En la UX vigente el destino forma parte de la finalización del flujo:

`Diseño → Destino → Listo → Publicar/Ejecutar`.

Por tanto, un flujo nuevo no aparece en **Mis Flujos** sin una aplicación/destino coherente con su ámbito. La tabla `workflow_applications_v2` sigue separando técnicamente receta y entidad real para mantener validación, recursos e historial.

Mientras el flujo nunca se haya ejecutado:

- **Editar** conserva la misma definición lógica y la misma versión actual;
- cambiar el destino reemplaza la aplicación configurada anterior;
- no se crea una versión histórica solo por corregir/configurar el flujo;
- **Eliminar** puede retirar definición, versión y aplicación porque no existe ejecución que reproducir.

Desde la primera ejecución:

- la aplicación utilizada por esa ejecución permanece asociada a su versión original;
- una edición futura publica vN+1 y prepara la aplicación vigente de esa nueva versión;
- las aplicaciones anteriores se archivan, no se reinterpretan;
- el historial siempre puede reconstruir la versión/destino exactos que generaron cada tarea.

Si se necesita otro proceso lógico diferente para otro conjunto de pisos, se crea otro flujo desde el Creador; la UX no ofrece una acción genérica **Duplicar**.

## 5. Recursos concretos

La receta puede declarar que necesita un tipo de recurso, por ejemplo evidencia fotográfica.

Los recursos ligados físicamente a una vivienda —como `photo_patterns_v2`— no deben convertir la definición genérica en una receta específica de un piso.

La selección concreta de esos recursos pertenece a la configuración de la aplicación o a un incremento posterior de bindings de recursos. La ejecución futura congelará las versiones exactas realmente utilizadas.

No se duplican patrones dentro del workflow.

## 6. Publicar y Ejecutar desde Listo

La finalización de un flujo nuevo usa `publish_workflow_ready_v1` como operación atómica.

**Publicar**:

- exige autenticación y `aal2`;
- valida autoría completa;
- crea/publica definición + versión;
- valida y crea el destino mediante la infraestructura de aplicaciones;
- vincula recursos concretos, incluidos patrones fotográficos cuando corresponda;
- es idempotente por `creation_request_key`;
- **no crea ejecución ni tarea**.

**Ejecutar** usa la misma finalización y además invoca el runner existente. Antes de materializar trabajo se vuelven a validar destino, vigencia de ocupación, asignación y recursos. El resultado es como máximo una ejecución idempotente y una tarea de `tenant_tasks_v2`.

Los RPC históricos `publish_workflow_definition_v1` y `create_workflow_application_v2` se conservan como primitivas internas/compatibilidad, pero la UX integrada no obliga al usuario a recorrerlas manualmente.

## 7. Crear aplicación

`create_workflow_application_v1`:

- recibe una versión publicada;
- exige `aal2`;
- resuelve organización desde la versión, no desde el cliente;
- valida el tipo lógico de ámbito;
- valida IDs reales contra las tablas canónicas;
- bloquea referencias cruzadas entre organizaciones;
- es idempotente para el mismo destino + misma versión;
- audita la creación;
- no crea tareas, notificaciones ni recurrencias.

## 8. Archivar aplicación

`archive_workflow_application_v1`:

- es explícito y auditado;
- conserva la fila histórica;
- no borra versiones ni definiciones;
- permite volver a aplicar posteriormente una versión mediante una nueva fila.

## 9. Seguridad

- RLS obligatoria en `workflow_applications_v2`.
- `anon` no ejecuta RPC administrativos.
- `authenticated` no puede hacer INSERT/UPDATE/DELETE directo sobre aplicaciones.
- ROOT/ADMIN solo leen dentro del contrato vigente.
- La autoridad efectiva se comprueba en backend.
- La UI nunca convierte la visibilidad de un botón en permiso.
- Publicar/aplicar/archivar requieren `aal2`.

## 10. Límite y siguiente capa

Una aplicación `configured` **no significa por sí sola que exista trabajo materializado**.

La siguiente capa ya consume `workflow_applications_v2` mediante el contrato `WORKFLOW_EXECUTION_CONTRACT.md`: crea ejecuciones `manual_now` idempotentes, congela asignación y registra el evento inicial.

Siguen fuera de Aplicaciones:

- materialización de tareas;
- bindings concretos de recursos cuando correspondan;
- recurrencia automática;
- ciclo de vida completo de ejecución.

El UUID del destino permanece exclusivamente en la aplicación/ejecución concreta; no vuelve a la definición lógica.


## 11. Recursos fotográficos concretos

Cuando la versión publicada contiene `steps.photo=true`, la definición sigue siendo lógica y no almacena UUIDs de patrones.

La creación de la aplicación usa `create_workflow_application_v2` y exige seleccionar explícitamente uno o varios patrones reales del piso. Los vínculos viven en `workflow_application_photo_resources_v2`.

El RPC anterior `create_workflow_application_v1` permanece para versiones sin Fotografía y rechaza versiones fotográficas con `workflow_photo_application_requires_v2`. Esto impide crear una aplicación fotográfica aparentemente configurada pero sin recursos.

Una vez que existe una ejecución, los recursos de la aplicación quedan bloqueados para evitar reinterpretar el histórico. Cada ejecución congela su propia versión del patrón conforme a `WORKFLOW_PHOTO_EVIDENCE_CONTRACT.md`.
