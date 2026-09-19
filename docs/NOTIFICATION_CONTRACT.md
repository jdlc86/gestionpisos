# Contrato de notificaciones

## Canales

- Campanita interna: histórico persistente.
- Push PWA: avisos aunque la app no esté abierta, sujeto a permisos del dispositivo.
- Email: eventos relevantes y comunicaciones configuradas.

No todos los eventos deben usar todos los canales.

## Broadcast

- Emisor visible: empresa gestora.
- Autor interno: usuario que crea/programa.
- Alcance: toda empresa, piso, varios pisos o segmentos/roles autorizados.
- Estados: borrador, programado, enviado, cancelado.
- Antes de envío masivo debe mostrarse alcance y número de destinatarios.
- Debe quedar auditoría de creación, programación, cancelación y envío.

## Automatizaciones

Ejemplos:
- recordatorios de pago;
- reclamaciones;
- vencimientos;
- tareas e inspecciones;
- escalados por SLA;
- limpiezas fallidas;
- contratos próximos a vencer.

Las reglas deben evitar duplicados y permitir trazabilidad.


## Flujos de Trabajo

Los workflows reutilizan `notifications_v2`; no crean otra tabla de notificaciones.

La receta publicada conserva dos flags:

- `notifications.onCreate=true`: crea una notificación interna para la persona asignada cuando nace la ejecución/tarea.
- `notifications.onClose=true`: crea una notificación interna para creador y asignado cuando la ejecución termina en `completed` o `rejected`. Si ambos son la misma persona, solo existe una notificación.

Tipos de evento:

- `workflow_task_created`
- `workflow_completed`
- `workflow_rejected`

La correlación se guarda en `notifications_v2.source_kind/source_id/event_key` y tiene unicidad por destinatario, de modo que reintentos idempotentes no duplican avisos.

En esta primera integración:

- `channel_in_app=true`;
- `channel_email=false`.

Email no se activa implícitamente: debe existir una opción explícita de autoría/canal antes de enviar correos por workflows.


## Campanita de Inicio

La superficie inicial de notificaciones vive en el encabezado de **Inicio**:

- la campana muestra contador solo cuando existen avisos no leídos;
- al abrirse usa un sheet compacto, no una pantalla administrativa;
- consulta las 30 notificaciones in-app recientes visibles por RLS;
- permite marcar una o todas como leídas mediante `mark_notification_read`;
- `workflow_task_created` navega a Tareas;
- `workflow_completed` y `workflow_rejected` navegan a Historial;
- no expone UUID, rutas de Storage ni claves de correlación en la interfaz.

El Centro Operativo sigue siendo el espacio para broadcasts/programación; la campanita es la bandeja personal del usuario.
