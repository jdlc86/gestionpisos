# Contrato de ejecución manual de Flujos de Trabajo

## Propósito

Este contrato define el primer runner transversal de GestionPisos. Consume una `workflow_application_v2` ya configurada y crea una ejecución persistente e idempotente.

Cadena canónica:

`Definición → Versión publicada → Aplicación concreta → Ejecutar ahora → Ejecución → Asignación → futura tarea → Recursos/Evidencias → Cierre → Historial`

## 1. Qué significa “Ejecutar ahora”

“Ejecutar ahora” es un disparo manual explícito de una aplicación concreta.

No cambia el disparador configurado en la receta. `Ejecutar ahora` solo está permitido para recetas de activación manual. `scheduled_once`, `recurring` y `event` se ejecutan exclusivamente por su disparador automático y la UI no los ofrece en ejecución manual o masiva.

Una ejecución manual registra `trigger_kind=manual_now`. Una ejecución originada por WF-02 registra `trigger_kind=event`.

Cada pulsación manual intencional puede crear una ejecución nueva. Los reintentos técnicos de la misma pulsación reutilizan la misma `idempotency_key` y no duplican la ejecución. Para eventos, el dispatcher usa `event:<event_id>` y `workflow_event_dispatches_v2` impide despachar dos veces la misma pareja evento/aplicación.

## 2. Entidad de ejecución

Tabla: `workflow_executions_v2`.

Cada ejecución conserva:

- aplicación concreta;
- definición y versión publicada;
- organización y ámbito real;
- `trigger_kind`;
- `idempotency_key`;
- regla de asignación;
- usuario finalmente asignado;
- snapshot de la especificación publicada;
- estado;
- actor e instante de creación.

La ejecución nunca vuelve a resolver silenciosamente su asignado después de creada.

Estados reservados:

- `pending`;
- `active`;
- `waiting_review`;
- `completed`;
- `cancelled`;
- `failed`;
- `rejected`.

La creación inicial produce `pending`. Los incrementos posteriores pueden mover la ejecución mediante acciones atómicas validadas.

## 3. Idempotencia

La clave única es:

`application_id + idempotency_key`

El cliente genera una clave por intención de “Ejecutar ahora” y la conserva mientras no tenga confirmación del servidor.

Si el mismo request se reintenta:

- devuelve la ejecución existente;
- no crea una segunda fila;
- no crea un segundo evento;
- no recalcula la asignación.

## 4. Autorización para lanzar

En este primer incremento puede lanzar una ejecución:

- ROOT activo;
- ADMIN activo de la organización.

La autorización se valida en servidor. Ver un botón no concede capacidad. La extensión futura al responsable/operador de piso se hará cuando exista una vista operativa de Tareas; la pantalla actual de Aplicaciones sigue siendo administrativa.

## 5. Asignación

### Manual

`assignmentType=manual` exige seleccionar un usuario al iniciar.

El usuario elegido debe mantener una relación operativa vigente con el destino:

- organización: ADMIN o EMPLOYEE activo de la organización;
- piso/habitación: ADMIN o EMPLOYEE actualmente asociado al piso, o inquilino con ocupación activa dentro del destino;
- ocupación: únicamente el inquilino activo de esa ocupación.

ROOT no entra como ejecutor por el mero hecho de ser ROOT. La selección manual se revalida server-side y no puede ampliar permisos por interfaz.

No se permite asignar silenciosamente a un usuario sin capacidad operativa.

### Responsable del piso

`assignmentType=property_responsible` se resuelve server-side desde `property_staff_access_v3`.

Debe existir exactamente un responsable vigente con escritura y rol interno activo. La ejecución congela ese usuario.

### Persona fija, rol y rotación

`fixed_person` guarda un `assignmentUserId` en la versión publicada y comprueba la relación vigente del usuario con el destino en cada ejecución. `role` guarda un `assignmentRole` (`admin`, `employee` o `tenant`) y el servidor elige entre las personas actualmente elegibles. `active_occupants_rotation` elige entre ocupantes activos del destino. ROOT no es candidato por su rol ROOT.

Para `role` y `active_occupants_rotation`, el reparto usa el menor número de ejecuciones previas de la aplicación, después la ejecución más antigua y finalmente el UUID como desempate estable. La aplicación se bloquea durante la resolución; un reintento idempotente devuelve la misma ejecución. El usuario elegido y la configuración quedan congelados en el snapshot de ejecución. La autorización para actuar vuelve a comprobar la relación vigente, de modo que una Suspensión/Baja o revocación impide nuevas acciones y futuras asignaciones sin alterar el histórico.

## 6. Validación del destino

Antes de crear la ejecución se vuelve a comprobar el ámbito real:

- organización existente;
- piso no archivado;
- habitación no archivada y perteneciente al piso;
- ocupación vigente y perteneciente al piso/organización.

Una aplicación histórica puede conservarse aunque su destino deje de estar disponible, pero no debe originar nuevas ejecuciones inválidas.

## 7. Historial mínimo

Tabla: `workflow_execution_events_v2`.

La creación genera exactamente un evento `created` con transición `null → pending`.

Este histórico funcional no sustituye `audit_log_v2`. La creación también deja auditoría administrativa/operativa suficiente para trazabilidad.

## 8. Relación con tenant_tasks_v2

`tenant_tasks_v2` ya fue generalizada de forma aditiva conforme a `WORKFLOW_TASKS_CONTRACT.md`: las tareas de workflow usan `source_kind='workflow_execution'`, pueden carecer de `tenant_id` y conservan ese requisito para tareas legacy. No existe una tabla paralela `workflow_tasks`.

## 9. Seguridad

- RLS obligatoria en ejecuciones y eventos.
- `anon` no ejecuta el RPC.
- `authenticated` no inserta/actualiza/borra directamente las tablas.
- El asignado puede leer su propia ejecución.
- ROOT/ADMIN y operadores autorizados pueden leer según organización/piso.
- El RPC deriva organización, versión y ámbito desde la aplicación; el cliente no los dicta.
- Reintentos no duplican ejecuciones.

## 10. Límite de este incremento

Una ejecución `pending` materializa una tarea visible. Si la receta requiere decisión del asignado, `accept` y `reject` mueven tarea + ejecución atómicamente conforme a `WORKFLOW_ACTIONS_CONTRACT.md`. `reject` conserva el rechazo como estado terminal explícito.

Ya están conectados en incrementos posteriores a este runner inicial:

- evidencia fotográfica;
- decisión Aceptar/Rechazar;
- cierre `human_review` para los pasos actualmente operativos.

Siguen fuera:

- checklist/documento;
- notificaciones operativas genéricas;
- recurrencia automática;
- cancelación genérica y adaptadores especializados.

La UI debe mostrar únicamente acciones realmente derivadas de la receta y soportadas por el servidor.

## Ejecución por evento — WF-02

La fuente inicial soportada es `occupancy.created`.

Cadena operativa:

`Evento de negocio → workflow_event_outbox_v2 → dispatcher → workflow_execute_application_internal_v1 → workflow_executions_v2 → tenant_tasks_v2`

Reglas:

- el trigger de la tabla de negocio solo inserta el evento en el outbox; no materializa trabajo;
- el payload es mínimo y no persiste correo u otra PII innecesaria;
- el dispatcher resuelve aplicaciones publicadas/configuradas cuyo `eventType` coincide y cuyo destino contiene el evento;
- organización, piso, habitación y ocupación se resuelven server-side desde el evento capturado;
- la asignación se revalida en el momento del despacho usando el mismo resolver del resto del motor;
- un fallo de una aplicación produce/actualiza un recibo `failed` y auditoría, pero no revierte el evento origen ni ejecuciones correctas de otras aplicaciones;
- mientras exista algún despacho fallido, el evento permanece `pending` para reintento; los recibos `executed` se saltan en los intentos siguientes;
- cuando todos los despachos convergen, el evento pasa a `processed`; reintentar después no crea ejecuciones nuevas;
- las tablas de outbox/recibos no conceden escritura ni ejecución directa a `authenticated`.

