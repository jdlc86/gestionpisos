# Estado de implementación — Flujos de Trabajo

Fecha de referencia: **2026-09-19**.

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

El Creador mantiene el asistente de siete pasos y la continuidad validada:

`Diseño → Destino → Listo`.

### Creación nueva: sin borradores parciales

Una creación nueva vive solo durante el recorrido actual. Los controles **Guardar** y **Guardar y salir** dejan de formar parte de esa experiencia y no se crea una definición parcial para retomarla después.

Si el usuario intenta abandonar antes de finalizar, la interfaz advierte que perderá los cambios. Recargar/cerrar una creación incompleta tampoco la convierte en un registro persistente.

Al completar Diseño, el Creador transporta temporalmente la especificación a Destino mediante un handoff de sesión de un solo uso. Elegir el destino todavía no escribe el flujo en servidor.

### Listo: Publicar / Ejecutar / Descartar

En Listo se decide el efecto real:

- **Publicar**: finaliza de forma atómica definición, versión, destino y recursos; aparece en Mis Flujos y crea **cero** ejecuciones/tareas.
- **Ejecutar**: realiza la misma finalización y además valida condiciones vigentes, asignación y recursos antes de materializar una ejecución y exactamente una tarea.
- **Descartar**: una creación nueva desaparece sin dejar registros parciales.

`publish_workflow_ready_v1` encapsula la primera finalización y usa una `creation_request_key` para que un reintento no cree duplicados.

### Edición según exista historial

La primera ejecución es la frontera histórica.

Un flujo publicado que **nunca se ha ejecutado**:

- se edita como la misma entidad lógica;
- no crea una v2 solo por cambiar configuración;
- puede cambiar su destino/recursos;
- puede eliminarse completamente.

`update_unexecuted_workflow_v1` aplica ese cambio únicamente después de comprobar server-side que no existe ninguna ejecución.

Un flujo que **ya tiene alguna ejecución**:

- ya no puede eliminarse;
- puede archivarse conservando versiones, aplicaciones, ejecuciones, tareas y evidencias;
- al pulsar **Editar**, el sistema prepara automáticamente un borrador separado en `workflow_definition_revision_drafts_v2`;
- la versión actualmente utilizada permanece intacta durante la edición;
- al finalizar, `publish_workflow_revision_ready_v1` añade vN+1 y prepara su destino actual.

Los borradores de futura versión siguen existiendo porque protegen un flujo con historial. Lo que desaparece del producto es el almacenamiento de **creaciones nuevas incompletas**.

## 4. Mis Flujos — estado actual

`workflow-definitions.html` muestra solo flujos terminados/publicados.

Cada tarjeta presenta la configuración operativa relevante, incluido el destino actual, el número de ejecuciones y la fecha/hora de la última ejecución. La UI no expone la decisión técnica de versionar.

Mis Flujos incorpora búsqueda contextual por nombre/configuración/destino: el campo no ocupa espacio permanente, se abre desde una lupa del encabezado y puede cerrarse conservando el filtro como chip compacto.

La selección múltiple tampoco usa controles permanentes. Se entra desde el icono contextual del encabezado o mediante pulsación prolongada de una tarjeta. En ese modo, las tarjetas muestran indicadores circulares discretos y las operaciones aparecen en un dock flotante sobre la navegación inferior. El menú contextual permite seleccionar o deseleccionar todos los resultados visibles del filtro actual.

Las ejecuciones múltiples se preparan como una cola asistida: el usuario selecciona varios flujos una sola vez y el sistema recorre cada uno reutilizando la pantalla de ejecución. Cada elemento vuelve a validar sus condiciones y, si necesita información, muestra únicamente los apartados pendientes. No se crean tareas masivas a ciegas.

Acciones:

- siempre: **Ejecutar**;
- siempre: **Editar**;
- sin historial: **Eliminar**;
- con historial: **Archivar**.

Al pulsar Editar, el sistema decide:

- cero ejecuciones → edición en sitio;
- una o más ejecuciones → borrador de futura versión.

Al pulsar Ejecutar se reutiliza `execute_workflow_application_now_v1`, que vuelve a comprobar estado del destino, vigencia de ocupación, asignación y recursos. La existencia de una tarjeta no garantiza por sí sola que hoy pueda ejecutarse.

## 5. Versiones, destinos y frontera histórica

`workflow_definition_versions_v2` sigue conservando la configuración ejecutable de una definición.

La inmutabilidad se aplica estrictamente desde que existe historial operativo:

- antes de la primera ejecución, la versión actual puede actualizarse mediante el RPC específico de flujo no ejecutado;
- desde la primera ejecución, la versión referenciada queda congelada y cualquier edición futura añade vN+1;
- una ejecución conserva su `definition_version_id`, `application_id`, `spec_snapshot`, asignación y recursos efectivos;
- archivar nunca borra esos vínculos históricos.

`workflow_applications_v2` continúa siendo la capa técnica que valida el destino real. En la UX actual, Destino forma parte del recorrido integrado antes de Publicar/Ejecutar.

La publicación sola no materializa trabajo. Solo **Ejecutar** crea `workflow_executions_v2` y su tarea vinculada en `tenant_tasks_v2`.

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

El motor ya puede publicar y ejecutar definiciones manuales reales con Foto, Checklist y Documento. Limpieza sigue siendo el primer adaptador de dominio previsto, pero su migración debe esperar a que el historial transversal y los E2E de los pasos genéricos estén suficientemente cerrados para no degradar el flujo legacy.

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

El 19/09/2026 se detectó además una diferencia entre el PostgreSQL local y los **default privileges** reales de Supabase: cinco RPC `SECURITY DEFINER` del ciclo Publicar/Editar/Eliminar/Archivar conservaban `EXECUTE` explícito para `anon`. Sus cuerpos ya rechazaban sesiones sin `auth.uid()`, pero se cerró también la superficie RPC con una migración aditiva que revoca `anon` de forma explícita. La regresión local reproduce desde entonces esos default privileges para evitar falsos verdes.

## 10. Estado por módulo

| Módulo | Estado | Observación |
| --- | --- | --- |
| Flujos de Trabajo | Implementado | Hub transversal |
| Creador de Flujos | Implementado como recorrido integrado | Creación nueva temporal; Diseño → Destino → Listo → Publicar/Ejecutar |
| Mis Flujos | Implementado como catálogo operativo | Buscar, selección múltiple, ejecución en cola y Eliminar/Archivar masivos según historial |
| Aplicaciones | Implementado como capa técnica de Destino | Validación real y recursos; integrada en la finalización |
| Banco Fotográfico | Operativo/reutilizado | Patrones vinculables a aplicaciones y congelados por ejecución |
| Versiones publicadas | Implementado | Editables solo antes de primera ejecución; después inmutables por historial |
| Tareas | Materialización + decisión + revisión humana implementadas | `tenant_tasks_v2` reutilizada; `accept/reject` y revisión agency sincronizan tarea + ejecución |
| Historial | Operativo inicial | vista única de ejecuciones con tarea, Foto/Checklist/Documento, decisiones, revisión y cierre; filtros avanzados/paginación profunda quedan posteriores |
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

Estas pruebas demuestran que el motor genérico cubre ejecución manual, Fecha concreta y Recurrente, además de Foto, Checklist, Documento y revisión humana. WF-02 añade el cuarto disparador, `event`, mediante outbox + dispatcher; su fuente representativa inicial es `occupancy.created`. Los disparadores automáticos conservan idempotencia server-side.

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

Este incremento está implementado y cubierto por regresión automatizada. Además, el 19/09/2026 se validó E2E real en la PWA el recorrido **Foto + human_review**:

- una ejecución fue aprobada: run `approved`, tarea + ejecución `completed`, revisor/fecha, histórico, evento y auditoría únicos;
- dos ejecuciones independientes fueron rechazadas con motivos distintos: run/tarea/ejecución `rejected`, motivo conservado y exactamente un histórico/evento/auditoría por ejecución.

El E2E real de `human_review` **sin Foto** y con revisor ADMIN distinto del asignado también fue validado manualmente. Ese hueco queda cerrado.


### Incremento — Separación Creador / Mis Flujos

La autoría queda separada de la operación:

- los borradores y la publicación viven en Creador;
- Mis Flujos muestra únicamente versiones publicadas;
- `workflow_definition_revision_drafts_v2` permite preparar vN+1 sin tocar vN;
- publicar vN+1 no modifica aplicaciones existentes de vN;
- el borrador de nueva versión usa concurrencia optimista y publicación idempotente;
- la PWA pasa a shell v11 para refrescar la nueva organización de pantallas.

La regresión específica demuestra v1 → aplicación v1 → borrador v2 → publicación v2 manteniendo la aplicación vinculada a v1.


### Incremento — Publicar / Ejecutar y frontera de primera ejecución

Se simplifica el modelo de autoría sin perder trazabilidad:

- una creación nueva incompleta ya no se persiste ni se lista como borrador;
- Destino sigue formando parte del recorrido integrado antes de cualquier escritura definitiva;
- Listo ofrece **Publicar**, **Ejecutar** y **Descartar**;
- Publicar genera flujo + destino con cero tareas;
- Ejecutar publica y materializa una única tarea si las condiciones actuales son válidas;
- un flujo publicado sin ejecuciones se edita en sitio y puede eliminarse;
- la primera ejecución convierte la configuración usada en historia protegida;
- a partir de ahí Editar crea una nueva versión y la alternativa destructiva pasa de Eliminar a Archivar;
- Mis Flujos no muestra botones “Crear nueva versión” ni “Duplicar”: el backend decide el versionado según exista historial.

La regresión `workflow-publish-execute-lifecycle-regression.sql` cubre publicación sin tarea, idempotencia, edición sin v2, eliminación antes de historial, primera ejecución con una sola tarea, prohibición de borrado posterior, creación de v2 y archivo preservando historial.

### Incremento — Checklist operativo

Checklist se implementa como un paso del motor común, no como un subsistema de tareas paralelo:

- el Creador persiste una lista ordenada de hasta 30 elementos, cada uno con texto y obligatoriedad;
- una receta con Checklist solo es publicable cuando tiene al menos un elemento válido y al menos uno obligatorio;
- la versión publicada congela la configuración y cada ejecución inicializa su propio `checklist_state`;
- solo el usuario asignado puede marcar o desmarcar mientras la tarea está en `pending`/`active`;
- si la receta exige Aceptar, el checklist queda bloqueado hasta esa decisión;
- el último obligatorio solo cierra cuando los demás pasos operativos también están satisfechos;
- `closeType=auto` lleva tarea + ejecución a `completed`;
- `closeType=human_review` lleva tarea + ejecución a `waiting_review`;
- Foto + Checklist funcionan en cualquier orden de finalización;
- cada cambio registra histórico de tarea, evento de ejecución y auditoría, con clave de reintento idempotente.

La primera versión no convierte Checklist en un constructor de formularios: no incluye texto libre, firma, adjuntos propios ni lógica condicional.

### Incremento — Documento operativo

Documento se integra como evidencia privada de la ejecución, no como un gestor documental paralelo:

- `workflow_execution_documents_v2` conserva ejecución, tarea, actor, nombre, MIME, tamaño, ruta y estado;
- el bucket privado `workflow-documents-v2` admite PDF/JPEG/PNG/WebP hasta 10 MiB;
- solo la persona asignada puede preparar y confirmar la evidencia;
- ROOT/ADMIN autorizados pueden leerla para revisión;
- preparación y confirmación son idempotentes por `request_key`;
- un documento `submitted` satisface Documento v1;
- Foto + Checklist + Documento pueden completarse en cualquier orden y el último requisito pendiente decide el cierre;
- `closeType=human_review` lleva la ejecución a `waiting_review` sin crear otra cola de revisión.

La v1 no incluye firma, OCR, clasificación, borrado destructivo ni un mínimo configurable mayor que uno. Véase `WORKFLOW_DOCUMENT_EVIDENCE_CONTRACT.md`.

## 12. Próximo incremento técnico

Los pasos **Fotografía**, **Checklist** y **Documento**, junto con el cierre **human_review**, ya están conectados a la infraestructura existente. Checklist congela sus ítems por ejecución y Documento conserva evidencia privada ligada a la ejecución; ambos bloquean el cierre mientras falte su requisito.

Orden recomendado:

1. validar E2E humano Checklist y Documento en producción;
2. validar combinaciones Foto + Checklist + Documento en órdenes distintos;
3. validar la vista de Historial transversal con ejecuciones reales;
4. validar notificaciones operativas de creación/cierre/rechazo en producción;
5. validar Fecha concreta automática en producción;
6. validar Recurrente E2E en producción con al menos dos ocurrencias y cambio de responsable.

La automatización recurrente ya está implementada; queda su validación humana E2E tras despliegue antes de adaptar dominios legacy a este disparador.

## 13. Reglas de no regresión

- no duplicar `photo_patterns_v2` por flujo;
- no crear una segunda cámara ni duplicar almacenamiento para el mismo tipo de evidencia; cada evidencia distinta debe justificar su propio bucket privado y políticas;
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

Esto no debe generalizarse a dominios legacy aún no migrados. Checklist, Documento, Fecha concreta y Recurrente ya tienen contrato, implementación y regresión automatizada; sus E2E humanos se validan después del despliegue. `human_review` ya tiene contrato, implementación y validación E2E real.


### Incremento — Notificaciones operativas

Los workflows reutilizan `notifications_v2` mediante una correlación genérica por fuente:

- `onCreate` avisa al asignado;
- `onClose` avisa a creador + asignado sin duplicados;
- cierre `completed` y `rejected` tienen eventos diferenciados;
- la emisión es transaccional con el cambio de `workflow_executions_v2`;
- reintentos no duplican notificaciones;
- el canal inicial es únicamente in-app; email permanece desactivado hasta disponer de autoría explícita de canal.

No se crea un segundo motor de notificaciones.


La campanita personal de Inicio consume `notifications_v2` directamente bajo RLS, muestra contador de no leídas y permite marcar avisos como leídos. Los eventos de workflow enlazan a Tareas o Historial según corresponda. No se crea una bandeja paralela.


### Incremento — Fecha concreta automática

`triggerType=scheduled_once` dispone de scheduler transversal:

- la receta conserva `scheduledAt`, `scheduledTimezone` y `scheduledAtUtc`;
- Listo usa **Programar** y no crea tarea inmediatamente;
- asignación manual queda fijada al programar;
- responsable operativo se resuelve al llegar la fecha;
- `workflow_application_schedules_v2` conserva el estado operativo;
- `pg_cron` revisa vencimientos cada minuto;
- el disparo reutiliza el núcleo común de ejecución y `tenant_tasks_v2`;
- una clave idempotente evita duplicados;
- un fallo pasa a `blocked`, no deja ejecución parcial y avisa al creador;
- Fecha concreta no ofrece ejecución manual ni entra en lotes de Ejecutar.

### Incremento — Recurrente automático

Recurrente reutiliza `workflow_application_schedules_v2` y el mismo cron de Fecha concreta:

- exige **Primera ejecución** explícita con hora local + zona IANA + UTC;
- soporta semanal, quincenal, mensual y frecuencia personalizada;
- calcula cada ocurrencia desde el ancla original para evitar deriva mensual;
- conserva la hora local a través de DST y bloquea horas futuras ambiguas/inexistentes;
- manual fija el asignado al Programar; responsable operativo se resuelve en cada ocurrencia;
- tras una caída crea una sola obligación vencida y audita las ocurrencias intermedias omitidas;
- una nueva versión cancela la programación de la aplicación anterior;
- no admite ejecución manual ni ejecución masiva.

La regresión PostgreSQL cubre avance, idempotencia, catch-up, fin de mes, DST y cambio de responsable entre ocurrencias.


Los flujos recurrentes publicados antes de existir la primera fecha explícita no reciben una fecha inventada ni se migran destructivamente. Mis Flujos los identifica como **Necesita programación** y destaca **Editar programación**; si ya tienen historial, la corrección crea una nueva versión y conserva las ejecuciones anteriores.

### Incremento — WF-02 · Disparador genérico por evento

El valor declarativo `triggerType=event` pasa a ser capacidad ejecutable del motor:

- el Creador exige un evento concreto; inicialmente `occupancy.created`;
- un flujo de evento no permite asignación manual ni ofrece Ejecutar/Ejecutar en lote;
- `workflow_event_outbox_v2` desacopla el evento de negocio de la creación de tareas;
- `workflow_event_dispatches_v2` registra exactamente un resultado por evento/aplicación;
- el dispatcher reutiliza `workflow_execute_application_internal_v1` con `trigger_kind=event`;
- el mismo resolver de asignaciones de WF-01 se aplica al llegar el evento;
- el destino se compara server-side contra organización/piso/habitación/ocupación;
- un fallo de un workflow no revierte la operación de negocio ni otras ejecuciones correctas;
- el consumidor corre por `pg_cron` cada minuto;
- la regresión PostgreSQL cubre desacoplamiento, idempotencia, ejecución/tarea, aislamiento de fallos y privilegios.

