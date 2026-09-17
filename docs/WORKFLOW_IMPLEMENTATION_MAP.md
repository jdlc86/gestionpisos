# Mapa de implementación — Flujos de Trabajo

## Propósito

Este documento traduce `WORKFLOW_ARCHITECTURE.md` al estado real actual de GestionPisos. Su función es impedir que el nuevo motor se construya en paralelo a componentes que ya existen.

Regla de esta fase:

> **No crear todavía tablas genéricas de workflow. Primero reutilizar, adaptar o encapsular lo existente y documentar qué pieza actual cumple cada responsabilidad.**

La arquitectura objetivo sigue siendo:

`Flujo → Disparador → Ejecución → Asignación → Tareas → Recursos → Evidencias → Revisión/Cierre → Historial`

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

## 2. Edge Functions actuales reutilizables

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

## 3. Pantallas actuales y destino

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

Cambio de Fase 2:

- añadir el mosaico **🔄 Flujos de Trabajo**;
- mantener temporalmente los accesos legacy mientras sus flujos no estén migrados;
- retirar mosaicos específicos de primer nivel solo después de que exista una ruta equivalente y probada dentro del motor.

## 4. Qué falta realmente

No existe todavía una entidad completa que represente:

- una receta de flujo versionada;
- un disparador genérico;
- una regla de asignación genérica;
- pasos ordenados de una receta;
- una ejecución inmutable de esa receta;
- congelación explícita de los recursos de la ejecución;
- idempotencia genérica de disparadores;
- un historial transversal que una definición, ejecución, tarea, evidencia y cierre.

Tampoco existe todavía un servicio server-side que pueda recibir una definición publicada y crear de forma idempotente una ejecución con sus tareas.

Eso es el **motor mínimo** que se diseñará después de cerrar este mapeo y la navegación.

## 5. Mapa objetivo de reutilización

| Concepto objetivo | Pieza actual principal | Decisión |
| --- | --- | --- |
| Banco Fotográfico | `photo_patterns_v2` + editor/cámara | Reutilizar |
| Evidencia fotográfica | `photo_verification_runs_v2` + `photo_verification_items_v2` | Reutilizar/adaptar |
| Tarea de usuario | `tenant_tasks_v2` | Candidato a generalización aditiva |
| Acciones de tarea | `tenant_task_actions_v2` | Reutilizar |
| Histórico de tarea | `tenant_task_history_v2` | Reutilizar |
| Plantillas de transición | `tenant_task_workflow_templates_v2` | Reutilizar como subcomponente, no como flujo completo |
| Limpieza | tablas `cleaning_*` | Adaptador de dominio; preservar |
| Revisión fotográfica | `review-photo-verification` | Reutilizar para evidencia fotográfica |
| Notificaciones | `notifications_v2` | Reutilizar |
| Auditoría sensible | `audit_log_v2` | Reutilizar |
| Definición de flujo | No existe | Diseñar después del mapeo |
| Versión de flujo | No existe | Diseñar |
| Disparador genérico | No existe | Diseñar |
| Regla de asignación genérica | No existe | Diseñar |
| Ejecución genérica | No existe | Diseñar |
| Enlace genérico flujo→recurso | No existe | Diseñar |
| Eventos transversales de ejecución | No existe como unidad completa | Diseñar sin duplicar históricos actuales |

## 6. Compatibilidad y transición

Durante la migración pueden convivir temporalmente:

- tareas antiguas de Limpieza;
- tareas genéricas de inquilino;
- nuevas ejecuciones del motor.

La coexistencia debe ser explícita y limitada en el tiempo. Nunca se resolverá ocultando duplicidades en la UI.

Reglas:

1. ningún histórico existente se reescribe;
2. ningún patrón se duplica para “adaptarlo” a un flujo;
3. una nueva definición solo afecta nuevas ejecuciones;
4. los IDs legacy permanecen trazables desde cualquier adaptador;
5. no se introduce una segunda cámara ni un segundo bucket;
6. no se introduce otro sistema de notificaciones;
7. no se elimina `cleaning.html` hasta disponer de sustituto funcional probado;
8. no se crean tablas de workflow hasta revisar el contrato del motor mínimo contra este mapa.

## 7. Primer incremento de producto

Fase 2 se implementa con riesgo bajo y sin tocar base de datos:

- mosaico principal **🔄 Flujos de Trabajo**;
- pantalla contenedora con:
  - ➕ Creador de Flujos;
  - 🧩 Mis Flujos;
  - 📷 Banco Fotográfico;
  - 📋 Tareas;
  - 🕘 Historial;
- conexión real de **Banco Fotográfico** con la herramienta ya existente;
- los módulos todavía no implementados se muestran como “En preparación”, sin simular funcionalidad inexistente;
- acceso legacy de Limpieza se mantiene hasta la migración funcional.

## 8. Próximo diseño técnico

Antes de cualquier DDL del motor mínimo se debe producir un contrato específico que defina:

- identidad/versionado de una definición;
- estados de definición;
- estructura de disparadores;
- semántica e idempotency key de ejecución;
- resolución server-side de asignaciones;
- modelo de pasos;
- enlace versionado a recursos;
- generación/adopción de tareas en `tenant_tasks_v2`;
- cómo una ejecución referencia evidencias actuales;
- eventos de ciclo de vida;
- permisos/RLS y pruebas negativas;
- estrategia de migración de Limpieza.

Hasta entonces, **no se crean tablas nuevas de workflow**.