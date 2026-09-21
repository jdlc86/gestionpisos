# CODEX WORKFLOW COMPLETION PLAN

Fecha de baseline: 2026-09-20  
Último `main` verificado por ChatGPT: `main@a67837c3cfbbd0db31105c31a5d26ec2347a9923`

Este documento es el **tablero operativo persistente** para terminar la implantación de Flujos de Trabajo en GestionPisos/Allaiso sin perder contexto entre sesiones de Codex.

No sustituye a los contratos del repositorio. Debe leerse junto con `AGENTS.md` y la documentación de workflow enlazada más abajo.

---

## 1. Modelo de trabajo: ChatGPT dirige, Codex ejecuta

La relación de trabajo es deliberadamente asimétrica:

- **ChatGPT = orquestador y verificador independiente.**
  - decide el orden de los bloques;
  - comprueba el estado real de GitHub y Supabase;
  - revisa diffs, checks, migraciones, RLS y despliegues;
  - decide si un bloque está realmente terminado;
  - hace el merge cuando corresponde;
  - coordina pruebas humanas E2E;
  - actualiza o autoriza el paso al siguiente bloque.

- **Codex = brazo de implementación.**
  - trabaja únicamente el bloque marcado como ACTIVO;
  - inspecciona el estado actual de `main` antes de modificar;
  - implementa cambios pequeños y trazables;
  - añade/actualiza regresiones;
  - ejecuta las pruebas que estén a su alcance;
  - actualiza ESTE documento con evidencia y handoff;
  - abre/actualiza PR;
  - se detiene en `READY_FOR_CHATGPT_REVIEW`.

### Prohibición clave

**Codex no puede marcar un bloque como `VERIFIED`.**  
Ese estado solo lo asigna ChatGPT después de verificación independiente.

Codex tampoco debe:
- fusionar PRs;
- desplegar manualmente producción;
- ejecutar DDL manual en producción;
- usar `migration repair` como atajo;
- avanzar al bloque siguiente sin autorización explícita de ChatGPT.

---

## 2. Cómo evitar que Codex se quede sin contexto

Cada nueva sesión de Codex debe comenzar exactamente así:

1. Leer `AGENTS.md`.
2. Leer este documento completo.
3. Leer:
   - `docs/WORKFLOW_STATUS.md`
   - `docs/WORKFLOW_ARCHITECTURE.md`
   - `docs/WORKFLOW_ENGINE_CONTRACT.md`
   - `docs/WORKFLOW_APPLICATIONS_CONTRACT.md`
   - `docs/WORKFLOW_EXECUTION_CONTRACT.md`
   - `docs/WORKFLOW_TASKS_CONTRACT.md`
   - `docs/WORKFLOW_ACTIONS_CONTRACT.md`
   - `docs/WORKFLOW_SCHEDULE_CONTRACT.md`
4. Consultar el HEAD real de `main`.
5. Compararlo con **Último main verificado** de este documento.
6. Inspeccionar el código/migraciones/tests del bloque ACTIVO.
7. Solo entonces modificar.

Si la sesión anterior terminó, se perdió contexto o Codex fue reiniciado, **NO reconstruir el estado de memoria**. Recuperarlo desde:
- este archivo;
- Git;
- PR del bloque;
- checks;
- Supabase solo en modo inspección cuando esté disponible.

### Handoff obligatorio al final de cada sesión

Antes de detenerse, Codex debe actualizar dentro del bloque activo:

- `Estado`
- `Rama`
- `PR`
- `HEAD de rama`
- `Main observado al comenzar`
- `Cambios realizados`
- `Pruebas ejecutadas`
- `Checks GitHub observados`
- `Pendientes / bloqueadores`
- `Siguiente acción exacta`

Si no hubo cambio de código, debe decirlo expresamente.

---

## 3. Estados permitidos para un bloque

- `PLANNED`: todavía no iniciado.
- `IN_PROGRESS`: Codex está trabajando.
- `BLOCKED`: existe un bloqueo concreto documentado.
- `READY_FOR_CHATGPT_REVIEW`: Codex terminó su implementación y evidencia; espera verificación independiente.
- `VERIFIED`: ChatGPT verificó código + checks + estado real; puede abrirse el siguiente bloque.

Solo puede existir **un bloque ACTIVO** a la vez.

---

## 4. Reglas de ejecución por bloque

Cada bloque debe seguir:

`inspeccionar → rama → cambio pequeño → prueba → commit → repetir → PR → READY_FOR_CHATGPT_REVIEW`

Reglas:
- partir siempre del `main` real;
- no trabajar directamente en `main`;
- un PR por bloque salvo autorización explícita;
- migraciones nuevas son aditivas y versionadas;
- no reescribir una migración ya aplicada remotamente;
- no borrar histórico para simplificar;
- toda nueva autorización se valida server-side;
- RLS permanece activa;
- R3/R4 requieren pruebas negativas;
- un bug descubierto durante el bloque se corrige con regresión cuando sea viable;
- no rediseñar la UI general si el bloque no lo requiere;
- no introducir otro motor de tareas, fotos, Storage, notificaciones o recurrencia.

### Checks mínimos antes de entregar a ChatGPT

Codex debe comprobar, cuando apliquen:
- Governance Guard
- PWA Smoke
- Schema Guard

Si alguno está rojo, el bloque NO está listo.

---

## 5. Estado real del motor al crear este plan

### Implementado y no debe rehacerse

- Hub Flujos de Trabajo.
- Creador integrado `Diseño → Destino → Listo`.
- Publicar / Ejecutar / Descartar.
- Edición en sitio antes de historial.
- Nueva versión después de historial.
- Mis Flujos con búsqueda, selección múltiple, acciones masivas y última ejecución.
- Definiciones/versiones/aplicaciones/ejecuciones.
- Ejecución manual idempotente.
- Fecha concreta (`scheduled_once`).
- Recurrente (`recurring`).
- Materialización en `tenant_tasks_v2`.
- Aceptar / Rechazar.
- Foto.
- Checklist.
- Documento.
- Cierre automático.
- `human_review`.
- Historial transversal inicial.
- Notificaciones del motor.
- Eliminación/archivado según exista historial.
- Asignación manual por destino corregida en PR #266.
- Revalidación de relación vigente del ejecutor.
- Revocación de acceso de inquilino en Suspensión/Baja endurecida en PR #267.

### Huecos confirmados por inspección de producción

#### Disparadores
- `manual`: operativo.
- `scheduled_once`: operativo.
- `recurring`: operativo.
- `event`: **NO operativo todavía**.
  - la autoría/esquema reconocen `event`;
  - el ejecutor interno actual solo acepta `manual_now`, `scheduled_once` y `recurring`.

#### Asignación
- `manual`: operativo.
- `property_responsible`: operativo.
- `fixed_person`: **NO soportado todavía**.
- `role`: **NO soportado todavía**.
- `active_occupants_rotation`: **NO soportado todavía**.

Producción devuelve explícitamente `workflow_assignment_not_supported` para estos tres últimos.

### Dominio legacy existente

El motor legacy de tareas ya contiene semántica para:
- recogida de llaves;
- entrega de llaves;
- entrada/check-in;
- salida/check-out;
- limpieza;
- pago de alquiler;
- gestión de incidencia;
- reclamación de alquiler;
- reclamación por daños;
- fianza;
- genérico.

Esto **NO significa** que esos dominios estén ya migrados al motor transversal.  
No deben duplicarse; deben adaptarse gradualmente preservando histórico y comportamiento.

---

## 6. Orden obligatorio de bloques

La razón del orden es evitar que cada dominio implemente su propia solución para capacidades que pertenecen al motor común.

### BLOQUE WF-00 — Baseline y protocolo Codex
**Estado:** VERIFIED  
**Objetivo:** instalar este protocolo en el repo y dejar la línea base verificable.

Aceptación:
- este documento existe en `main`;
- `AGENTS.md` obliga a leerlo para trabajo de workflows;
- PR solo documental;
- checks verdes;
- ChatGPT verifica y marca `VERIFIED`.

**No implementar lógica de producto en este bloque.**

Handoff:
- Rama: `docs/codex-workflow-orchestration`
- PR: #268
- HEAD de rama al registrar el primer handoff: `644ca96bcce11d2ac59a1d9511eb9e273fd3e6e1`
- Commit que cerró WF-00 y activó WF-01: `9c77e25e347d77af4637ed7d3a8b72b0b405870b`
- Main observado al comenzar: `825a70c224cc3dc3a05f97a7477134d582f1c478`
- Cambios realizados: documento maestro + regla de descubrimiento en AGENTS
- Pruebas: cambios documentales; Governance Guard ✅, PWA Smoke ✅, Schema Guard ✅ sobre `6cd6d6a6c46e2231f69516f63e8f1f83abc10367`
- Verificación ChatGPT: completada; rama 0 behind y tres checks requeridos verdes antes de activar WF-01
- Bloqueadores: ninguno
- Siguiente acción: fusionar PR #268 tras checks verdes del HEAD final

---

### BLOQUE WF-01 — Asignaciones genéricas faltantes
**Estado:** VERIFIED


**Instrucción de arranque para Codex:** este es el único bloque que puede implementar tras el merge de WF-00. Debe crear una rama NUEVA desde el `main` real, inspeccionar la implementación actual y cambiar este estado a `IN_PROGRESS` en su primer commit del bloque.

Handoff para revisión:
- Rama: `codex/wf-01-assignment-rules`
- PR: [#269](https://github.com/jdlc86/gestionpisos/pull/269)
- HEAD verificado por ChatGPT antes del cierre documental: `a9d8c97140ef1899d4899771a69a823d2b0eae8d`.
- HEAD de implementación antes del commit de handoff: `d190f895a6873c5864b17d13a0d0e852a4a00401`
- Main observado al comenzar: `9088c21121735a312f2b576c161c0a03ad0cbce5`
- Main observado al terminar: `9088c21121735a312f2b576c161c0a03ad0cbce5`
- Cambios realizados: `fixed_person`, `role` y `active_occupants_rotation` configurables en autoría y resueltos server-side para manual, fecha concreta y recurrente; snapshot inmutable de ejecución, revalidación de relación vigente, controles UI y contratos actualizados. Una migración nueva; ninguna migración remota aplicada ni Edge Function modificada.
- Pruebas ejecutadas: `tests/database-regression-v2.sh` (PostgreSQL 17 desechable), `tests/workflows-smoke.sh`, `tests/pwa-smoke.sh`, `tests/login-auth-smoke.sh`, `tests/mfa-smoke.sh`, `tests/no-legacy-schema.sh`, `tests/migration-history-smoke.sh`, `tests/schema-regression-smoke.sh` y `tests/workflow-definition-schema-smoke.sh`: todas verdes. La regresión específica WF-01 cubre positivos/negativos, ROOT no ejecutor, revocación/suspensión, RLS, reintentos, rotación y programación.
- Checks GitHub verificados por ChatGPT en `a9d8c97140ef1899d4899771a69a823d2b0eae8d`: Governance Guard ✅, PWA Smoke ✅, Schema Guard ✅.
- Riesgos: migración R3 aún no aplicada a producción en el momento de esta verificación; debe desplegarse exclusivamente por el workflow normal tras merge.
- Verificación independiente ChatGPT: diff, resolver server-side, exclusión de ROOT, elegibilidad vigente, rotación/idempotencia, persistencia de `assignmentUserId`/`assignmentRole`, dependencias reales de Supabase y checks del mismo HEAD revisados. Aprobado para merge.
- Pendientes / bloqueadores: ninguno antes del merge; queda verificación post-merge de migración, Pages y checks.
- Prueba humana sugerida: tras la migración aprobada, ejecutar en un destino de prueba una asignación fija, una por rol y dos ocurrencias de rotación; suspender un ocupante y confirmar que solo cambia la elegibilidad futura.
- Siguiente acción exacta para ChatGPT: esperar checks del commit documental final, fusionar PR #269, verificar despliegue/migración post-merge y continuar con WF-02.


Implementar en el motor común, server-side:
1. `fixed_person`
2. `role`
3. `active_occupants_rotation`

Requisitos:
- configuración persistida en la versión de definición;
- resolución server-side en el momento de ejecutar;
- resultado congelado en la ejecución;
- solo candidatos con relación vigente;
- Suspensión/Baja revocan elegibilidad inmediatamente;
- ROOT no entra como ejecutor por ser ROOT;
- rotación estable, determinista e idempotente;
- cambios de ocupantes afectan ejecuciones futuras, nunca las históricas;
- compatible con manual, scheduled_once y recurring;
- UI no debe ofrecer una configuración que backend no pueda ejecutar.

Pruebas mínimas:
- positivo y negativo por tipo;
- usuario revocado/no vigente;
- ocupante suspendido/baja;
- dos reintentos no cambian asignado;
- rotación con entrada/salida de ocupantes;
- RLS/autorización.

---

### BLOQUE WF-02 — Disparador genérico por evento
**Estado:** VERIFIED

**Verificación independiente:** completada por ChatGPT antes del merge y post-merge.

Handoff final:
- Rama: `feat/wf-02-event-trigger`
- PR: [#270](https://github.com/jdlc86/gestionpisos/pull/270)
- Main observado al comenzar y base actual del PR: `da21d32adfff66a2ca99c5e025f7db53bfbf6828`
- HEAD de implementación verificado antes de este cierre documental: `322673def4313947b7bf9ae9f6713cbc1cd0c6d8`
- Divergencia observada: 0 commits detrás de `main`; PR mergeable; sin hilos de revisión abiertos.
- Arquitectura implementada: outbox + dispatcher común. El evento de negocio no crea tareas dentro de su transacción.
- Evento representativo inicial: `occupancy.created`, válido para ámbito organización, piso o habitación; ámbito ocupación se rechaza por ser temporalmente imposible.
- Persistencia: `workflow_event_outbox_v2` + `workflow_event_dispatches_v2`; rutas de negocio guardadas como snapshots, sin FKs destructivas a piso/habitación/ocupación/aplicación.
- Ejecución: `trigger_kind='event'` reutiliza `private.workflow_execute_application_internal_v1` y materializa trabajo exclusivamente en `tenant_tasks_v2`.
- Idempotencia: clave `event:<event_id>` por aplicación + recibo único evento/aplicación; ejecuciones correctas no se repiten.
- Fallos: una aplicación fallida no revierte el evento ni otras ejecuciones; queda reintentable, puede converger después y no duplica las ya correctas.
- Temporalidad: una aplicación/versión creada después de `occurred_at` no puede consumir retroactivamente un evento pendiente anterior.
- Seguridad: payload mínimo sin email del ocupante; tablas/funciones privadas sin escritura/ejecución directa para cliente autenticado; enrutamiento y asignación server-side.
- UX: Creador exige evento explícito, bloquea asignación manual y ámbito ocupación para `occupancy.created`; Listo usa **Activar**; Destinos/Mis Flujos muestran **Activo · esperando evento**; ejecución manual y masiva quedan excluidas, incluso ante URLs antiguas.
- PWA: shell `gestionpisos-shell-v43`; assets de Builder/Applications/Definitions versionados.
- Migraciones nuevas: `20260920103000_wf02_event_trigger_core.sql` y `20260920103100_wf02_event_trigger_cron.sql`. No se aplicaron manualmente a Supabase remoto.
- Cron previsto tras merge: `gestionpisos-workflow-events` cada minuto → `private.process_pending_workflow_events_v1(50)`.
- Factory reset: actualizado aditivamente para incluir outbox/recibos sin reescribir migraciones históricas.
- Regresión específica: `tests/workflow-event-trigger-regression.sql`; cubre autoría inválida, prohibición manual, captura desacoplada, no-PII, ejecución/tarea, aislamiento de fallos, recuperación por reintento, idempotencia, eliminación de flujo fallido sin historial, no consumo retroactivo y privilegios.
- Checks verificados sobre `322673def4313947b7bf9ae9f6713cbc1cd0c6d8`: Governance Guard ✅, PWA Smoke ✅, Schema Guard ✅ (regresión PostgreSQL aislada incluida).
- Documentación actualizada: Engine Contract, Execution Contract, Applications Contract, Implementation Map y Workflow Status; se corrigió también la regla heredada que trataba ROOT como ejecutor manual por defecto.
- Riesgo residual: despliegue real aún pendiente del workflow normal de merge; no se considera validación humana E2E hasta probar un evento real tras el despliegue.
- Prueba humana sugerida post-merge: activar un flujo de prueba por `occupancy.created`, confirmar 0 tareas iniciales, crear una ocupación temporal y verificar en <=1 ciclo del cron una sola tarea `trigger_kind=event` sin duplicados.
- Siguiente acción exacta: comprobar los tres checks del HEAD documental final, convertir PR #270 de draft a ready, comparar de nuevo contra `main`, fusionar por squash y verificar Supabase Migrations + Pages + checks + tablas/trigger/cron en producción. Solo después activar WF-03.

Objetivo: convertir `event` de opción declarativa a capacidad real del motor.

Requisitos:
- modelo explícito de fuente/tipo de evento;
- payload mínimo validado;
- idempotencia por evento origen;
- resolución de aplicación/destino server-side;
- ejecución usa el mismo motor interno;
- ninguna tabla de tareas paralela;
- auditoría e histórico;
- evitar listeners específicos por dominio cuando pueda existir un dispatcher común.

Eventos iniciales necesarios para dominios posteriores:
- alta/entrada de ocupación;
- suspensión/reactivación cuando aplique;
- baja/salida;
- incidencia creada/cerrada;
- cambio relevante que el contrato del dominio necesite.

No conectar todos los dominios en este bloque; solo infraestructura + una prueba representativa.

---

### BLOQUE WF-03 — Adaptador Limpieza
**Estado:** VERIFIED

**Cierre verificado por ChatGPT (2026-09-20):**
- Rama de implementación: `feat/wf-03-cleaning-adapter`.
- PR: #271, fusionado.
- Commit de merge/resultado en `main`: `b14fc58c39a4c40c03fea5c7e0bd341df1743489`.
- El adaptador es **opt-in**: `flowType=cleaning` + `closeType=domain_adapter`. Las limpiezas legacy/genéricas conservan su comportamiento previo.
- `tenant_tasks_v2` sigue siendo la única tarjeta operativa transversal; `cleaning_tasks_v2` es expediente especializado enlazado al workflow, no un segundo motor de tareas.
- Se preservan decisión Aceptar/Rechazar, varias fotos, auditoría/revisión, informe final único, swaps entre ocupantes y deuda legacy, con sincronización atómica de asignado/estado.
- La UI transversal elimina la dependencia normal de introducir manualmente IDs legacy de limpieza.
- Seguridad revisada: autorización server-side, RLS mantenida, AAL2 en revisión sensible, bridge de revisión no expuesto al cliente y regresiones negativas.
- Checks requeridos del HEAD de WF-03 fueron verificados verdes antes del merge: Governance Guard ✅, PWA Smoke ✅, Schema Guard ✅.
- Producción verificada tras merge: migraciones `20260920113000`, `114000`, `115000`, `124500`, `134000`, `141000`, `143000` y `143100` presentes.
- Edge Functions de WF-03 verificadas ACTIVE en producción: `review-photo-verification` v8 y `my-cleaning-checklist` v5, con JWT requerido.
- No quedan pendientes que bloqueen el siguiente dominio. No reabrir WF-03 salvo regresión concreta.

**Contexto posterior que Codex debe respetar:**
- Tras WF-03 se cerró el bug crítico de reactivación de inquilino en PR #274.
- `main` actual verificado al activar WF-04: `98242d6bb2aa61fdaea813dcb180659cc2ce07d3`.
- La reactivación ya no debe depender de multi-escrituras cliente. Existen `reactivate_tenant_occupancy_v1`, `restore_tenant_platform_access_v1` y `has_current_platform_access_v1()`; no debilitarlas ni sustituirlas.
- La prueba humana final del caso real Suspendido → Alta → acceso fue satisfactoria después de reparar una inconsistencia histórica previa a #274.
- El estado UI `Acceso pendiente de vincular` es diagnóstico de inconsistencia, no un estado normal estable del lifecycle.

Objetivo cumplido:
- expresar Limpieza mediante el motor transversal sin perder semántica legacy;
- mantener coexistencia e histórico;
- no crear tareas operativas paralelas.

---

### BLOQUE WF-04 — Check-in / Check-out + llaves
**Estado:** IMPLEMENTED_DEPLOYED_E2E_DEFERRED
**Bloque ACTIVO:** no — implementación, revisión independiente, merge y despliegue completados. El E2E humano queda deliberadamente diferido a la batería final conjunta por decisión del usuario; NO marcar VERIFIED todavía.

**Handoff obligatorio de Codex (2026-09-20):**
- Rama: `codex/wf-04-checkin-checkout-keys` (nueva desde `main`; no reutiliza WF-03 ni #274).
- PR activo de revisión: [#279](https://github.com/jdlc86/gestionpisos/pull/279). Sustituye a #276/#277/#278 únicamente para obtener CI sobre el HEAD final generado por el conector; los anteriores quedan cerrados sin merge.
- HEAD de rama de implementación sometido a las pruebas y checks: `07e69b64ce5a5bbe28842560f91aca077d08abd1`. El HEAD final de rama es el commit documental que contiene este handoff y debe leerse en el PR; no se autocita un SHA que aún no existe al redactarlo.
- Main observado al comenzar: `6e9d35018968407bcbb42faf98298c4eedd37a8b`, descendiente de `98242d6bb2aa61fdaea813dcb180659cc2ce07d3`.
- Cambios realizados: `occupancy.offboarded` en el outbox/dispatcher WF-02 solo tras Baja real; vinculación exacta de evento y ocupación a la ejecución/tarjeta; autoría nueva de Check-in/Check-out limitada al evento lifecycle correcto; acciones aceptar/rechazar, recogida/entrega de llaves y confirmación de entrada/salida sobre `tenant_tasks_v2`, con revalidación de destino/asignado, idempotencia, historia y auditoría. La tarjeta transversal y el historial muestran los hitos; las rutas legacy y el camino atómico de reactivación #274 permanecen. Cuatro migraciones aditivas; ninguna aplicada remotamente.
- Pruebas ejecutadas: regresión PostgreSQL 17 completa `tests/database-regression-v2.sh` y modo enfocado `WF04_FOCUSED=1`, ambas verdes; cubren evento→una ejecución/tarjeta, reintentos, destino y asignado no vigentes, RLS negativa, llaves sin efecto en Auth/lifecycle, entrada futura, Baja/Salida, Suspensión/reactivación #274, legacy y auditoría. `tests/workflows-smoke.sh`, `tests/pwa-smoke.sh`, login/MFA, contratos de esquema/documentación y `node --check` de módulos modificados, verdes. No se hizo E2E humano ni despliegue.
- Checks GitHub observados para el HEAD de implementación `07e69b6`: Governance Guard ✅, PWA Smoke ✅, Schema Guard ✅ (incluida regresión PostgreSQL aislada). Revalidar los tres en el HEAD documental final del PR.
- Correcciones de revisión independiente aplicadas por ChatGPT: los `occupancy.created` obsoletos por lifecycle se retiran como `processed_with_errors` sin bloquear la cola; sujetos legacy aún sin `tenant_id` siguen `pending` y recuperan el mismo evento al vincularse; `reject` mantiene tarea y ejecución en `rejected`, recuperando Historial y `workflow_rejected`; la asignación por rol WF-04 filtra escritura antes del desempate determinista; ADMIN exige AAL2 server-side para actuar. Regresiones específicas añadidas para estos comportamientos.
- Estado post-merge verificado por ChatGPT: PR #279 fusionado en `main@a69c7534748a21114643e7f0d746b0fcb0934e03`; Governance Guard, PWA Smoke y Schema Guard verdes sobre el HEAD final pre-merge; Deploy GitHub Pages y Supabase Migrations ejecutados tras merge; migraciones WF-04 `20260920192346`, `20260920193646`, `20260920194226` y `20260920194659` presentes en producción.
- Pendiente deliberado: E2E humano completo de Entrada → llaves → Salida/Baja → acceso. No bloquea la implementación de WF-05 a WF-09, pero debe ejecutarse dentro de la batería final conjunta antes de considerar el programa workflow totalmente verificado.
- Siguiente acción exacta: mantener WF-04 congelado salvo regresión concreta y avanzar a WF-05. No marcar WF-04 `VERIFIED` hasta completar la batería final.

**Arranque y mapa real observado (primer commit WF-04):**
- Rama nueva: `codex/wf-04-checkin-checkout-keys`. Base: `main` remoto `6e9d35018968407bcbb42faf98298c4eedd37a8b`, descendiente del `98242d6bb2aa61fdaea813dcb180659cc2ce07d3` exigido. Entre ambos solo cambió este plan para cerrar WF-03 y activar WF-04.
- Legacy: `tenant_tasks_v2` conserva `key_pickup`, `key_delivery`, `check_in` y `check_out`. `tenant_task_workflow_templates_v2` da a las llaves `requested → accepted/rejected → completed` y a Entrada/Salida `scheduled → completed` o reprogramación. `docs/portfolio.html` ofrece los cuatro tipos; `docs/portfolio.js` crea mediante `create_tenant_task_v2` y actúa mediante `apply_tenant_task_action_v2`. El guard de `20260918114500_workflow_atomic_task_actions.sql` reserva `apply_workflow_task_action_v1` para tarjetas workflow, sin retirar la ruta legacy.
- Lifecycle y acceso: `occupancies_v2` mantiene estado/fechas autoritativos. Cartera aún edita ocupaciones directamente en casos ordinarios, pero Baja usa `offboard_tenant_occupancy_v2`; Suspensión se representa con `blocked`; Suspendido → Alta usa la RPC atómica `reactivate_tenant_occupancy_v1` de #274. `restore_tenant_platform_access_v1` y `has_current_platform_access_v1()` condicionan el acceso al rol e identidad vigentes y a una ocupación `active` dentro de fechas. Ni una tarea ni la entrega/recogida de llaves son autoridad de acceso.
- Eventos: WF-02 solo admite y emite `occupancy.created`, mediante trigger de inserción → `workflow_event_outbox_v2` → `private.process_pending_workflow_events_v1` → `workflow_event_dispatches_v2`. El despacho exige aplicación configurada/publicada con antigüedad suficiente y clave idempotente `event:<id>`; no existe aún evento lifecycle para Baja/Suspensión o cambios de ocupación.
- Motor común: definiciones/versiones publicadas y aplicaciones configuradas seleccionan destino exacto; `private.workflow_execute_application_internal_v1` crea `workflow_executions_v2` y materializa una sola tarjeta `tenant_tasks_v2` por ejecución. WF-01 resuelve el asignado según alcance, rol, asociación vigente o inquilino de la ocupación; la acción atómica workflow conserva historia/auditoría y comprueba identidad. El trabajo WF-04 deberá reutilizar estas piezas y probar de nuevo vigencia de destino/asignado al actuar, sin motor paralelo ni replay retroactivo.

**Instrucción de arranque para Codex:**
1. Leer `AGENTS.md`, este documento completo y todos los contratos workflow obligatorios.
2. Consultar el HEAD real de `main`. Debe ser `98242d6bb2aa61fdaea813dcb180659cc2ce07d3` o un descendiente; si ha avanzado, inspeccionar primero qué cambió.
3. Crear una rama **nueva** desde el `main` real. No reutilizar ramas de WF-03 ni de #274.
4. Antes de modificar lógica, inspeccionar y documentar:
   - tipos legacy de Recogida de llaves, Entrega de llaves, Entrada y Salida;
   - RPC/triggers/funciones que hoy mutan ocupaciones o acceso;
   - eventos lifecycle ya emitidos por WF-02 y su outbox/dispatcher;
   - `tenant_tasks_v2`, definiciones/aplicaciones/ejecuciones y reglas de asignación WF-01;
   - contratos de Auth/lifecycle que fueron endurecidos en #274.
5. En el primer commit de WF-04, cambiar este estado a `IN_PROGRESS` y registrar rama, HEAD base y mapa de implementación observado.
6. Implementar en bloques pequeños: inspección → cambio concreto → regresión → commit. No hacer una migración o refactor masivo de una sola vez.

**Objetivo de WF-04:** unificar mediante el motor transversal:
- Recogida de llaves.
- Entrega de llaves.
- Entrada / check-in.
- Salida / check-out.

**Principios de dominio obligatorios:**
- Las fechas y estados de `occupancies_v2` son la autoridad del lifecycle.
- Una acción de llaves **nunca** concede, reactiva ni conserva acceso de plataforma por sí sola.
- Check-in/check-out no pueden crear una segunda verdad de ocupación ni un segundo motor de tareas.
- `tenant_tasks_v2` sigue siendo la tarjeta operativa única; cualquier expediente específico debe enlazarse al workflow, no duplicarlo.
- Baja/Suspensión pueden cortar acceso según los contratos existentes, pero nunca destruyen el histórico.
- Reactivación debe reutilizar el camino atómico introducido por #274; está prohibido volver a una secuencia cliente de varias escrituras.
- No debilitar `has_current_platform_access_v1()`, RLS ni las restricciones de ocupación para “hacer pasar” el workflow.
- El destino debe ser exacto y el asignado debe seguir siendo elegible en el momento de ejecutar/actuar.
- Reintentos del mismo evento no pueden duplicar ejecución, tarea, entrega/recogida ni efectos de lifecycle.
- Las acciones operativas deben ser auditables y conservar actor/origen.

**Uso de eventos:**
- Debe aprovechar la infraestructura genérica `event` de WF-02.
- Codex debe verificar qué eventos lifecycle existen realmente antes de añadir ninguno.
- Si falta un evento necesario, extender el outbox/dispatcher común; no crear listeners paralelos específicos del dominio.
- La creación/cambio de ocupación no debe acoplarse transaccionalmente a la creación de tareas: evento de negocio primero, despacho workflow después, con idempotencia.
- No consumir retroactivamente eventos anteriores a la activación de una aplicación salvo que el contrato lo defina explícitamente.

**Alcance inicial recomendado tras inspección:**
1. Mapear semántica legacy → workflow sin cambiar comportamiento.
2. Conectar un caso representativo de Entrada/check-in al evento lifecycle existente.
3. Añadir Salida/check-out preservando histórico y reglas de acceso.
4. Integrar Recogida/Entrega de llaves como acciones de dominio sin autoridad sobre Auth.
5. Cerrar equivalencia UI/E2E y compatibilidad legacy.
6. Solo entonces preparar el PR para revisión de ChatGPT.

**Pruebas mínimas obligatorias:**
- evento válido → exactamente una ejecución y una tarjeta;
- reintento del mismo evento → 0 duplicados;
- destino incorrecto/no vigente → rechazo;
- asignado revocado/no vigente → no puede actuar;
- acción de llave → no modifica Auth, rol tenant ni vigencia de ocupación;
- check-in → no concede acceso antes de la fecha/estado autorizado;
- check-out/Baja → conserva histórico y no deja acceso operativo indebido;
- Suspensión → no se confunde con Salida ni con Entrega de llaves;
- reactivación posterior → usa el lifecycle seguro vigente y no recrea el bug #274;
- RLS/autorización negativa para inquilino/empleado fuera de alcance;
- compatibilidad con registros legacy existentes;
- idempotencia y auditoría.

**Fuera de alcance de WF-04:**
- Incidencias/mantenimiento/inspección (WF-05).
- Pago/reclamación de alquiler (WF-06).
- Daños/fianza (WF-07).
- Presets generales de dominio (WF-08).
- Retirada global del legacy (WF-09).
- Rediseños visuales no necesarios para cerrar este dominio.

**Entrega obligatoria de Codex:**
- un solo PR de WF-04 salvo autorización explícita;
- migraciones aditivas y versionadas;
- regresiones nuevas para cada bug o regla crítica;
- Governance Guard, PWA Smoke y Schema Guard verdes sobre el mismo HEAD;
- actualizar aquí el handoff completo;
- detenerse en `READY_FOR_CHATGPT_REVIEW`;
- **no fusionar, no desplegar manualmente y no activar WF-05**.

---

### BLOQUE WF-05 — Incidencia / Mantenimiento / Inspección
**Estado:** IMPLEMENTED_DEPLOYED_E2E_DEFERRED
**Bloque ACTIVO:** no — implementación, revisión independiente, merge y despliegue completados. El E2E humano queda deliberadamente diferido a la batería final conjunta; NO marcar VERIFIED todavía.

**Arranque y mapa real observado (primer commit WF-05, 2026-09-21):**
- Rama nueva: `codex/wf-05-incidents-maintenance-inspection`. Base exacta: `main` remoto `a69c7534748a21114643e7f0d746b0fcb0934e03`, que contiene WF-04 revisado y fusionado. El PR documental #280 seguía abierto al comenzar; esta rama incorpora su decisión de diferir el E2E humano de WF-04 para que la trazabilidad no dependa de ese merge.
- Expediente legacy: `incidents_v2`, `incident_updates_v2` e `incident_evidence_v2` existen desde Beta 0. La incidencia conserva organización, piso, habitación opcional, creador, asignado, categoría, prioridad y estados legacy; updates separan visibilidad `tenant/internal/owner` y evidence conserva rutas privadas. No existe tabla específica de mantenimiento ni de inspecciones. Mantenimiento aparece como `flowType`, propósito fotográfico y estado de piso; Inspección aparece como `flowType` y tipo/source fotográfico.
- Autoridad operativa: `tenant_tasks_v2` ya admite el tipo legacy `incident` y sus plantillas contienen `accept`, `request_info`, `resume` y `resolve`, pero ese camino legacy solo está ligado al modal de tareas por inquilino en Cartera y usa `create_tenant_task_v2`/`apply_tenant_task_action_v2`. No enlaza `incidents_v2`, no crea `workflow_executions_v2` y no debe convertirse en la implementación de WF-05. La tarjeta transversal nueva sigue siendo `task_type=workflow`, `source_kind=workflow_execution`.
- UI real: `docs/incidents.html` es una pantalla estática «en preparación» sin módulo JS de datos. El Creador ya ofrece `maintenance` e `inspection`; Foto, Checklist, Documento, Tareas e Historial son superficies operativas y genéricas. No existe una UI operativa específica de mantenimiento/inspección que haya que conservar.
- Backend real: no hay RPC, trigger ni Edge Function que abra, asigne o transicione `incidents_v2`; tampoco hay productor `incident.*` en el outbox. Las únicas policies legacy de incidencias son SELECT para ROOT/ADMIN basadas en claims JWT y no existe escritura cliente autorizada. La inspección solo reutiliza hoy tipos de foto, no un expediente propio.
- Motor reutilizable: WF-02 aporta `workflow_event_outbox_v2`, `workflow_event_dispatches_v2` y `private.process_pending_workflow_events_v1`; hoy solo admite `occupancy.created/offboarded`. Definición → versión → aplicación → ejecución materializa exactamente una `tenant_tasks_v2`, congela asignación/snapshot y registra eventos/auditoría. WF-01/WF-04 revalidan asignado y destino server-side; WF-05 deberá extender ese mismo camino, no crear listeners ni runner paralelos.
- Evidencias y cierre: `workflow_execution_photo_resources_v2`, `workflow_executions_v2.checklist_state` y `workflow_execution_documents_v2` ya coordinan Foto/Checklist/Documento sobre la misma ejecución. `notifications_v2` y el trigger de ejecución ya deduplican avisos de creación/cierre. Un expediente de incidencia debe enlazarse a la ejecución y reutilizar esas piezas; las tablas legacy de evidencia no se reinterpretarán ni borrarán.
- Estado remoto contrastado en lectura: el proyecto Supabase `qsxtmmkftsohkqqmytbb` coincide con este mapa de Git para columnas, policies, RPC y triggers de incidencias/workflow. No se aplicó ninguna mutación remota.

**Instrucción de arranque para Codex:**
1. Leer `AGENTS.md`, este documento completo y los contratos workflow actuales antes de modificar nada.
2. Comprobar el HEAD real de `main`; debe ser `a69c7534748a21114643e7f0d746b0fcb0934e03` o un descendiente. Si avanzó, inspeccionar primero el delta.
3. Crear una rama nueva desde el `main` real. No reutilizar ramas WF-04.
4. En el primer commit cambiar WF-05 a `IN_PROGRESS` y registrar el mapa real encontrado: modelos legacy de incidencia/mantenimiento/inspección, RPC/Edge Functions, UI, RLS, tareas, notificaciones y cualquier integración fotográfica/documental existente.
5. Trabajar en bloques pequeños: inspección → cambio concreto → regresión → commit.
6. No reabrir ni rediseñar WF-00..WF-04 salvo que una dependencia real y demostrable de WF-05 lo exija.
7. No hacer E2E humano de WF-04 ahora; esa prueba queda en la batería final conjunta.

**Objetivo:**
- Gestión de incidencia sobre el motor común.
- Mantenimiento como categoría transversal.
- Inspección reutilizando Foto/Checklist/Documento.

**Debe soportar:**
- abrir;
- aceptar gestión;
- solicitar información;
- continuar;
- resolver;
- revisión/evidencia cuando proceda;
- evento posterior opcional, p.ej. inspección después de reparación.

**Principios obligatorios:**
- `tenant_tasks_v2` sigue siendo la tarjeta operativa transversal; no crear un segundo motor de tareas.
- Si existe expediente específico de incidencia/mantenimiento, debe ser dominio enlazado al workflow, no autoridad paralela.
- Reutilizar Foto/Checklist/Documento ya construidos; no duplicar subsistemas.
- Preservar RLS y autorización server-side por organización/piso/responsabilidad.
- Revalidar asignado y destino al actuar, no solo al crear la ejecución.
- Solicitar información y continuar deben ser estados/acciones auditables e idempotentes.
- Resolver debe tener una semántica terminal única y consistente con Historial/notificaciones.
- Los eventos posteriores opcionales deben usar el outbox/dispatcher común de WF-02; no listeners paralelos.
- No mezclar todavía Pago/Reclamación (WF-06), Daños/Fianza (WF-07), presets (WF-08) ni retirada legacy (WF-09).

**Pruebas mínimas obligatorias:**
- incidencia válida → una ejecución y una tarjeta;
- reintento → 0 duplicados;
- aceptar → estado consistente en tarea/ejecución/historial;
- solicitar información → transición auditable y no terminal;
- continuar tras información → recupera la misma ejecución, no crea otra;
- resolver → cierre consistente y notificación final cuando corresponda;
- asignado sin permiso o revocado → rechazo server-side;
- destino fuera de alcance → rechazo;
- evidencia Foto/Checklist/Documento reutiliza contratos existentes;
- evento posterior opcional → exactamente una ejecución downstream;
- RLS negativas para actores fuera de alcance;
- compatibilidad con registros legacy existentes.

**Entrega obligatoria de Codex:**
- un solo PR WF-05 salvo autorización explícita;
- migraciones aditivas/versionadas; no modificar migraciones aplicadas;
- nuevas regresiones para reglas críticas y bugs;
- Governance Guard, PWA Smoke y Schema Guard verdes sobre el mismo HEAD;
- actualizar este handoff con rama, PR, HEAD, archivos/migraciones, pruebas, riesgos y pendientes;
- detenerse en `READY_FOR_CHATGPT_REVIEW`;
- no fusionar, no desplegar manualmente y no activar WF-06.

**Handoff WF-05 (2026-09-21):**
- Rama: `codex/wf-05-incidents-maintenance-inspection`, creada desde `main@a69c7534748a21114643e7f0d746b0fcb0934e03`. `origin/main` seguía en ese mismo SHA al cerrar el bloque.
- PR: [#281 — WF-05: incidencia, mantenimiento e inspección](https://github.com/jdlc86/gestionpisos/pull/281), fusionado por squash en `main@a67837c3cfbbd0db31105c31a5d26ec2347a9923`. El PR documental #280 quedó cerrado sin merge por quedar supersedido por WF-05.
- HEAD de implementación validado antes de este handoff: `45ffcd63d83c7d7cc4aea5454b8336d38f199649`; corrección posterior del contrato visual detectada por PWA Smoke: `3fa7ac5428f96120808007e7a36322082ea9049c`. El HEAD final es siempre la punta publicada de la rama; los checks de PR #281 son la fuente autoritativa de su SHA y estado CI.
- Migraciones aditivas: `20260921062822_wf05_incident_domain_core.sql`, `20260921064050_wf05_incident_event_workflow_link.sql` y `20260921065433_wf05_incident_domain_actions.sql`. No se aplicaron migraciones ni cambios manuales en Supabase remoto.
- Dominio entregado: apertura idempotente de incidencia/mantenimiento; `incident.created` por el outbox WF-02; vínculo exacto expediente/evento/ejecución; una `tenant_tasks_v2` por ejecución; aceptar, rechazar, solicitar información, continuar y resolver sobre el RPC común; revalidación server-side del asignado y destino; MFA privilegiado; historial, auditoría y notificaciones coherentes; `incident.resolved` capaz de activar una Inspección posterior por el mismo dispatcher.
- Reutilización: Foto, Checklist y Documento siguen en sus tablas, buckets y RPC existentes. Mantenimiento es `flowType=maintenance`; Inspección es `flowType=inspection`; no se creó otro motor, listener, cron, bandeja ni tabla específica de inspección.
- UI: `incidents.html/css/js` consulta bajo RLS, abre por RPC y permite responder a solicitudes de información; Creador, Mis Flujos, Tareas e Historial presentan los eventos, requisitos y acciones WF-05. El cliente no recibe privilegios de escritura directa sobre las tablas de incidencia.
- Contratos/documentación: nuevo `WORKFLOW_INCIDENT_MAINTENANCE_INSPECTION_CONTRACT.md`; actualizados los contratos transversales afectados, el contrato de incidencias, el índice, el mapa de implementación y el estado real.
- Regresión PostgreSQL: `workflow-wf05-domain-regression.sql` cubre apertura → una ejecución/tarjeta por aplicación compatible; reintento sin duplicados; aceptación; espera de información no terminal y auditable; respuesta idempotente; continuación en la misma ejecución; resolución coherente; rechazo por asignado revocado, destino alterado y ROOT sin AAL2; Foto/Checklist/Documento comunes; una ejecución downstream por aplicación; RLS negativas; compatibilidad legacy; auditoría y notificaciones. La suite completa `database-regression-v2.sh` terminó verde en PostgreSQL 17 desechable.
- Guards locales sobre el HEAD de implementación: Governance Guard ✅; PWA Smoke y todos sus subchecks ✅; Schema Guard estático ✅; regresión PostgreSQL completa ✅. Tras este commit documental deben quedar verdes Governance Guard, PWA Smoke y Schema Guard sobre el mismo HEAD final de PR #281 antes de cualquier merge.
- Correcciones de revisión independiente aplicadas por ChatGPT: `incident.created` admite un único gestor Mantenimiento canónico por destino efectivo y rechaza configuraciones solapadas; `workflow_execution_actor_current_v1()` revalida además la regla congelada `property_responsible/fixed_person/role` después de comprobar acceso y sujeto WF-05; `request_info` funciona también para expedientes abiertos por personal interno, con visibilidad `internal` y respuesta del creador autorizado sobre la misma ejecución. Se añadieron regresiones específicas para estos hallazgos.
- Producción post-merge: migraciones `20260921062822_wf05_incident_domain_core`, `20260921064050_wf05_incident_event_workflow_link` y `20260921065433_wf05_incident_domain_actions` aplicadas por el workflow normal de Supabase. Verificados en producción los RPC `open_workflow_incident_v1`, `submit_incident_information_v1`, la acción privada WF-05 y los triggers de solapamiento/siembra.
- Correcciones finales de revisión: un único gestor maintenance por destino efectivo; revalidación de regla de asignación al actuar; bucle pedir información → responder → continuar válido también para creador interno, con visibilidad `internal` y autorización estricta del creador.
- E2E humano integral: diferido deliberadamente a la batería final conjunta junto con WF-04. No bloquear WF-06 por esta deuda documentada.
- Riesgos/pendientes deliberados: las inspecciones `incident.resolved` conservan fan-out por aplicación compatible; el camino legacy `task_type=incident` permanece solo por compatibilidad hasta WF-09.
- Siguiente acción exacta: mantener WF-05 congelado salvo regresión concreta y avanzar a WF-06. No marcar WF-05 `VERIFIED` hasta completar la batería final.

---

### BLOQUE WF-06 — Pago de alquiler + reclamación de alquiler
**Estado:** IN_REVIEW
**Bloque ACTIVO:** sí — implementación directa por ChatGPT en PR #283; Codex queda reservado por límite de crédito. El E2E humano de WF-04/WF-05 queda diferido a la batería final y NO bloquea este bloque.

**Instrucción de arranque para Codex:**
1. Leer `AGENTS.md`, este documento completo y los contratos workflow actuales.
2. Comprobar el HEAD real de `main`; debe ser `a67837c3cfbbd0db31105c31a5d26ec2347a9923` o un descendiente. Si avanzó, inspeccionar primero el delta.
3. Crear una rama NUEVA desde el `main` real. No reutilizar ramas de WF-05.
4. En el primer commit cambiar WF-06 a `IN_PROGRESS` y documentar el mapa real de pagos/reclamaciones: tablas legacy, obligaciones, recordatorios, tareas, notificaciones, RPC/triggers/cron, UI, RLS y cualquier integración financiera existente.
5. Trabajar en bloques pequeños: inspección → cambio concreto → regresión → commit.
6. No reabrir WF-00..WF-05 salvo una dependencia real y demostrable.
7. No hacer E2E humano de WF-04/WF-05 ahora; queda para la batería final conjunta.

**Mapa real al iniciar (2026-09-21):**
- Rama: `feat/wf-06-rent-payment-claims`, creada desde `main@6591482155b53f82cee9f23890b58c4201f45357`.
- Dominio legacy existente: `payment_obligations_v2`, `claims_v2`, `reminder_rules_v2`; sin RPC/triggers de dominio para pago/reclamación.
- `payment_obligations_v2` conserva `pending/paid/overdue/waived/cancelled`, importe, moneda y vencimiento. `claims_v2` conserva expediente de reclamación pero no workflow transversal.
- Las policies legacy de escritura de obligaciones/reclamaciones se apoyan todavía en claims JWT ADMIN/ROOT; WF-06 no ampliará escritura cliente y llevará mutaciones sensibles a RPC server-side.
- Semántica legacy en tareas: Pago = registrar/solicitar/aplazar; Reclamación = notificar, aceptar/disputar, pedir información, continuar y resolver. Aceptar/disputar pertenece al inquilino; la gestión restante pertenece a la gestoría.
- El motor transversal ya materializa `tenant_tasks_v2` con `tenant_id` automáticamente cuando el ámbito es `occupancy`. Esto se reutiliza para Pago.
- Diseño fijado: `rent_payment` será `domain_adapter` sobre una ocupación exacta y soportará manual/fecha/recurrente; cada ejecución genera exactamente una obligación. La acción Reclamar crea un expediente `claims_v2` y publica `rent_claim.created` por el outbox WF-02. `rent_claim` consume ese evento sobre piso/habitación y conserva acciones mixtas gestoría/inquilino en la misma tarjeta.
- No se tocará producción durante implementación; solo migraciones versionadas en Git.
- PR de implementación: **#283** (`feat/wf-06-rent-payment-claims`).
- Migraciones: `20260921135000_wf06_rent_domain_core.sql`, `20260921140500_wf06_rent_execution_binding.sql`, `20260921142000_wf06_rent_domain_actions.sql`.
- Regresión: `tests/workflow-wf06-domain-regression.sql`, integrada en `database-regression-v2.sh`.
- Contrato: `docs/WORKFLOW_RENT_PAYMENT_CLAIM_CONTRACT.md`.
- PWA: Creador con Pago/Reclamación y Tareas con acciones mixtas + aplazamiento tipado.
- Evidencia durante revisión: Governance y PWA han pasado en HEADs de #283; Schema Guard completo pasó en HEADs anteriores del mismo PR después de integrar WF-06. Se exige una ronda final común antes del merge.

**Objetivo:**
- Integrar Pago de alquiler y Reclamación de alquiler sobre el motor transversal.
- Conservar la semántica legacy sin crear un segundo motor financiero ni de tareas.

**Debe conservar como mínimo:**
- registrar pago;
- solicitar pago;
- aplazar;
- reclamar;
- aceptar/disputar;
- pedir información;
- continuar;
- resolver.

**Principios obligatorios:**
- `tenant_tasks_v2` sigue siendo la tarjeta operativa transversal.
- Las obligaciones/pagos/reclamaciones pueden conservar expediente de dominio, pero nunca una segunda autoridad de tareas.
- No convertir WF-06 en contabilidad ni en ledger general.
- Reutilizar tablas/relaciones financieras legacy cuando sean la autoridad correcta; enlazarlas a la ejecución en vez de duplicarlas.
- Toda transición sensible debe ser server-side, idempotente y auditable.
- Ningún cliente autenticado obtiene escritura directa adicional sobre tablas financieras por conveniencia.
- Revalidar organización, piso, ocupación/inquilino y actor en cada acción.
- No permitir que un empleado sin permiso vigente registre, reclame o resuelva.
- Aplazar no equivale a pagar ni cerrar; debe ser estado no terminal con nueva fecha/condición trazable.
- Registrar pago debe ser idempotente y no crear dobles pagos por reintento.
- Reclamación debe reutilizar la misma obligación/expediente cuando corresponda; no duplicar deuda.
- Aceptar/disputar y pedir información deben quedar en historial/auditoría.
- Notificaciones y eventos posteriores deben usar infraestructura común, no listeners paralelos.
- No mezclar Daños/Fianza (WF-07), presets (WF-08) ni retirada legacy (WF-09).

**Pruebas mínimas obligatorias:**
- obligación válida → una ejecución y una tarjeta;
- reintento → cero duplicados;
- registrar pago → cierre/coherencia exacta sin doble registro;
- solicitar/reclamar → estados coherentes;
- aplazar → no terminal, nueva fecha trazable, misma ejecución;
- aceptar/disputar → historial/auditoría y autorización correcta;
- pedir información → respuesta idempotente y continuación sobre la misma ejecución;
- resolver → cierre consistente;
- actor revocado/sin permiso → rechazo server-side;
- inquilino/ocupación equivocados → rechazo;
- RLS negativas;
- notificación final deduplicada;
- compatibilidad con obligaciones/recordatorios legacy existentes;
- ninguna mutación financiera sensible depende solo de UI.

**Entrega obligatoria de Codex:**
- un solo PR WF-06 salvo autorización explícita;
- migraciones aditivas/versionadas; no modificar migraciones aplicadas;
- regresiones nuevas para reglas críticas y bugs;
- Governance Guard, PWA Smoke y Schema Guard verdes sobre el mismo HEAD;
- actualizar este handoff con rama, PR, HEAD, migraciones, pruebas, riesgos y pendientes;
- detenerse en `READY_FOR_CHATGPT_REVIEW`;
- no fusionar, no desplegar manualmente y no activar WF-07.

---

### BLOQUE WF-07 — Reclamo de daños + Fianza
**Estado:** PLANNED

Integrar:
- reclamación por daños;
- fianza.

Debe conservar:
- evidencia;
- revisión;
- solicitar información;
- resolución;
- recepción;
- devolución;
- retención parcial;
- retención total.

No convertir el motor en contabilidad; reutilizar relaciones y evidencia existentes.

---

### BLOQUE WF-08 — Presets/plantillas de dominio en Creador
**Estado:** PLANNED

Solo después de que los dominios anteriores funcionen.

Objetivo:
- que elegir Limpieza / Inspección / Mantenimiento / Check-in / Check-out configure valores iniciales útiles;
- seguir permitiendo personalización;
- preset no es un segundo motor;
- nunca ocultar una limitación backend con UI.

---

### BLOQUE WF-09 — Cierre de migración legacy
**Estado:** PLANNED

Objetivo:
- decidir qué accesos legacy pueden retirarse;
- mantener histórico;
- no borrar estructuras si aún existen referencias;
- documentar compatibilidad;
- actualizar `WORKFLOW_STATUS.md` con evidencia final.

Criterio:
ningún acceso legacy se retira hasta que exista equivalencia funcional + seguridad + E2E verificada por ChatGPT.

---

## 7. Regla para bugs encontrados durante estos bloques

Si Codex descubre un bug que impide el bloque:
- si es pequeño y directamente relacionado: corregir dentro del bloque con regresión;
- si es grande/no relacionado: documentar como bloqueo y parar;
- nunca ampliar silenciosamente el alcance.

Formato:
`BLOCKER-<bloque>-NN`
- síntoma;
- causa;
- impacto;
- archivos;
- propuesta;
- decisión necesaria.

---

## 8. Qué significa “terminado”

Un bloque NO está terminado porque:
- compila;
- Codex dice que funciona;
- el PR está abierto;
- un smoke aislado está verde.

Está terminado únicamente cuando ChatGPT verifica, según aplique:
1. diff contra main real;
2. checks del mismo HEAD;
3. comentarios/reviews pendientes;
4. migraciones remotas;
5. funciones Edge desplegadas;
6. RLS/privilegios;
7. Pages;
8. pruebas de producción no destructivas;
9. E2E humano cuando sea necesario.

Solo entonces ChatGPT cambia el bloque a `VERIFIED`.

---

## 9. Formato de entrega obligatorio de Codex

Al terminar el bloque activo, Codex debe escribir aquí:

```
Estado: READY_FOR_CHATGPT_REVIEW
Rama:
PR:
HEAD de rama:
Main observado al comenzar:
Main observado al terminar:
Cambios:
Migraciones:
Edge Functions:
Tests locales:
Checks GitHub:
Riesgos:
Pendientes:
Prueba humana sugerida:
Siguiente acción exacta para ChatGPT:
```

Y detenerse.

---

## 10. Regla de continuidad entre bloques

Después de que ChatGPT marque un bloque `VERIFIED`:
- ChatGPT cambia exactamente un siguiente bloque a ACTIVO;
- Codex crea rama nueva desde el main actualizado;
- no arrastra ramas anteriores;
- no reutiliza un HEAD viejo;
- vuelve a inspeccionar producción/código afectado.

La finalidad es que **el repositorio sea la memoria compartida** y Codex pueda ser sustituido, reiniciado o perder contexto sin perder la dirección del proyecto.
