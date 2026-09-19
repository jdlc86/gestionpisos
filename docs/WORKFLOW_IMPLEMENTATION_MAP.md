# Mapa de implementación — Flujos de Trabajo

## Propósito

Este documento traduce `WORKFLOW_ARCHITECTURE.md` al estado real actual de GestionPisos. Su función es impedir que el nuevo motor se construya en paralelo a componentes que ya existen.

El estado fechado de implementación se mantiene en `WORKFLOW_STATUS.md` y el contrato previo al motor persistente en `WORKFLOW_ENGINE_CONTRACT.md`.

Regla de esta fase:

> **No crear tablas genéricas de workflow sin aplicar primero el contrato del motor mínimo, la migración aditiva y las pruebas RLS. Reutilizar, adaptar o encapsular lo existente antes de introducir una pieza paralela.**

La arquitectura objetivo sigue siendo:

`Flujo → Versión publicada → Aplicación concreta → Disparador → Ejecución → Asignación → Tareas → Recursos → Evidencias → Revisión/Cierre → Historial`

## Estado de implementación — 2026-09-18

Ya están completados o implementados en el incremento actual:

- el mosaico principal **🔄 Flujos de Trabajo**;
- el hub con **➕ Creador de Flujos**, **🧩 Mis Flujos**, **📷 Banco Fotográfico**, **📋 Tareas** y **🕘 Historial**;
- la conexión real del **Banco Fotográfico** con la infraestructura de patrones existente;
- el contrato `WORKFLOW_ENGINE_CONTRACT.md`;
- la UI del **Creador de Flujos** como asistente de siete pasos;
- persistencia segura de borradores mediante `workflow_definitions_v2` y RPC server-side;
- publicación controlada en `workflow_definition_versions_v2`, sin escritura cliente;
- `workflow_applications_v2` para vincular versiones publicadas con entidades reales;
- **Mis Flujos** como inventario de borradores visibles según RLS;
- control de concurrencia optimista mediante `revision` y rechazo de ediciones obsoletas;
- auditoría de creación/edición de borradores;
- smoke tests, pruebas RLS positivas/negativas y regresión PostgreSQL aislada.

Cambios integrados previamente:

- PR #195 → hub de Flujos de Trabajo;
- PR #196 → contrato del motor + Creador de Flujos local;
- PR #197 → actualización documental del estado previo a persistencia.

El incremento actual publica versiones inmutables, permite aplicaciones concretas, crea ejecuciones manuales idempotentes y **materializa tareas visibles reutilizando `tenant_tasks_v2`**.

## 1. Inventario funcional existente

### 1.1 Tareas genéricas de inquilino

Tablas actuales:

- `tenant_tasks_v2`
- `tenant_task_actions_v2`
- `tenant_task_history_v2`
- `tenant_task_workflow_templates_v2`

Lectura arquitectónica:

- `tenant_tasks_v2` ya contiene una abstracción bastante genérica de tarea: ámbito de organización/piso/habitación, tipo, origen, título, descripción, estado, vencimiento, asignado y referencia a una fuente.
- `tenant_task_actions_v2` representa acciones/transiciones disponibles para una tarea concreta.
- `tenant_task_history_v2` conserva cambios de estado y actor.
- `tenant_task_workflow_templates_v2` contiene plantillas de transiciones por `task_type`, pero **no es todavía una definición completa de flujo**: no representa disparadores, recursos, versionado de receta, reglas de asignación ni ejecuciones.

Decisión:

- **Reutilizar `tenant_tasks_v2` como candidato principal para la capa de tarea de usuario**, siempre que el contrato final permita tareas no exclusivamente ligadas a inquilinos.
- No renombrar ni generalizar destructivamente en esta fase.
- No duplicar una nueva tabla `workflow_tasks` hasta demostrar qué carencias reales no pueden resolverse de forma aditiva.
- Mantener las acciones e histórico actuales como base para el futuro ciclo de vida de tareas, sin convertir sus plantillas en el motor completo.

### 1.2 Limpieza

Tablas actuales:

- `cleaning_plans_v2`
- `cleaning_tasks_v2`
- `cleaning_swap_requests_v2`
- `cleaning_debts_v2`
- `cleaning_audits_v2`
- `cleaning_audit_items_v2`
- `cleaning_audit_policies_v2`
- `cleaning_photo_requests_v2`
- `cleaning_photo_request_policies_v2`

Lectura arquitectónica:

- `cleaning_plans_v2` es una definición específica de dominio (`property + cadence`). No debe convertirse en el modelo genérico de workflow.
- `cleaning_tasks_v2` conserva semántica propia de Limpieza: estados, intercambio, deuda, revisión y vínculo explícito con verificación fotográfica.
- `cleaning_photo_requests_v2` ya funciona como checklist fotográfico congelado por tarea y enlaza un patrón concreto con la tarea.
- las tablas de auditoría contienen reglas que solo tienen sentido para Limpieza y deben permanecer como semántica especializada.

Decisión:

- **Limpieza será el primer adaptador de dominio al nuevo motor**, no la base del motor.
- `cleaning_plans_v2` y `cleaning_tasks_v2` se conservan durante la transición para no romper histórico ni reglas ya probadas.
- No ampliar `cleaning_plans_v2` con conceptos de Check-in, Mantenimiento o Inspección.
- Cuando exista el motor mínimo, una definición de flujo de tipo Limpieza deberá poder producir/coordinar las estructuras de Limpieza necesarias mediante una capa de compatibilidad explícita.
- Intercambio de tareas, deuda no monetaria y auditoría por foto siguen siendo reglas propias del dominio Limpieza.

### 1.3 Banco Fotográfico

Tablas actuales:

- `photo_patterns_v2`
- `photo_verification_runs_v2`
- `photo_verification_items_v2`
- `verification_policies_v2`
- `random_photo_requests_v2`

Infraestructura existente:

- bucket privado de fotoverificación;
- patrones reales por piso;
- `contour_data` manual;
- versionado lógico de patrón;
- captura fullscreen;
- alineación local;
- almacenamiento JPEG privado;
- historial de runs/items;
- revisión humana protegida.

Decisión:

- **`photo_patterns_v2` es el núcleo actual del recurso Banco Fotográfico.**
- El Banco Fotográfico se considera transversal y deja de pertenecer conceptualmente a Limpieza.
- `photo_verification_runs_v2` y `photo_verification_items_v2` son infraestructura de evidencia fotográfica compartida.
- Su `purpose` ya diferencia `general`, `cleaning`, `maintenance` y `state`, lo que confirma que la evidencia fotográfica ya ha empezado a desacoplarse de Limpieza.
- `source_type` sigue limitado a valores actuales; no se ampliará hasta diseñar el vínculo correcto con una futura ejecución genérica.
- No duplicar patrones por flujo.

### 1.4 Solicitudes fotográficas

`random_photo_requests_v2` representa hoy una solicitud fotográfica dirigida y `cleaning_photo_requests_v2` una selección fotográfica congelada para Limpieza.

Decisión:

- conservar ambas como implementaciones específicas existentes;
- no generalizarlas cambiando su significado histórico;
- el futuro motor deberá expresar solicitudes de evidencia mediante pasos/recursos genéricos y, cuando corresponda, adaptarlas a estas estructuras existentes;
- una captura podrá vincularse a más de un propósito solo mediante vínculos explícitos, nunca reinterpretando su decisión original.

### 1.5 Auditoría e histórico global

Tabla actual:

- `audit_log_v2`

Decisión:

- reutilizarla para operaciones sensibles y cambios administrativos;
- no usarla como sustituto del histórico funcional detallado del motor;
- el futuro historial de workflow deberá conservar versión de receta, asignación, recursos y eventos de ejecución, mientras `audit_log_v2` mantiene la auditoría de seguridad/administración que corresponda.

### 1.6 Notificaciones

Tabla actual:

- `notifications_v2`

Decisión:

- reutilizable para avisar de nuevas tareas, vencimientos, revisiones o cierres;
- el motor no debe crear un segundo sistema de notificaciones;
- la decisión de notificar forma parte de la definición/cierre del flujo, pero la entrega se delega a la infraestructura de notificación existente.

### 1.7 Definiciones de Flujos de Trabajo

Tablas introducidas de forma aditiva:

- `workflow_definitions_v2`;
- `workflow_definition_versions_v2`;
- `workflow_applications_v2`.

Responsabilidad actual:

- `workflow_definitions_v2` conserva identidad estable, metadatos resumidos, estado `draft`, especificación saneada, `revision` de concurrencia y `authoring_complete` derivado server-side;
- `workflow_definition_versions_v2` contiene versiones publicadas inmutables mediante RPC protegido;
- `workflow_applications_v2` contiene el vínculo entre una versión y organización/piso/habitación/ocupación real;
- `workflow_executions_v2` conserva cada ejecución manual, versión, ámbito, idempotencia y asignado congelado;
- `workflow_execution_events_v2` inicia el histórico funcional de ejecución.

Seguridad:

- RLS obligatoria;
- lectura limitada a ROOT y ADMIN activos de la organización correspondiente;
- el cliente no tiene INSERT/UPDATE/DELETE directo;
- la escritura del borrador pasa por `save_workflow_definition_draft_v1`;
- organización y rol del autor se resuelven server-side desde `auth.uid()` + `user_roles`;
- crear/editar deja eventos de auditoría;
- `revision` evita sobrescribir silenciosamente un borrador modificado en otra sesión;
- los campos de configuración pueden permanecer nulos mientras el borrador está incompleto;
- ninguna selección de negocio se introduce por defecto y los borradores anteriores a `authoringVersion=2` no se consideran completos hasta revisión.

## 2. Edge Functions y servicios actuales reutilizables

### `manage-photo-pattern`

Responsabilidad actual: ciclo de vida seguro del patrón fotográfico.

Destino: servicio del **Banco Fotográfico**.

### `save-photo-pattern-contours`

Responsabilidad actual: guardar siluetas manuales con validación de permisos y versión.

Destino: editor del **Banco Fotográfico**.

### `submit-photo-verification`

Responsabilidad actual: recibir evidencia fotográfica y finalizar la persistencia autorizada del run/item.

Destino: servicio compartido de **evidencia fotográfica** consumido por pasos de distintos flujos.

### `review-photo-verification`

Responsabilidad actual: revisión humana segura de fotoverificaciones con AAL2/rol privilegiado cuando corresponde.

Destino: componente de revisión de evidencia fotográfica; no equivale todavía a la revisión universal de un workflow.

### `my-cleaning-checklist`

Responsabilidad actual: resolver para una tarea de Limpieza sus solicitudes fotográficas y devolver enlaces de captura.

Destino transitorio: **adaptador de Limpieza**. No debe evolucionar hasta convertirse en un endpoint genérico con nombre de Limpieza.

Cuando exista el motor mínimo deberá aparecer un servicio genérico equivalente a “obtener mi tarea/ejecución y sus pasos”, y este endpoint podrá mantenerse como compatibilidad hasta retirar el flujo antiguo.

### `save_workflow_definition_draft_v1`

Responsabilidad actual: crear o actualizar un borrador de flujo mediante RPC `SECURITY DEFINER`, validando rol activo, organización, estructura de la receta y revisión esperada.

Destino: servicio de autoría de definiciones. **No publica** y no debe evolucionar para crear ejecuciones de forma implícita.

## 3. Pantallas actuales y destino

### `workflows.html`

Estado: **operativo**.

Es el hub transversal y expone los cinco módulos acordados. No debe contener lógica de dominio de Limpieza, Mantenimiento o Inspección.

### `workflow-builder.html`

Estado: **operativo con borrador persistente**.

- asistente de siete pasos;
- todos los apartados de negocio parten como **Pendiente** y requieren elección explícita;
- permite guardar un borrador incompleto con identidad mínima;
- `sessionStorage` conserva únicamente un borrador local todavía no ligado a una definición guardada; un flujo ya persistido no se restaura como si fuera uno nuevo;
- “Guardar borrador” persiste la definición mediante RPC server-side;
- un borrador guardado puede reabrirse por `id` y continuar editándose;
- el guardado no publica ni crea tareas/ejecuciones/notificaciones;
- enlaza con Banco Fotográfico como recurso reutilizable.

Destino: mantener aquí solo la receta lógica. Los UUID concretos se gestionan en la capa de Aplicaciones.

### `workflow-definitions.html`

Estado: **operativo para Mis Flujos**.

- lista definiciones visibles por RLS;
- muestra estado, completitud de autoría, tipo, ámbito, activación, asignación, revisión y fecha de cambio;
- permite reabrir borradores para edición;
- permite publicar un borrador configurado;
- una definición publicada enlaza con su pantalla de Aplicaciones;
- todavía no ejecuta tareas ni recurrencias.

### `photo-patterns.html`

Estado: operativo.

Destino conceptual inmediato:

`Flujos de Trabajo → Banco Fotográfico`

No cambia todavía su URL para evitar regresiones.

### `photo-pattern-editor.html`

Estado: operativo.

Destino: editor interno del Banco Fotográfico.

### `photo-camera.html`

Estado: operativo.

Destino: capacidad transversal de captura, invocada desde tareas/pasos que requieran evidencia fotográfica.

### `photo-verifications.html`

Estado: operativo para historial/revisión fotográfica.

Destino: componente de historial y revisión de **evidencias fotográficas**. No se renombrará aún a “Historial de Flujos” porque su alcance actual es más estrecho.

### `cleaning.html`

Estado: interfaz funcional de transición que todavía exige conocer un `task_id`.

Destino:

- conservar hasta que exista la vista genérica de Tareas;
- después, las tareas de Limpieza deben aparecer automáticamente dentro de `Flujos de Trabajo → Tareas`;
- eliminar la dependencia del UUID manual solo cuando el nuevo flujo esté probado extremo a extremo.

### `index.html`

Estado actual:

- mosaico **🔄 Flujos de Trabajo** ya integrado;
- accesos legacy se mantienen mientras sus flujos no estén migrados;
- mosaicos específicos de primer nivel solo se retirarán después de disponer de ruta equivalente y probada dentro del motor.

## 4. Qué falta realmente

Ya existe persistencia genérica para **identidad estable de definición y borrador editable**, publicación inmutable y aplicación concreta del ámbito.

Falta implementar:

- congelación explícita de otros recursos/versiones concretos;
- notificaciones operativas genéricas de cierre/rechazo;
- la vista transversal de Historial ya presenta ejecución, tarea, evidencias, revisión y cierre usando las fuentes existentes; paginación profunda y filtros avanzados quedan como evolución.

La revisión/cierre `human_review` ya está implementada para los pasos actualmente operativos.

Ya existe el servicio server-side que crea de forma idempotente una ejecución manual, congela su asignación y materializa una tarea compartida sin fabricar `tenant_id`. El primer RPC de acciones sincroniza tarea + ejecución y protege la ruta legacy.

Fotografía, Checklist y Documento ya son pasos operativos del motor mínimo.

## 5. Mapa objetivo de reutilización

| Concepto objetivo | Pieza actual principal | Decisión |
| --- | --- | --- |
| Banco Fotográfico | `photo_patterns_v2` + editor/cámara | Reutilizar |
| Evidencia fotográfica | `photo_verification_runs_v2` + `photo_verification_items_v2` | Integrada con snapshots y cierre transaccional |
| Checklist | `workflow_executions_v2.checklist_state` + `set_workflow_checklist_item_v1` | Snapshot por ejecución; usa la tarea común y bloquea cierre hasta obligatorios |
| Documento | `workflow_execution_documents_v2` + bucket privado `workflow-documents-v2` | Evidencia ligada a ejecución; un submitted satisface v1 y coordina cierre con Foto/Checklist |
| Tarea de usuario | `tenant_tasks_v2` | Generalización aditiva implementada para `source_kind=workflow_execution` |
| Acciones de tarea | `tenant_task_actions_v2` | Reutilizar |
| Histórico de tarea | `tenant_task_history_v2` | Reutilizar |
| Plantillas de transición | `tenant_task_workflow_templates_v2` | Reutilizar como subcomponente, no como flujo completo |
| Limpieza | tablas `cleaning_*` | Adaptador de dominio; preservar |
| Revisión fotográfica | `review-photo-verification` + `apply_workflow_photo_review_v1` | Reutilizada; decide el run y sincroniza el cierre `human_review` del workflow |
| Notificaciones | `notifications_v2` | Reutilizar |
| Auditoría sensible | `audit_log_v2` | Reutilizar |
| Definición de flujo | `workflow_definitions_v2` | Implementado para borradores persistentes |
| Versión de flujo | `workflow_definition_versions_v2` | Publicación inmutable implementada |
| Aplicación concreta | `workflow_applications_v2` | Vinculación real implementada |
| Disparador manual explícito | `execute_workflow_application_now_v1` | Implementado con idempotencia |
| Regla de asignación inicial | Snapshot en `workflow_executions_v2` | Manual y responsable de piso soportados; otras bloqueadas explícitamente |
| Ejecución genérica | `workflow_executions_v2` | Fase inicial `pending` implementada |
| Tarea materializada | `tenant_tasks_v2` + `source_kind/source_id` | Implementada e idempotente |
| Acción atómica | `tenant_task_actions_v2` + `apply_workflow_task_action_v1` | `accept/reject` y revisión `agency` sin Foto; mantiene tarea/ejecución sincronizadas |
| Binding aplicación→foto | `workflow_application_photo_resources_v2` | Implementado con patrones reales del piso |
| Snapshot ejecución→foto | `workflow_execution_photo_resources_v2` | Implementado; congela versión y silueta |
| Eventos transversales de ejecución | `workflow_execution_events_v2` | Creación, materialización, acciones, evidencia y cierre de revisión registrados; presentación transversal implementada en Historial |
| Notificaciones | `notifications_v2` + trigger de `workflow_executions_v2` | onCreate al asignado; onClose a creador+asignado; dedupe por source/event/recipient |

## 6. Compatibilidad y transición

Durante la migración pueden convivir temporalmente:

- tareas antiguas de Limpieza;
- tareas genéricas de inquilino;
- borradores genéricos del nuevo motor;
- nuevas ejecuciones del motor cuando se incorporen.

La coexistencia debe ser explícita y limitada en el tiempo. Nunca se resolverá ocultando duplicidades en la UI.

Reglas:

1. ningún histórico existente se reescribe;
2. ningún patrón se duplica para “adaptarlo” a un flujo;
3. una nueva definición solo afecta nuevas ejecuciones futuras;
4. los IDs legacy permanecen trazables desde cualquier adaptador;
5. no se introduce una segunda cámara ni se duplica un bucket para el mismo tipo de evidencia; Documento usa su bucket privado propio porque requiere MIME, límites y políticas distintas de Foto;
6. no se introduce otro sistema de notificaciones;
7. no se elimina `cleaning.html` hasta disponer de sustituto funcional probado;
8. todo DDL de workflow debe seguir `WORKFLOW_ENGINE_CONTRACT.md`, ser aditivo y disponer de pruebas RLS positivas y negativas.

## 7. Incrementos de producto completados

### Incremento A — Hub

Completado en PR #195:

- mosaico principal **🔄 Flujos de Trabajo**;
- pantalla contenedora con los cinco módulos;
- conexión real de **Banco Fotográfico** con la herramienta ya existente;
- acceso legacy de Limpieza preservado;
- smoke tests del hub.

### Incremento B — Creador de Flujos local

Completado en PR #196:

- contrato `WORKFLOW_ENGINE_CONTRACT.md`;
- Creador de Flujos de siete pasos;
- borrador local explícito y recuperable durante la sesión;
- resumen legible de la receta;
- enlace a Banco Fotográfico;
- integración PWA y protección con `auth-guard.js`;
- sin DDL ni escritura en Supabase.

### Incremento C — Persistencia de borradores + Mis Flujos

Implementado en esta fase:

- `workflow_definitions_v2` como identidad estable y borrador persistente;
- `workflow_definition_versions_v2` preparada para publicación futura;
- RLS de lectura por rol/organización;
- ausencia deliberada de escritura directa cliente;
- RPC `save_workflow_definition_draft_v1` para crear/editar de forma auditada;
- revisión optimista contra ediciones concurrentes;
- Creador conectado al servidor sin cambiar la semántica de “borrador”;
- **Mis Flujos** conectado a las definiciones visibles por RLS;
- pruebas negativas para TENANT, acceso cruzado y escritura directa.

### Incremento D — Borradores parciales y decisiones explícitas

- elimina defaults de negocio del Creador;
- permite persistir campos todavía pendientes sin fabricar decisiones;
- añade `authoring_complete` calculado en servidor;
- marca en **Mis Flujos** «Borrador incompleto» o «Borrador configurado»;
- obliga a revisar borradores legacy antes de tratarlos como configurados;
- mantiene publicación y ejecución bloqueadas.

## 8. Próximo incremento técnico

La evidencia fotográfica y la revisión/cierre `human_review` ya están conectadas a las piezas existentes.

El siguiente trabajo debe cubrir:

- validación E2E real de aprobación y rechazo de revisión humana;
- Documento sin motores paralelos;
- Historial transversal visible suficiente para reconstruir evidencia, reviewer y cierre;
- notificaciones operativas específicas de cierre/rechazo;
- permisos/RLS y pruebas negativas de los nuevos tipos de paso;
- no habilitar recurrencia hasta probar estos recorridos extremo a extremo.

La recurrencia automática se incorpora después de esa validación.

La regla histórica del primer mapeo se mantiene como salvaguarda: **no se crean tablas nuevas de workflow de forma improvisada o paralela**; cualquier DDL nuevo debe derivarse explícitamente del contrato del motor, justificar su necesidad frente a las tablas existentes y venir acompañado de RLS y pruebas de regresión.
