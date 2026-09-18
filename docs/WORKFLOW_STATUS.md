# Estado de implementación — Flujos de Trabajo

Fecha de referencia: **2026-09-18**.

Este documento resume el estado real de implementación de **Flujos de Trabajo** y complementa:

- `WORKFLOW_ARCHITECTURE.md` — arquitectura funcional objetivo;
- `WORKFLOW_IMPLEMENTATION_MAP.md` — reutilización de piezas existentes;
- `WORKFLOW_ENGINE_CONTRACT.md` — contrato técnico del motor común.

Cadena canónica:

`Definición → Versión publicada → Aplicación concreta → Disparador → Ejecución → Asignación → Tareas → Recursos → Evidencias → Revisión/Cierre → Historial`

## 1. Decisión arquitectónica vigente

**Limpieza, Inspección, Mantenimiento, Check-in, Check-out y futuros procesos son configuraciones del mismo motor transversal.**

Los recursos reutilizables viven fuera del flujo. El primer recurso transversal operativo es el **Banco Fotográfico**.

No se crearán motores paralelos de tareas, cámara, Storage, notificaciones o recurrencia por dominio.

## 2. Navegación implementada

Desde Inicio existe **🔄 Flujos de Trabajo**.

Dentro están:

- **➕ Creador de Flujos**;
- **🧩 Mis Flujos**;
- **📷 Banco Fotográfico**;
- **📋 Tareas**;
- **🕘 Historial**.

Banco Fotográfico reutiliza `photo-patterns.html`, editor, cámara, Storage privado y fotoverificación existentes.

Los accesos legacy funcionales, especialmente Limpieza, permanecen hasta disponer de sustitución extremo a extremo.

## 3. Creador de Flujos — estado actual

El Creador es un asistente de siete pasos:

1. identidad;
2. ámbito;
3. activación;
4. asignación;
5. pasos y recursos;
6. cierre/revisión;
7. revisión final.

### Persistencia de borradores

El borrador ya puede guardarse en servidor mediante `save_workflow_definition_draft_v1`.

La persistencia usa:

- `workflow_definitions_v2` para identidad estable, especificación editable y `revision`;
- RLS de lectura por ROOT/ADMIN activo y organización;
- ausencia deliberada de INSERT/UPDATE/DELETE directo desde cliente;
- RPC `SECURITY DEFINER` que resuelve usuario/organización server-side;
- auditoría `workflow_draft_created` / `workflow_draft_updated`;
- control de concurrencia optimista: una revisión obsoleta se rechaza con `workflow_draft_conflict`.

`sessionStorage` se usa únicamente para un borrador local todavía no ligado a una definición guardada. Tras el primer guardado servidor, la caché local genérica se elimina y los flujos persistidos se reabren por `id`; así una definición publicada no reaparece como si fuera un flujo nuevo.

### Borradores parciales y decisiones explícitas

El Creador permite guardar un borrador con solo un nombre y continuar más tarde. Las opciones de tipo, ámbito, activación, asignación, pasos y cierre ya no tienen decisiones de negocio preseleccionadas.

`workflow_definitions_v2.authoring_complete` se calcula server-side a partir de una especificación de autoría v2. Un borrador solo pasa a **configuración completa** cuando los seis apartados requeridos contienen decisiones explícitas. Descripción y notificaciones siguen siendo opcionales.

Los borradores anteriores a esta regla no se reinterpretan como completos por sus antiguos valores por defecto: permanecen incompletos hasta ser revisados en el Creador.

El guardado de borradores es idempotente: pulsar **Guardar borrador** repetidamente sin modificar la especificación no incrementa `revision`, no cambia `updated_at` y no genera un evento `workflow_draft_updated`. La UI informa **Sin cambios** y conserva la revisión existente.

La activación también es condicional: **Manual** y **Por evento** no muestran frecuencia; **Recurrente** muestra frecuencia y, si se elige **Personalizada**, solicita intervalo + unidad; **Fecha concreta** muestra calendario y hora. El RPC sanea cualquier campo residual que no corresponda al tipo seleccionado.

### Límite intencional

**Guardar no significa publicar.**

Un borrador guardado todavía no:

- crea una versión publicada;
- selecciona de forma definitiva el piso/habitación/ocupación concreta;
- genera ejecuciones;
- crea tareas;
- programa recurrencias;
- dispara notificaciones operativas;
- altera Limpieza.

## 4. Mis Flujos — estado actual

`workflow-definitions.html` ya consulta `workflow_definitions_v2` mediante RLS.

Muestra:

- nombre;
- estado;
- tipo;
- ámbito conceptual;
- activación;
- asignación;
- revisión;
- fecha de último cambio.

Los borradores pueden reabrirse en el Creador con su `id` y continuar editándose.

Los borradores configurados pueden publicarse mediante RPC protegido. Una definición publicada ofrece acceso a **Aplicaciones**; `Ejecutar ahora` crea de forma idempotente la ejecución y su tarea materializada. Las primeras acciones atómicas ya pueden avanzar tarea + ejecución juntas.

## 5. Versiones publicadas y aplicaciones concretas

`workflow_definition_versions_v2` representa versiones inmutables de la receta lógica.

`publish_workflow_definition_v1`:

- exige `aal2`;
- publica solo autoría completa;
- no acepta INSERT cliente;
- congela el `scopeType` lógico;
- no selecciona todavía una entidad real;
- es idempotente ante reintento de una definición ya publicada.

`workflow_applications_v2` vincula una versión publicada con la entidad real. `create_workflow_application_v1` valida server-side organización, piso, habitación u ocupación y deja la aplicación en estado `configured`.

`configured` no activa recurrencias. Desde la tarjeta puede crear una ejecución explícita `manual_now`; esa ejecución nace `pending` y materializa exactamente una tarea vinculada.

La semántica detallada vive en `WORKFLOW_APPLICATIONS_CONTRACT.md`.

## 6. Banco Fotográfico

La infraestructura reutilizable sigue siendo:

- `photo_patterns_v2`;
- `contour_data` manual;
- cámara fullscreen;
- alineación local;
- Storage privado;
- `photo_verification_runs_v2`;
- `photo_verification_items_v2`;
- revisión humana protegida.

En cada ejecución que usa fotografía, el motor congela la versión exacta del patrón/recurso y su snapshot. Este comportamiento ya fue validado E2E con una versión publicada y una aplicación real.

## 7. Tareas

No se ha creado `workflow_tasks`.

`tenant_tasks_v2` se reutiliza como núcleo de tareas mediante una generalización aditiva:

- tareas legacy conservan `tenant_id` obligatorio;
- tareas de workflow usan `task_type='workflow'` y `source_kind='workflow_execution'`;
- `tenant_id` puede ser NULL únicamente bajo esa forma validada;
- una ejecución produce como máximo una tarea por índice único;
- el asignado puede leer su tarea por RLS;
- la pantalla `workflow-tasks.html` lista el trabajo visible.

`tenant_task_actions_v2` y `tenant_task_history_v2` se conservan. Las acciones de workflow se derivan del snapshot de la receta; cuando la receta requiere decisión del asignado se publican **Aceptar / Rechazar**. Rechazar exige motivo, deja tarea + ejecución en `rejected` y cancela recursos fotográficos pendientes. `apply_workflow_task_action_v1` mantiene la transición atómica e impide que el RPC legacy modifique una tarea de workflow por separado.

## 8. Limpieza — transición

Se conservan:

- `cleaning_plans_v2`;
- `cleaning_tasks_v2`;
- swaps;
- deuda no monetaria;
- auditoría por foto;
- solicitudes fotográficas;
- `cleaning.html`.

El motor ya puede publicar y ejecutar definiciones manuales reales. Limpieza sigue siendo el primer adaptador de dominio previsto, pero su migración debe esperar a que revisión humana, checklist/documento e historial transversal estén suficientemente cerrados para no degradar el flujo legacy.

## 9. Seguridad y pruebas de la persistencia

La persistencia de definiciones es un cambio R3 y dispone de pruebas negativas.

Se verifica que:

- TENANT no puede crear borradores;
- un ADMIN de otra organización no puede leer definiciones ajenas;
- ROOT/ADMIN no pueden insertar o editar directamente las tablas desde cliente;
- la tabla de versiones no admite publicación directa;
- la RPC puede crear/actualizar borradores autorizados;
- una `revision` obsoleta no sobrescribe cambios concurrentes;
- creación/edición queda auditada.

Las pruebas se ejecutan también en PostgreSQL 17 desechable desde Schema Guard.

## 10. Estado por módulo

| Módulo | Estado | Observación |
| --- | --- | --- |
| Flujos de Trabajo | Implementado | Hub transversal |
| Creador de Flujos | Implementado con borradores parciales y completitud explícita | Define receta lógica |
| Mis Flujos | Implementado; distingue incompletos/configurados/publicados | Publicación controlada disponible |
| Aplicaciones | Implementado para vincular versión publicada con entidad real | Permite `Ejecutar ahora` |
| Banco Fotográfico | Operativo/reutilizado | Patrones vinculables a aplicaciones y congelados por ejecución |
| Versiones publicadas | Implementado | Publicación RPC inmutable e idempotente |
| Tareas | Materialización + decisión + revisión humana implementadas | `tenant_tasks_v2` reutilizada; `accept/reject` y revisión agency sincronizan tarea + ejecución |
| Historial | Parcial avanzado | registra creación, materialización, acciones, evidencia y cierre de revisión; falta unificar la vista transversal completa |
| Ejecución genérica | Implementada; cierre auto validado E2E y `human_review` cubierto por regresión de integración | `manual_now`, snapshots, tarea materializada, cierre automático y revisión humana para pasos implementados |
| Adaptador Limpieza | Pendiente | Legacy preservado |

## 11. Incrementos

### PR #195 — Hub de Flujos de Trabajo

Introdujo hub y conexión con Banco Fotográfico.

Merge: `37b0bd2520d7a57211f5e80df90fdc50bdde11f1`.

### PR #196 — Creador de Flujos local

Introdujo contrato del motor, asistente de siete pasos y borrador local.

Merge: `112dbbdbc78146bc7e2be52d83b5385bacfc0c02`.

### PR #197 — Documentación de estado

Separó arquitectura, contrato, mapeo y estado fechado antes del primer DDL.

Merge: `a111c2dbd71527cf32de3eda6b4de5781e16e585`.

### PR #198 + #199 — Persistencia de borradores + Mis Flujos + hardening

Incluye:

- primer DDL aditivo del motor;
- `workflow_definitions_v2`;
- `workflow_definition_versions_v2` preparada para publicación;
- RLS;
- RPC de guardado seguro;
- auditoría;
- concurrencia optimista;
- Creador conectado al servidor;
- Mis Flujos conectado a RLS;
- pruebas negativas y regresión;
- hardening de privilegios para retirar `EXECUTE` anónimo de los RPC administrativos.

### Incremento de corrección — Borradores parciales

Añade la distinción entre **guardar** y **configurar**: permite persistir un borrador incompleto, elimina valores de negocio implícitos en la UI y mantiene la completitud calculada server-side mediante `authoring_complete`.

### Incremento de corrección — Guardado idempotente

Una revisión representa un cambio real de contenido. Repetir Guardar sin modificaciones devuelve la revisión existente y no altera fecha ni auditoría de actualización.

### Incremento de corrección — Decisión Aceptar/Rechazar y regresiones E2E

Las pruebas reales del recorrido fotográfico detectaron y corrigen tres puntos:

- el paso técnico `steps.accept=true` se presenta y ejecuta como **Requerir decisión del asignado: Aceptar / Rechazar**;
- Rechazar exige motivo, registra histórico/evento atómico y cancela recursos fotográficos pendientes;
- el Creador ya no recupera como flujo nuevo la caché local de una definición ya guardada/publicada;
- la vista previa vacía de la cámara permanece realmente oculta hasta existir una captura.


### Validación E2E real — 18/09/2026

Se cerraron dos recorridos manuales completos sobre el motor persistente:

1. **Aceptar + Foto**
   - definición publicada;
   - aplicación a un piso real de prueba;
   - patrón fotográfico congelado por ejecución;
   - tarea `pending` → `active` mediante `accept`;
   - captura fotográfica;
   - recurso `submitted`;
   - tarea + ejecución `completed`;
   - histórico/evento de aceptación y evidencia sin duplicados;
   - objeto JPEG único en Storage.

2. **Foto sin Aceptar**
   - receta con `steps.accept=false`;
   - tarea `pending` permite Foto directamente;
   - no existe acción/evento/histórico `accept`;
   - una captura válida completa recurso + tarea + ejecución;
   - un único run/ítem/objeto de Storage.

Estas pruebas demuestran que el primer flujo manual con evidencia fotográfica **sí es operativo dentro del alcance implementado**. No implican que checklist, documento, revisión humana genérica o recurrencias estén completos.

### PR #216 + #217 — Evidencia fotográfica y decisión del asignado

- PR #216 integró binding de patrones, snapshot por ejecución y cierre transaccional de evidencia fotográfica.
- PR #217 completó la semántica **Aceptar / Rechazar**, corrigió el borrador local obsoleto del Creador y la vista previa vacía de cámara.
- `reject` exige motivo, mantiene tarea + ejecución en `rejected` y cancela recursos fotográficos pendientes.


### Incremento — Revisión humana operativa

Se implementa `closeType=human_review` sin crear una cola de revisión paralela:

- los pasos operativos terminan en `waiting_review`;
- workflows sin Foto exponen `review_approve/review_reject` para actor `agency` (ROOT/ADMIN autorizado);
- workflows con Foto reutilizan **Fotoverificaciones**, de modo que la decisión se toma viendo la evidencia;
- todas las fotos aprobadas → tarea + ejecución `completed`;
- alguna foto rechazada, una vez revisadas todas → tarea + ejecución `rejected`;
- rechazo exige/conserva motivo;
- RLS permite al gestor leer las acciones `agency` aunque no sea el asignado;
- reintentos no duplican histórico/eventos;
- regresión PostgreSQL cubre aprobación, rechazo, actor no autorizado, ámbito organización y revisión fotográfica.

Este incremento está implementado y cubierto por regresión automatizada. La validación E2E real en la PWA se realizará como siguiente prueba antes de dar por cerrado el recorrido de revisión humana en producción de pruebas.


## 12. Próximo incremento técnico

El paso **Fotografía** y el cierre **human_review** ya están conectados a la infraestructura existente. El siguiente trabajo debe empezar por **validar E2E real la revisión humana** y después avanzar a los tipos de paso restantes.

Orden recomendado:

1. validar en producción de pruebas un workflow Foto + `human_review`, tanto aprobación como rechazo;
2. validar un workflow sin Foto que llegue a `waiting_review` y sea revisado por un ADMIN distinto del asignado;
3. implementar checklist/documento con el mismo principio de bloqueo de cierre;
4. completar la vista de Historial transversal ejecución → tarea → evidencia → revisión → cierre;
5. añadir notificaciones operativas específicas de cierre/rechazo;
6. después habilitar recurrencias automáticas.

La recurrencia automática permanece posterior a estos E2E para no automatizar un ciclo que todavía tenga tipos de paso incompletos.

## 13. Reglas de no regresión

- no duplicar `photo_patterns_v2` por flujo;
- no crear una segunda cámara o bucket;
- no crear otro sistema de notificaciones;
- no reescribir históricos existentes;
- no convertir `cleaning_plans_v2` en modelo universal;
- no retirar `cleaning.html` antes de sustitución funcional probada;
- no confiar en organización/ámbito enviados por cliente;
- no volver a guardar UUID de piso/habitación/ocupación dentro de la receta lógica;
- no presentar un borrador guardado como publicado;
- no permitir que editar una definición cambie ejecuciones ya creadas;
- no permitir publicación directa por INSERT cliente.

## 14. Criterio del primer flujo real — cumplido para Foto/manual

El criterio inicial quedó demostrado el 18/09/2026 para el recorrido manual con evidencia fotográfica:

- definición persistida;
- versión publicada inmutable;
- aplicación concreta;
- ejecución única;
- asignación server-side;
- tarea trazada a ejecución;
- recurso/patrón congelado por versión;
- evidencia almacenada una sola vez;
- cierre sincronizado tarea + ejecución;
- histórico/eventos sin duplicados en los recorridos probados.

Por tanto, **una definición publicada y aplicada ya puede representar un proceso operativo real dentro de los pasos implementados**.

Esto no debe generalizarse a capacidades aún pendientes. Un flujo que incluya checklist, documento o recurrencia automática no puede considerarse completo hasta que esos componentes tengan contrato, implementación y E2E propios. `human_review` ya tiene contrato e implementación; falta cerrar su validación E2E real.
