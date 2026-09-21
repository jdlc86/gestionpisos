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

Las tablas de fianza no conceden escritura directa a `authenticated`. La reclamación conserva las restricciones de `claims_v2`.

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

La Edge Function resuelve el email directamente desde la identidad Auth con service role; no exige rol tenant vigente. Esto permite comunicar una fianza/daño después de la Baja sin restaurar acceso a la PWA. Usa los secretos existentes `RESEND_API_KEY` y `AUTH_EMAIL_FROM`.

Orden obligatorio de despliegue: primero la migración de email y después la Edge Function. Nunca desplegar `notification-email` antes de que existan sus RPC/secretos de base de datos.

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
- apertura de daños;
- evidencia obligatoria;
- aceptación/disputa externa auditada;
- resolución;
- devolución total sin daños;
- retención parcial;
- retención total;
- idempotencia;
- notificaciones por email.

El E2E humano permanece diferido a la batería final conjunta. WF-07 no se marca `VERIFIED` hasta completar esa batería.
