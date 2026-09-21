# WF-07 · Reclamación por daños + Fianza

## Objetivo

WF-07 integra la recepción/revisión de fianza y la reclamación por daños sobre el motor transversal existente. No crea un ledger, una contabilidad paralela ni una segunda tabla de tareas.

La autoridad operativa queda repartida así:

- `security_deposits_v2`: expediente operativo único de fianza por ocupación;
- `claims_v2`: expediente de reclamación por daños;
- `workflow_executions_v2`: ejecución transversal;
- `tenant_tasks_v2`: única tarjeta operativa;
- Foto / Checklist / Documento: evidencia transversal existente;
- `workflow_event_outbox_v2`: eventos de Baja y de reclamación por daños.

## Fianza

Existe una única fianza por `occupancy_id`.

Estados de dominio:

`pending → received → under_review ↔ waiting_info → refunded | partially_held | held`

Reglas:

- Recepción usa `flowType=deposit_receipt`, ámbito `occupancy`, disparo manual y `domain_adapter`.
- Registrar recepción cierra esa ejecución. La fianza permanece como expediente para la futura salida.
- Revisión usa `flowType=deposit_review` y se activa por `occupancy.offboarded`.
- La revisión exige al menos una evidencia Foto, Checklist o Documento.
- La Baja real mantiene revocado el acceso del antiguo inquilino; WF-07 nunca reactiva Auth ni roles.
- Si la Baja no tiene una fianza recibida revisable, el despacho se clasifica como `workflow_domain_lifecycle_mismatch` terminal para no bloquear el outbox.
- Solicitar información deja la revisión en `waiting_info`; como el antiguo inquilino no tiene acceso, la respuesta externa se registra por la gestoría mediante nota auditada al continuar.
- Una fianza no se resuelve mientras exista una reclamación por daños no resuelta.
- Devolución total exige daños resueltos por 0 €.
- Retención parcial debe ser mayor que 0, menor que el total de fianza y no superior a la suma de daños finalmente reconocidos.
- Retención total exige daños resueltos por al menos el importe completo de la fianza.
- Siempre se cumple `held_amount_cents + refunded_amount_cents <= amount_cents`.

## Reclamación por daños

Daños reutiliza `claims_v2` con `claim_type=damage`.

Una reclamación queda vinculada a:

- organización;
- piso;
- ocupación histórica;
- usuario tenant histórico;
- fianza exacta;
- importe reclamado;
- moneda.

`damage_claim.created` se publica por el outbox común y solo se acepta cuando la fianza está en revisión.

Estados del expediente:

`draft → sent ↔ waiting_info → resolved`

Reglas:

- solo un flujo gestor compatible puede cubrir un destino efectivo;
- una fianza puede originar como máximo una reclamación de daños; el invariante está respaldado por índice único parcial y la acción `open_damage_claim` deja de estar activa tras crearla;
- la tarjeta pertenece operativamente al gestor interno asignado;
- el antiguo inquilino no obtiene lectura ni acciones después de la Baja;
- “Notificar reclamación” exige completar la evidencia configurada;
- “Solicitar información” envía comunicación por email y deja la misma ejecución en espera;
- “Registrar aceptación” / “Registrar disputa” son registros internos de una respuesta recibida por un canal externo y requieren nota;
- Resolver exige decisión registrada, evidencia completa e importe reconocido entre 0 y el importe reclamado;
- el importe reconocido alimenta la justificación de la retención de fianza.

## Actor y seguridad

Las mutaciones de WF-07 son server-side e idempotentes.

El actor interno debe:

- ser el `assigned_user_id` de la ejecución;
- conservar perfil/rol vigente;
- conservar escritura vigente sobre el piso;
- seguir cumpliendo la regla congelada de asignación `property_responsible / fixed_person / role`.

ADMIN/ROOT requieren AAL2 mediante el mismo guard privilegiado ya usado por WF-06.

Las tablas de fianza no conceden escritura directa a `authenticated`. `claims_v2` conserva lectura autorizada bajo RLS, pero `authenticated` no recibe INSERT/UPDATE/DELETE directo para estas mutaciones.

WF-07 envuelve `workflow_execution_actor_current_v1()` para añadir la validación estricta de fianza/daños. Como PostgreSQL enlaza las expresiones de POLICY al OID de la función, las policies workflow que ya dependían de ese gate se recrean sin cambiar sus predicados ni ampliar permisos, de modo que queden enlazadas al wrapper WF-07 actual.

## Evidencia

WF-07 no crea almacenamiento nuevo.

Para Foto, Checklist y Documento se reutilizan los recursos ya materializados por la aplicación/ejecución. Un recurso obligatorio solo se considera completo cuando su estado transversal está completado/submitted.

Completar evidencia puede mover una ejecución `pending → active`; por ello `start_review` y `notify` son válidos tanto desde `pending` como desde `active` cuando corresponda.

## Notificaciones

Como la Baja revoca acceso, las comunicaciones posteriores a la salida no dependen de la PWA del tenant:

- recepción de fianza: notificación normal;
- solicitud de información de fianza: email;
- notificación de daños: email;
- solicitud de información de daños: email;
- resolución de daños: email;
- devolución/retención de fianza: email.

Las claves de evento deduplican reintentos.

`notifications_v2.channel_email=true` se despacha de forma asíncrona mediante el trigger `notification_email_dispatch_v1` hacia la Edge Function `notification-email`. El puente usa `pg_net`, secreto interno en Vault y un recibo idempotente `notification_email_deliveries_v1`.

La entrega admite reintentos controlados sin convertir la notificación en una segunda cola de negocio:
- primer claim → `sending`;
- un `failed` puede reclamarse tras 2 minutos;
- un `sending` huérfano puede reclamarse tras 15 minutos;
- máximo 5 claims por notificación;
- el cron `gestionpisos-notification-email-retry` reencola candidatos cada 5 minutos;
- la llamada a Resend usa `Idempotency-Key=allaiso-notification/<notification_id>`, de modo que un timeout posterior al envío no debe producir un segundo mensaje del proveedor.

La Edge Function resuelve el email directamente desde la identidad Auth con service role; no exige rol tenant vigente. Esto permite comunicar una fianza/daño después de la Baja sin restaurar acceso a la PWA. Reutiliza los secretos existentes `RESEND_API_KEY` y `AUTH_EMAIL_FROM`.

Orden obligatorio de despliegue: primero todas las migraciones de WF-07, incluidas `20260921164500_notification_email_dispatch.sql`, `20260921181500_notification_email_retry.sql` y `20260921181600_notification_email_retry_cron.sql`; confirmar su aplicación remota; solo entonces desplegar `notification-email` con verificación JWT desactivada. La invocación DB no lleva JWT de usuario: el handler valida el secreto interno `X-Allaiso-Email-Secret` obtenido de Vault. El workflow manual `.github/workflows/notification-email-function.yml` preserva deliberadamente este orden.

## Idempotencia y auditoría

Cada mutación usa `request_key` y deja:

- `tenant_task_history_v2`;
- `workflow_execution_events_v2`;
- `audit_log_v2`.

Repetir una acción con la misma clave devuelve el resultado anterior sin duplicar estado ni histórico.

## E2E

La regresión automática `tests/workflow-wf07-domain-regression.sql` cubre:

- autoría válida/negativa;
- una fianza por ocupación;
- recepción;
- Baja real y revocación de acceso;
- evento terminal cuando no existe fianza;
- evidencia de revisión;
- solicitud/registro externo de información;
- apertura de daños y rechazo de una segunda reclamación para la misma fianza;
- enlace RLS de las policies al gate de actor WF-07 vigente;
- evidencia obligatoria;
- aceptación/disputa externa auditada;
- resolución;
- devolución total sin daños;
- retención parcial;
- retención total;
- idempotencia;
- notificaciones por email;
- claim idempotente, backoff, recuperación de `failed/sending` y cierre definitivo `sent` de la entrega.

El E2E humano permanece diferido a la batería final conjunta. WF-07 no se marca `VERIFIED` hasta completar esa batería.
