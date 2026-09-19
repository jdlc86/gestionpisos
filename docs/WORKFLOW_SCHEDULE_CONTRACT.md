# Contrato — Fecha concreta automática

## Propósito

**Fecha concreta** es el primer disparador automático del motor transversal de Flujos de Trabajo.

Cadena:

`Definición → Versión → Aplicación programada → Scheduler → Ejecución → Tarea`

No crea un motor paralelo. La ejecución automática reutiliza el mismo núcleo, snapshot, evidencias, tarea, historial y notificaciones que una ejecución manual.

## 1. Autoría temporal exacta

El control visual sigue siendo un `datetime-local`, pero ese valor no contiene zona horaria. Por ello una receta `triggerType=scheduled_once` conserva tres valores inseparables:

- `scheduledAt`: fecha/hora local mostrada al autor, formato `YYYY-MM-DDTHH:mm`;
- `scheduledTimezone`: zona IANA detectada por el navegador, por ejemplo `Europe/Madrid`;
- `scheduledAtUtc`: instante UTC exacto elegido por el navegador.

El backend verifica que al representar `scheduledAtUtc` dentro de `scheduledTimezone` se obtiene exactamente `scheduledAt`.

Esto evita:

- tratar `datetime-local` como UTC;
- desplazar la ejecución según el servidor;
- decidir silenciosamente una hora en cambios DST;
- reinterpretar una versión histórica desde otro dispositivo.

La fecha debe seguir estando en el futuro en el momento de Programar.

## 2. Estado operativo de programación

La programación vive en:

`workflow_application_schedules_v2`

Existe como máximo una programación operativa por aplicación/version y conserva:

- definición/version/aplicación/organización;
- tipo `scheduled_once`;
- zona horaria;
- `next_run_at` en `timestamptz`;
- asignado fijado, solo cuando la regla es manual;
- estado `active/completed/blocked/cancelled`;
- último intento, ejecución creada y código de error;
- autor que programó.

La tabla tiene RLS de lectura y no es escribible directamente por clientes autenticados.

## 3. Asignación

### Manual

En Fecha concreta, **Se decide al iniciar** cambia de significado operativo: la persona se elige al pulsar **Programar**.

La persona seleccionada se valida al programar y se vuelve a validar cuando llega la hora. Si pierde elegibilidad antes del disparo, la programación queda bloqueada y no crea una tarea parcial.

### Responsable operativo

No se congela una persona al programar.

El responsable se resuelve en el instante real de ejecución, por lo que un cambio de responsable entre Programar y la fecha prevista se respeta automáticamente.

No es obligatorio que exista responsable en el momento de programar. Sí debe existir uno elegible al dispararse.

### Otras reglas

`fixed_person`, `role` y `active_occupants_rotation` no se automatizan todavía porque su ejecución genérica aún no está soportada por el motor actual.

## 4. Programar no es Ejecutar

Una receta `scheduled_once`:

- se finaliza con **Programar**;
- no crea ejecución ni tarea en ese momento;
- no ofrece **Ejecutar** en Mis Flujos;
- no entra en una ejecución masiva manual;
- el backend rechaza también una creación `manual_now` accidental.

Una futura capacidad explícita de “Ejecutar ahora y cancelar programación” tendría que diseñarse como operación propia; no se infiere.

## 5. Scheduler

`pg_cron` ejecuta cada minuto:

`private.process_due_workflow_schedules_v1(now())`

El procesador:

- usa `FOR UPDATE ... SKIP LOCKED`;
- toma solo programaciones `active` y vencidas;
- exige aplicación configurada y definición publicada;
- genera una clave idempotente a partir de aplicación + instante programado;
- reutiliza `private.workflow_execute_application_internal_v1`;
- materializa exactamente una `tenant_tasks_v2`;
- marca la programación `completed`.

Una segunda pasada no duplica ejecución ni tarea.

## 6. Fallos

Si al llegar la fecha no se puede ejecutar —por ejemplo, responsable inexistente o destino ya no válido—:

- no queda una ejecución parcial;
- la programación pasa a `blocked`;
- se conserva solo `SQLSTATE` como código técnico;
- el texto completo de la excepción no se persiste;
- el creador recibe `workflow_schedule_blocked` en `notifications_v2`;
- la campanita lleva a Mis Flujos.

El `event_key` de la notificación incluye el instante programado para que una reprogramación posterior pueda generar su propio aviso.

No existe reintento automático infinito: un bloqueo requiere una nueva decisión/configuración.

## 7. Archivo y edición

Archivar la aplicación cancela una programación `active` o `blocked`.

Editar un flujo sin historial vuelve a configurar su programación dentro de la misma operación transaccional.

Una revisión de un flujo con historial crea una nueva versión/aplicación y su propia programación, sin alterar ejecuciones anteriores.

## 8. Recurrencias

Este contrato no habilita todavía `triggerType=recurring`.

La frecuencia ya puede definirse en el Creador, pero falta una **primera fecha/hora explícita** que actúe como ancla. No se usará la hora de publicación ni otra hora implícita.

Recurrente reutilizará esta misma infraestructura cuando esa semántica esté definida.
