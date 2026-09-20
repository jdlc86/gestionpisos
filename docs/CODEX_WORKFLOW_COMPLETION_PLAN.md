# CODEX WORKFLOW COMPLETION PLAN

Fecha de baseline: 2026-09-20  
Baseline verificado por ChatGPT: `main@825a70c224cc3dc3a05f97a7477134d582f1c478`

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

**Verificación independiente:** completada por ChatGPT antes del merge. WF-03 permanece en `PLANNED` hasta verificar despliegue post-merge.

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
**Estado:** PLANNED

Primer adaptador legacy obligatorio.

Objetivo:
- expresar Limpieza usando el motor transversal sin perder funcionalidades legacy.

Debe conservar:
- recurrencia;
- rotación real entre ocupantes;
- cambios entre compañeros;
- deuda no monetaria;
- fotoverificación/auditoría;
- revisión;
- informe único;
- histórico.

Estrategia:
- coexistencia primero;
- equivalencia E2E;
- no borrar tablas legacy;
- no migrar histórico antiguo sin evidencia;
- solo retirar entrada legacy cuando ChatGPT valide equivalencia.

---

### BLOQUE WF-04 — Check-in / Check-out + llaves
**Estado:** PLANNED

Unificar mediante el motor transversal:
- Recogida de llaves.
- Entrega de llaves.
- Entrada.
- Salida.

Debe aprovechar `event` del lifecycle de ocupación.

Reglas:
- destino exacto;
- asignado vigente;
- Baja corta acceso pero no destruye histórico;
- fechas y estados de ocupación son autoridad;
- acciones de llave no deben conceder acceso a vivienda por sí mismas;
- idempotencia ante reintentos del evento.

---

### BLOQUE WF-05 — Incidencia / Mantenimiento / Inspección
**Estado:** PLANNED

Objetivo:
- Gestión de incidencia sobre el motor común.
- Mantenimiento como categoría transversal.
- Inspección reutilizando Foto/Checklist/Documento.

Debe soportar:
- abrir;
- aceptar gestión;
- solicitar información;
- continuar;
- resolver;
- revisión/evidencia cuando proceda;
- evento posterior opcional, p.ej. inspección después de reparación.

No crear un motor de incidencias paralelo al workflow.

---

### BLOQUE WF-06 — Pago de alquiler + reclamación de alquiler
**Estado:** PLANNED

Integrar:
- Pago alquiler.
- Reclamación alquiler.

Debe conservar la semántica legacy:
- registrar pago;
- solicitar;
- aplazar;
- reclamar;
- aceptar/disputar;
- pedir información;
- resolver.

Toda transición con impacto sensible debe quedar auditada.

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
