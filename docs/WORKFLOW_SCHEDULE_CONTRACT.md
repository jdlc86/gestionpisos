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
- reinterpretar una versión histórica desde otro dispositivo.

Si una hora local aparece **dos veces** por el cambio horario de otoño, el Creador y el backend la rechazan como ambigua y exigen elegir otra hora. El sistema no decide silenciosamente cuál de los dos instantes usar.

La fecha debe seguir estando en el futuro en el momento de Programar.

## 2. Estado operativo de programación

La programación vive en:

`workflow_application_schedules_v2`

Existe como máximo una programación operativa por aplicación/version y conserva:

- definición/version/aplicación/organización;
- tipo `scheduled_once` o `recurring`;
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

### Persona fija, rol y rotación

`fixed_person` valida la relación vigente al programar y la revalida al dispararse. `role` y `active_occupants_rotation` se resuelven en el servidor en cada ocurrencia; no congelan una persona al programar. Si en ese momento no existe nadie elegible, la programación queda bloqueada sin crear una tarea parcial. Los cambios de ocupantes solo afectan ocurrencias futuras.

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

`triggerType=recurring` reutiliza la misma infraestructura de Fecha concreta.

### Primera ejecución

Toda recurrencia exige una primera fecha/hora explícita. El Creador conserva:

- `scheduledAt`: hora local mostrada al autor;
- `scheduledTimezone`: zona IANA;
- `scheduledAtUtc`: instante UTC exacto.

No se usa la hora de publicación ni otra ancla implícita.

### Frecuencias

Se soportan:

- semanal;
- cada 2 semanas;
- mensual;
- personalizada cada N días, semanas o meses, con N entre 1 y 365.

Cada ocurrencia se calcula **desde el ancla local original**, no desde la fecha ajustada anterior. Así una recurrencia mensual iniciada un día 31 puede ejecutar el último día de febrero y volver al día 31 en marzo, sin deriva permanente.

### Hora local y DST

La recurrencia conserva la hora local en su zona IANA a través de cambios de horario.

Si una ocurrencia futura cae en una hora local inexistente o ambigua por DST:

- la tarea de la ocurrencia actual, si ya fue creada válidamente, se conserva;
- el futuro de la programación pasa a `blocked`;
- se conserva solo el `SQLSTATE`;
- el creador recibe `workflow_schedule_blocked`;
- no se elige silenciosamente otro instante.

### Asignación

Para `manual`, la persona queda fijada al pulsar **Programar** y se revalida en cada ocurrencia.

Para `property_responsible`, no se congela una persona: el responsable operativo vigente se resuelve de nuevo en **cada ejecución recurrente**. Un cambio de responsable entre dos ocurrencias se respeta automáticamente.

### Catch-up

Si el scheduler estuvo detenido y ya pasaron varias ocurrencias:

- una pasada crea como máximo una obligación vencida;
- las ocurrencias intermedias que ya quedaron en el pasado no generan una tormenta de tareas;
- el número omitido queda auditado como `workflow_recurring_occurrences_skipped`;
- `next_run_at` avanza a la primera ocurrencia futura.

Esta política evita inundar a usuarios con tareas atrasadas sin ocultar que hubo ocurrencias omitidas.

### Estado operativo

La misma tabla `workflow_application_schedules_v2` conserva además:

- `next_occurrence_index`;
- `execution_count`;
- `last_scheduled_for`.

Después de cada ejecución válida, la programación sigue `active` con su próxima fecha. Archivar o sustituir una aplicación cancela su programación anterior, evitando dos recurrencias simultáneas de versiones distintas.

Recurrente no ofrece **Ejecutar** manual ni entra en ejecución masiva; usa `trigger_kind=recurring` y el mismo núcleo privado de ejecución/materialización de tareas.
