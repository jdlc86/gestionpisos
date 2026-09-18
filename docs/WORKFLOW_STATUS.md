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

`sessionStorage` sigue usándose únicamente como recuperación local de cambios mientras se edita. Ya no es la única persistencia.

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

Los borradores configurados pueden publicarse mediante RPC protegido. Una definición publicada ofrece acceso a **Aplicaciones** y una aplicación configurada puede crear una ejecución manual pendiente mediante **Ejecutar ahora**. Pausar, tareas materializadas y recurrencias automáticas siguen pendientes.

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

`configured` no activa recurrencias. Desde la tarjeta puede crear una ejecución explícita `manual_now`; esa ejecución nace `pending` y todavía no materializa una tarea.

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

Cuando exista una ejecución real, el motor deberá congelar la versión exacta del patrón/recurso utilizado.

## 7. Tareas

No se ha creado `workflow_tasks`.

`tenant_tasks_v2` se reutiliza como núcleo de tareas mediante una generalización aditiva:

- tareas legacy conservan `tenant_id` obligatorio;
- tareas de workflow usan `task_type='workflow'` y `source_kind='workflow_execution'`;
- `tenant_id` puede ser NULL únicamente bajo esa forma validada;
- una ejecución produce como máximo una tarea por índice único;
- el asignado puede leer su tarea por RLS;
- la pantalla `workflow-tasks.html` lista el trabajo visible.

`tenant_task_actions_v2` y `tenant_task_history_v2` se conservan. Las acciones de workflow todavía no se habilitan hasta sincronizar atómicamente el estado de tarea y ejecución.

## 8. Limpieza — transición

Se conservan:

- `cleaning_plans_v2`;
- `cleaning_tasks_v2`;
- swaps;
- deuda no monetaria;
- auditoría por foto;
- solicitudes fotográficas;
- `cleaning.html`.

Limpieza será el primer adaptador de dominio cuando el motor pueda publicar y ejecutar una definición real.

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
| Banco Fotográfico | Operativo/reutilizado | Infraestructura existente |
| Versiones publicadas | Implementado | Publicación RPC inmutable e idempotente |
| Tareas | Materialización inicial implementada | `tenant_tasks_v2` generalizada sin fabricar inquilino; acciones aún bloqueadas |
| Historial | Inicial | `workflow_execution_events_v2` registra creación; ciclo completo pendiente |
| Ejecución genérica | Implementada en fase inicial | `manual_now`, idempotente, estado `pending` |
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

## 12. Próximo incremento técnico

El siguiente incremento debe ser **sincronización atómica de acciones tarea ↔ ejecución**.

Orden recomendado:

1. derivar las acciones permitidas desde la versión publicada;
2. mover tarea y ejecución en una única transacción;
3. impedir completar si quedan pasos/recursos obligatorios;
4. incorporar binding de Banco Fotográfico cuando `steps.photo=true`;
5. registrar eventos de ejecución e histórico de tarea coherentes;
6. probar reintentos sin duplicar acciones, evidencias ni notificaciones.

La recurrencia automática se mantiene posterior a un recorrido manual extremo a extremo.

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

## 14. Criterio para declarar el primer flujo real

Un flujo será operativo solo cuando exista evidencia de que:

- definición persistida;
- versión publicada inmutable;
- RLS bloquea accesos cruzados;
- activación crea una única ejecución;
- asignación se resuelve server-side;
- tarea trazada a ejecución;
- recursos congelados/versionados;
- cierre con histórico reproducible;
- reintentos no duplican trabajo.

Hasta entonces, las definiciones visibles en **Mis Flujos** siguen siendo **borradores de autoría**, no procesos operativos activos.
