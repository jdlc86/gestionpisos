# Contrato — Incidencia / Mantenimiento / Inspección sobre Flujos de Trabajo

## Propósito

WF-05 integra el expediente de incidencia con el motor transversal sin crear otra autoridad operativa.

Cadena canónica:

`Incidencia → outbox común → aplicación Mantenimiento → ejecución → tenant_tasks_v2 → acciones/evidencias → resolución → outbox común → aplicación Inspección opcional`

`incidents_v2` conserva el expediente de negocio. `workflow_executions_v2` conserva la ejecución congelada y `tenant_tasks_v2` sigue siendo la única tarjeta operativa transversal.

## 1. Límites de las autoridades

- `incidents_v2`: identidad, clasificación, destino y estado de la incidencia.
- `workflow_executions_v2`: receta, asignación, destino, estado de ejecución y sujeto de dominio congelados.
- `tenant_tasks_v2`: tarjeta sobre la que actúa la persona asignada.
- `workflow_execution_events_v2` y `tenant_task_history_v2`: historial funcional de ejecución y tarea.
- `audit_log_v2`: auditoría de seguridad/administración.
- `notifications_v2`: avisos persistentes.
- Foto, Checklist y Documento: subsistemas genéricos existentes; no se copian a tablas de incidencias.

Una incidencia no crea una segunda tarea y una tarea no sustituye el expediente. El vínculo debe ser explícito y verificable en servidor.

## 2. Clasificación

El expediente distingue:

- `incident`: reporte general;
- `maintenance`: reporte que requiere gestión de mantenimiento.

Mantenimiento es una categoría transversal, no una tabla ni un motor propios. La receta que gestiona el expediente usa `flowType=maintenance`.

Las inspecciones posteriores usan `flowType=inspection`. No se crea un expediente paralelo de inspección en WF-05: su evidencia e histórico viven en la ejecución común.

Los registros legacy sin clasificación explícita conservan semántica `incident` y no se reescriben.

## 3. Apertura idempotente

La apertura se realiza mediante una RPC server-side.

La RPC:

- deriva organización y actor desde relaciones autoritativas;
- valida piso y habitación;
- permite a un inquilino únicamente su ocupación activa y destino vigente;
- permite a personal interno únicamente un piso sobre el que tenga escritura operativa vigente;
- valida categoría, descripción y prioridad;
- crea una sola incidencia por `actor + request_key`;
- detecta el uso de la misma clave con un payload diferente;
- audita la creación;
- publica exactamente un `incident.created` en `workflow_event_outbox_v2`.

La transacción de apertura no crea una ejecución ni una tarea directamente. El dispatcher WF-02 las materializa después.

## 4. Aplicación de gestión

Una aplicación que consuma `incident.created` para gestionar el expediente debe cumplir:

- `flowType=maintenance`;
- `triggerType=event`;
- `eventType=incident.created`;
- destino piso o habitación;
- asignación server-side a responsable, persona fija o rol interno autorizado;
- `steps.accept=true`;
- `closeType=domain_adapter`.

Foto, Checklist y Documento son opcionales y se configuran con los contratos existentes. Si están presentes, `resolve` exige que todos los requisitos obligatorios estén completos.

El dispatcher vincula la misma incidencia a la ejecución. Un reintento del evento recupera la misma ejecución y la misma tarjeta.

Para `incident.created` existe **un único gestor Mantenimiento canónico por destino efectivo**. Dos aplicaciones configuradas se consideran solapadas cuando cubren el mismo piso y al menos una tiene alcance de piso, o cuando ambas tienen alcance de la misma habitación. La configuración solapada se rechaza transaccionalmente antes del despacho. Esto evita dos tarjetas gestoras para el mismo expediente. Esta restricción no aplica a `incident.resolved`: las inspecciones posteriores conservan fan-out por aplicación compatible.

## 5. Estados y acciones

El recorrido mínimo es:

`reported → in_progress → waiting_info → in_progress → resolved`

También puede terminar en `rejected` con motivo.

Correspondencia tarea/ejecución:

| Acción | Incidencia | Tarea + ejecución | Nota |
| --- | --- | --- | --- |
| `accept` | `in_progress` | `active` | asigna la gestión al actor |
| `request_info` | `waiting_info` | `waiting_info` | no terminal; exige nota |
| `continue` | `in_progress` | `active` | misma ejecución; exige información posterior a la solicitud |
| `resolve` | `resolved` | `completed` | terminal; exige evidencias configuradas completas |
| `reject` | `rejected` | `rejected` | terminal; exige motivo |

Cada acción:

- bloquea incidencia, tarea y ejecución;
- revalida actor, asignación, organización, piso y habitación;
- revalida permiso de escritura vigente;
- revalida también la **regla de asignación congelada** de la ejecución: un antiguo responsable no sigue autorizado solo por conservar acceso secundario, una persona fija debe seguir siendo la misma y una asignación por rol exige conservar ese rol;
- exige MFA `aal2` a ROOT/ADMIN cuando actúan en una operación sensible;
- es idempotente por `execution_id + request_key`;
- actualiza expediente, tarea y ejecución en la misma transacción;
- registra histórico, evento de ejecución y auditoría.

Solicitar información nunca crea otra ejecución ni marca cierre.

## 6. Respuesta de información

El creador autorizado de la incidencia puede aportar información mientras el expediente está `waiting_info`.

La respuesta:

- puede provenir del creador autorizado tanto si el expediente fue abierto por un inquilino como por personal interno;
- la solicitud usa visibilidad `tenant` para expedientes ligados a ocupación y `internal` para expedientes abiertos por personal interno;
- usa una RPC idempotente;
- conserva autor, visibilidad y texto en `incident_updates_v2`;
- no cambia por sí sola la autoridad operativa ni crea una tarea;
- queda auditada;
- permite que el asignado ejecute `continue` sobre la misma ejecución.

`continue` se rechaza si no existe una respuesta posterior a la última solicitud de información.

## 7. Evidencias reutilizadas

Una aplicación Mantenimiento o Inspección usa sin variaciones conceptuales:

- `workflow_execution_photo_resources_v2` y la cámara existente;
- `workflow_executions_v2.checklist_state`;
- `workflow_execution_documents_v2` y su bucket privado.

Las tablas `incident_evidence_v2` se preservan como histórico legacy. WF-05 no duplica en ellas evidencias genéricas nuevas ni reinterpreta rutas existentes.

Para Mantenimiento con `closeType=domain_adapter`, completar evidencias mantiene la ejecución activa hasta `resolve`.

Para Inspección, los cierres `auto` y `human_review` conservan las reglas actuales: el último requisito completa o envía a revisión; la revisión fotográfica se hace en la superficie protegida existente.

## 8. Evento posterior e Inspección

Resolver una incidencia publica idempotentemente `incident.resolved` en el mismo outbox WF-02.

Una aplicación posterior compatible debe cumplir:

- `flowType=inspection`;
- `triggerType=event`;
- `eventType=incident.resolved`;
- mismo destino de piso/habitación;
- asignación interna server-side;
- al menos uno de Foto, Checklist o Documento;
- cierre `auto` o `human_review`.

El evento puede no tener ninguna aplicación suscrita. Si existe una, cada aplicación compatible recibe exactamente una ejecución downstream. No hay listeners ni cron específicos de incidencias.

## 9. Notificaciones

El cierre de tarea/ejecución reutiliza el trigger común de `notifications_v2` y los flags publicados `notifications.onClose`.

`request_info` genera un aviso in-app idempotente al creador autorizado cuando existe una identidad receptora. La respuesta de información no crea canales nuevos ni activa email implícitamente.

## 10. RLS y acceso

RLS permanece habilitada en las tres tablas legacy.

- ROOT activo puede leer con su contrato global.
- ADMIN activo puede leer dentro de su organización.
- EMPLOYEE solo lee pisos con asociación vigente.
- TENANT solo lee la incidencia de su ocupación activa y las actualizaciones con visibilidad `tenant`.
- OWNER solo lee incidencias de sus pisos y contenido con visibilidad `owner`.
- `anon` no accede.

No hay INSERT/UPDATE/DELETE directo del cliente para operaciones de WF-05. Las mutaciones pasan por RPCs con permisos mínimos y `EXECUTE` explícito.

## 11. Compatibilidad legacy

- Los registros anteriores permanecen consultables sin ejecución asociada.
- El tipo legacy `tenant_tasks_v2.task_type=incident` y sus plantillas no se eliminan en WF-05.
- Una nueva incidencia WF-05 no crea además una tarea legacy `incident`.
- No se borran ni reescriben estados, updates o evidencias históricos.
- La retirada del camino legacy pertenece a WF-09.

## 12. Criterio de cierre automático

Las regresiones mínimas deben demostrar:

- apertura válida → un expediente, un evento, una ejecución y una tarjeta;
- retry → cero duplicados;
- acciones coherentes e idempotentes;
- `request_info` no terminal y auditable;
- respuesta + `continue` sobre la misma ejecución;
- `resolve` sincroniza las cuatro fuentes y notifica según receta;
- actor o destino revocado/fuera de alcance → rechazo server-side;
- cambio de responsable/persona fija/rol manteniendo acceso al piso → el antiguo asignado deja de ser actor válido;
- segundo gestor Mantenimiento solapado para `incident.created` → rechazo de configuración;
- Foto/Checklist/Documento siguen usando las tablas/RPCs comunes;
- `incident.resolved` → una ejecución downstream por aplicación;
- RLS negativas y compatibilidad legacy.

El E2E humano integral se ejecutará en la batería final conjunta autorizada. Su aplazamiento no relaja ninguna regresión automática, Governance Guard, PWA Smoke o Schema Guard.
