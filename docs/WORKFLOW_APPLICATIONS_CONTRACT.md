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

La publicación congela esa receta lógica en `workflow_definition_versions_v2`.

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

## 4. Reutilización

Una misma versión publicada puede aplicarse a muchos destinos.

Ejemplo:

`Limpieza semanal v1`

puede tener aplicaciones independientes en:

- Piso A;
- Piso B;
- Piso C.

No se duplican tres definiciones.

Para una misma definición y un mismo destino solo puede existir una aplicación `configured` a la vez. Archivar permite crear posteriormente otra aplicación explícita sin destruir la anterior.

## 5. Recursos concretos

La receta puede declarar que necesita un tipo de recurso, por ejemplo evidencia fotográfica.

Los recursos ligados físicamente a una vivienda —como `photo_patterns_v2`— no deben convertir la definición genérica en una receta específica de un piso.

La selección concreta de esos recursos pertenece a la configuración de la aplicación o a un incremento posterior de bindings de recursos. La ejecución futura congelará las versiones exactas realmente utilizadas.

No se duplican patrones dentro del workflow.

## 6. Publicación

`publish_workflow_definition_v1`:

- exige autenticación;
- exige `aal2`;
- valida autorización administrativa server-side;
- solo publica una definición con `authoring_complete=true`;
- crea una versión inmutable;
- es idempotente ante reintentos de la misma definición ya publicada;
- audita la publicación;
- **no selecciona un piso/habitación/ocupación**;
- **no crea una aplicación ni una ejecución**.

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

## 10. Límite de este incremento

Una aplicación `configured` **no significa que el flujo esté operativo**.

Aún faltan:

- entidad mínima de ejecución;
- `idempotency_key`;
- “Ejecutar ahora” idempotente;
- resolución de asignación;
- integración con `tenant_tasks_v2`;
- bindings concretos de recursos cuando correspondan;
- recurrencia automática;
- historial transversal de ejecución.

La siguiente capa debe consumir `workflow_applications_v2`; no debe volver a mezclar el UUID del destino dentro de la definición.
