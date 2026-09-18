# Contrato de ejecución manual de Flujos de Trabajo

## Propósito

Este contrato define el primer runner transversal de GestionPisos. Consume una `workflow_application_v2` ya configurada y crea una ejecución persistente e idempotente.

Cadena canónica:

`Definición → Versión publicada → Aplicación concreta → Ejecutar ahora → Ejecución → Asignación → futura tarea → Recursos/Evidencias → Cierre → Historial`

## 1. Qué significa “Ejecutar ahora”

“Ejecutar ahora” es un disparo manual explícito de una aplicación concreta.

No cambia el disparador configurado en la receta. Una receta recurrente puede ejecutarse manualmente sin perder su regla recurrente futura. La ejecución registra `trigger_kind=manual_now`.

Cada pulsación intencional puede crear una ejecución nueva. Los reintentos técnicos de la misma pulsación reutilizan la misma `idempotency_key` y no duplican la ejecución.

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
- `failed`.

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

## 5. Asignación soportada inicialmente

### Manual

`assignmentType=manual` exige seleccionar un usuario al iniciar.

El usuario elegido debe ser:

- ROOT activo; o
- ADMIN activo de la organización; o
- EMPLOYEE activo con escritura vigente sobre el piso cuando existe ámbito de piso;
- EMPLOYEE activo de la organización cuando el ámbito es toda la organización.

No se permite asignar silenciosamente a un usuario sin capacidad operativa.

### Responsable del piso

`assignmentType=property_responsible` se resuelve server-side desde `property_staff_access_v3`.

Debe existir exactamente un responsable vigente con escritura y rol interno activo. La ejecución congela ese usuario.

### Reglas todavía no ejecutables

Hasta disponer de datos completos y contrato específico, el runner rechaza explícitamente:

- `fixed_person`;
- `role`;
- `active_occupants_rotation`.

No se inventan defaults ni se interpreta información ausente.

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

Una ejecución `pending` materializa una tarea visible. La primera acción operativa `accept` puede mover tarea + ejecución atómicamente conforme a `WORKFLOW_ACTIONS_CONTRACT.md`.

Quedan fuera:

- evidencia fotográfica;
- checklist/documento;
- notificaciones;
- recurrencia automática;
- revisión humana operativa;
- cancelación y adaptadores especializados.

La UI debe mostrar únicamente acciones realmente derivadas de la receta y soportadas por el servidor.
