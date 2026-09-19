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

### Separación de autoría y operación

El **Creador de Flujos** concentra ahora toda la autoría:

- nuevo borrador;
- lista de borradores guardados;
- retomar/editar;
- publicar la primera versión;
- editar y publicar una futura versión.

Los borradores iniciales continúan en `workflow_definitions_v2(status='draft')`.

Cuando una definición ya está publicada, una futura versión se prepara en `workflow_definition_revision_drafts_v2`. Ese borrador conserva `base_version`, revisión optimista y especificación separada. Mientras se edita v2, v1 y sus aplicaciones siguen intactas.

La publicación de una nueva versión:

- exige AAL2;
- añade una nueva fila inmutable a `workflow_definition_versions_v2`;
- es idempotente ante reintentos;
- actualiza la metadata canónica únicamente después de publicar;
- no migra aplicaciones creadas con versiones anteriores.

**Mis Flujos** deja de ser zona de autoría: solo muestra recetas publicadas. Si existe una futura versión en borrador, la tarjeta lo indica y enlaza de vuelta al Creador.

### UX del Creador: Borradores y Editor separados

Para evitar que una lista creciente obligue a desplazarse hasta el formulario, el Creador usa dos vistas exclusivas:

- **Borradores**: buscador, filtro por estado, tarjetas compactas y carga progresiva de 12 elementos;
- **Editor**: únicamente el asistente de siete pasos y una cabecera con `← Borradores`.

Salir del Editor con cambios sin guardar ofrece **Guardar y salir / Salir sin guardar / Cancelar**. También existe **Guardar y salir** como acción directa. En un borrador persistido, **Descartar cambios locales** restaura la última revisión guardada en servidor en vez de vaciar el formulario.

### Continuidad UX: Diseño → Destino → Listo

La arquitectura interna continúa siendo `Definición → Versión → Aplicación → Ejecución`, pero esa terminología ya no obliga al usuario a navegar manualmente por cada capa.

Para una primera publicación, el Creador presenta una continuidad operativa de tres etapas:

`Diseño → Destino → Listo`

Al completar el paso 7, **Continuar para usarlo** guarda el borrador, publica una versión inmutable y lleva directamente a seleccionar el destino real. La UI denomina **Destino** a la aplicación concreta, aunque internamente se conserva `workflow_applications_v2`.

Después de guardar el destino, la misma experiencia muestra **Listo para usar**, resuelve la asignación permitida y ofrece **Ejecutar ahora** sin obligar a volver a Mis Flujos ni buscar manualmente la aplicación recién creada.

Las nuevas versiones publicadas mantienen un tratamiento conservador: se llega a la gestión de destinos sin migrar silenciosamente las aplicaciones existentes de versiones anteriores.

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

`workflow-definitions.html` es el **catálogo operativo** y consulta únicamente definiciones `published` mediante RLS.

Cada tarjeta se construye desde la última versión inmutable publicada y muestra:

- nombre;
- versión publicada;
- tipo;
- ámbito conceptual;
- activación;
- asignación;
- cierre;
- fecha de publicación.

Desde aquí se accede a **Aplicaciones**. También existe **Crear nueva versión**; esa acción prepara un borrador separado y redirige al Creador. Si ese borrador ya existe, la tarjeta indica que vN sigue operativa y permite **Continuar nueva versión**.

Mis Flujos no edita ni publica borradores directamente.

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

El motor ya puede publicar y ejecutar definiciones manuales reales. Limpieza sigue siendo el primer adaptador de dominio previsto, pero su migración debe esperar a que Documento e historial transversal estén suficientemente cerrados para no degradar el flujo legacy.

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
| Creador de Flujos | Implementado como workspace de autoría | Nuevo/editar/publicar borradores y futuras versiones |
| Mis Flujos | Implementado como catálogo operativo published-only | Aplicaciones + crear/continuar nueva versión |
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

Estas pruebas demuestran que el primer flujo manual con evidencia fotográfica **sí es operativo dentro del alcance implementado**. Checklist y revisión humana genérica ya tienen implementación propia; Documento y recurrencias siguen fuera del alcance operativo completo.

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

## 12. Próximo incremento técnico

Los pasos **Fotografía** y **Checklist**, junto con el cierre **human_review**, ya están conectados a la infraestructura existente. Checklist congela sus ítems por ejecución y bloquea el cierre hasta completar los obligatorios.

Orden recomendado:

1. validar E2E humano el nuevo paso Checklist en producción;
2. implementar Documento con el mismo principio de bloqueo de cierre;
3. completar la vista de Historial transversal ejecución → tarea → evidencia → revisión → cierre;
4. añadir notificaciones operativas específicas de cierre/rechazo;
5. después habilitar recurrencias automáticas.

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

Esto no debe generalizarse a capacidades aún pendientes. Checklist ya tiene contrato, implementación y regresión automatizada; su E2E humano se valida después del despliegue. Documento y recurrencia automática no pueden considerarse completos hasta que tengan contrato, implementación y E2E propios. `human_review` ya tiene contrato, implementación y validación E2E real.
