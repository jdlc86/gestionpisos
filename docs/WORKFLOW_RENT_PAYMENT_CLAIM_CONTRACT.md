# WF-06 · Pago de alquiler y Reclamación de alquiler

## 1. Autoridades de datos

WF-06 no crea contabilidad ni una segunda cola de tareas.

- `payment_obligations_v2`: obligación económica.
- `claims_v2`: expediente de reclamación.
- `workflow_executions_v2`: ejecución transversal.
- `tenant_tasks_v2`: única tarjeta operativa.
- `workflow_event_outbox_v2`: publicación asíncrona de `rent_claim.created`.
- `notifications_v2`: avisos.
- `workflow_execution_events_v2` + `audit_log_v2`: historial funcional y auditoría.

La ejecución puede enlazar exactamente una `payment_obligation_id` y, en el flujo de reclamación, exactamente una `rent_claim_id`.

## 2. Pago de alquiler

`flowType=rent_payment` exige:

- `scopeType=occupancy`;
- `triggerType` manual, fecha concreta o recurrente;
- asignación interna por responsable, persona fija o rol ADMIN/EMPLOYEE;
- `closeType=domain_adapter`;
- concepto, importe en céntimos, moneda ISO de tres letras y días hasta vencimiento.

Cada ejecución crea exactamente una obligación ligada a la ocupación e inquilino actuales. Reintentar la misma ejecución no crea otra obligación.

Acciones:

- `request_payment`: abre la gestión y avisa al inquilino;
- `postpone`: mantiene la misma obligación y ejecución, cambia el vencimiento y exige motivo;
- `register_payment`: marca `paid` y cierra tarea + ejecución;
- `claim`: solo si el pago ya llegó a su fecha de vencimiento y existe un flujo `rent_claim` compatible con ejecutor resoluble.
- La fecha de vencimiento, la validación de aplazamiento y la elegibilidad para `claim` usan la misma fecha de negocio de `scheduledTimezone` (`Europe/Madrid` por defecto); nunca se compara un vencimiento local contra `current_date` UTC.

ADMIN/ROOT requieren AAL2 para mutaciones financieras. EMPLOYEE debe conservar escritura vigente sobre el piso.

## 3. Reclamación de alquiler

`claim` no crea una segunda deuda. Reutiliza la misma obligación, la marca `overdue`, crea un único expediente `claims_v2(claim_type='payment')` y publica `rent_claim.created`.

`flowType=rent_claim` exige:

- ámbito piso o habitación;
- `triggerType=event`;
- `eventType=rent_claim.created`;
- asignación interna;
- `closeType=domain_adapter`.

Solo puede existir un gestor de reclamación solapado por destino efectivo. Un flujo de piso solapa todas sus habitaciones; dos flujos de habitación solo solapan si apuntan a la misma habitación.

El dispatcher común WF-02 crea una ejecución y una única tarjeta `tenant_tasks_v2` enlazada al inquilino exacto.

## 4. Actor mixto en la misma tarjeta

La tarjeta conserva dos clases de acciones:

Gestoría/asignado:
- `notify`;
- `request_info`;
- `continue`;
- `resolve`.

Inquilino exacto:
- `accept`;
- `dispute`;
- `provide_info`.

El inquilino no puede ver la reclamación mientras el expediente sigue en `draft`. Tras `notify`, la policy permite leer la misma tarjeta solo al inquilino enlazado por `tenant_id/user_id` y con acceso de plataforma vigente.

Aceptar o disputar guarda `tenant_decision`, desactiva ambas decisiones y habilita `resolve`. Resolver antes de una decisión válida está prohibido server-side.

## 5. Información y continuidad

`request_info` mueve expediente, tarea y ejecución a `waiting_info`.

`provide_info` registra respuesta del inquilino sin cerrar la ejecución.

`continue` solo es válido si existe una respuesta posterior a la última solicitud de información; recupera la misma ejecución y vuelve a estado activo.

## 6. Seguridad e idempotencia

- no se conceden nuevos grants de escritura directa cliente sobre tablas financieras;
- todas las transiciones WF-06 son server-side;
- organización, piso, ocupación, inquilino, obligación, reclamación, evento y actor se revalidan;
- los request keys de Pago y Reclamación son únicos por ejecución;
- un reintento devuelve `applied_new=false`;
- RLS de Tareas usa la elegibilidad WF-06 para el gestor y una excepción exacta solo para el inquilino de la reclamación;
- ninguna acción tenant concede capacidad de gestión interna.

## 7. Pruebas automáticas

`tests/workflow-wf06-domain-regression.sql` cubre:

- autoría válida e inválida;
- una obligación por ejecución;
- pago solicitado, aplazado e idempotente;
- registro de pago;
- MFA de ADMIN;
- escalado a reclamación;
- outbox + dispatcher;
- tarjeta compartida bajo RLS;
- solicitud/respuesta de información;
- decisión del inquilino;
- activación tardía de Resolver;
- cierre consistente;
- notificaciones y auditoría.

La migración solo se considera apta para merge cuando Governance Guard, PWA Smoke y Schema Guard pasan sobre el mismo HEAD.
