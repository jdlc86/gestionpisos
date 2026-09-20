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
**Estado:** READY_FOR_CHATGPT_REVIEW  
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
- HEAD de rama: `644ca96bcce11d2ac59a1d9511eb9e273fd3e6e1`
- Main observado al comenzar: `825a70c224cc3dc3a05f97a7477134d582f1c478`
- Cambios realizados: documento maestro + regla de descubrimiento en AGENTS
- Pruebas: cambios documentales; Governance/PWA/Schema pendientes del PR
- Siguiente acción: ChatGPT verifica checks del mismo HEAD; si están verdes, marca WF-00 VERIFIED y activa WF-01

---

### BLOQUE WF-01 — Asignaciones genéricas faltantes
**Estado:** PLANNED

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
**Estado:** PLANNED

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
