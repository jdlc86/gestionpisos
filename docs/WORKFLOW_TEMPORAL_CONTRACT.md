# Contrato — Activación temporal de Flujos de Trabajo

## Propósito

Este contrato define la autoría necesaria para que una versión futura del scheduler pueda ejecutar flujos sin intervención humana.

Tipos temporales:

- `scheduled_once` — una ejecución en una fecha/hora concreta;
- `recurring` — ejecuciones periódicas a partir de una primera fecha/hora.

Este incremento **solo cierra la autoría temporal**. El scheduler automático se implementa en un incremento separado.

## 1. Fecha local + zona horaria

Los flujos temporales guardan dos valores explícitos:

- `scheduledAt`: fecha/hora local en formato `YYYY-MM-DDTHH:MM`;
- `scheduleTimeZone`: zona IANA, por ejemplo `Europe/Madrid`.

Para `scheduled_once`, `scheduledAt` significa **Fecha y hora**.

Para `recurring`, `scheduledAt` significa **Primera ejecución** y actúa como ancla de la recurrencia.

No se usa la hora de publicación, la hora del servidor ni una zona horaria implícita.

## 2. Zona horaria

El Creador detecta la zona del dispositivo con `Intl.DateTimeFormat().resolvedOptions().timeZone` y la guarda de forma explícita.

El backend valida el nombre contra `pg_timezone_names`.

La base de datos opera en UTC, pero el scheduler futuro calculará cada ocurrencia desde la hora local + zona IANA para conservar la hora de pared a través de cambios DST.

## 3. Asignación automática

Un disparador temporal no puede depender de una decisión humana en el instante de ejecución.

La primera versión automatizable exige:

`assignmentType = property_responsible`

y un ámbito que tenga piso:

- `property`;
- `room`;
- `occupancy`.

No se consideran completos para automatización:

- `manual`;
- `fixed_person`;
- `role`;
- `active_occupants_rotation`;
- ámbito `organization`.

Estas opciones podrán habilitarse cuando exista una resolución server-side completa y probada.

## 4. Recurrente

Además de primera ejecución + zona horaria + asignación automática, requiere una cadencia:

- `weekly`;
- `biweekly`;
- `monthly`;
- `custom`.

Para `custom`:

- `customEvery`: entero entre 1 y 365;
- `customUnit`: `day`, `week` o `month`.

## 5. Fecha concreta

`scheduled_once` no conserva campos de recurrencia. El sanitizador elimina:

- `recurrence`;
- `customEvery`;
- `customUnit`.

## 6. Compatibilidad histórica

Las versiones publicadas existentes **no se reescriben**.

Un flujo temporal antiguo que no tenga:

- `scheduledAt`;
- `scheduleTimeZone`;
- asignación server-resolved;

sigue siendo histórico/publicado, pero no puede considerarse listo para automatización.

Al editarlo, el Creador exige completar la nueva información antes de volver a publicar.

No se infiere una fecha desde `published_at` ni desde `created_at`.

## 7. Estado en Mis Flujos

Mientras falte información temporal, Mis Flujos muestra:

- `inicio pendiente` para recurrentes;
- `programación pendiente` para fecha concreta.

Esto no significa error ni altera el historial; indica que la versión no dispone todavía de un contrato temporal suficiente para el scheduler.

## 8. Siguiente incremento

El scheduler deberá:

- reutilizar el mismo núcleo de ejecución que `Ejecutar ahora`;
- usar claves idempotentes deterministas por ocurrencia;
- respetar la zona horaria guardada;
- congelar la versión exacta de la aplicación;
- resolver `property_responsible` server-side;
- no crear ráfagas de tareas por periodos históricos perdidos;
- registrar `trigger_kind` temporal y actor de sistema;
- no ejecutar configuraciones legacy incompletas.
