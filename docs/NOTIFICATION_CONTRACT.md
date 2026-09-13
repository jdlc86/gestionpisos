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
