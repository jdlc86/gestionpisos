# Auditoría de documentación y estado técnico — 18/09/2026

## 1. Alcance

Auditoría de consistencia entre:

- `main` del repositorio `jdlc86/gestionpisos`;
- contratos y documentación de `docs/`;
- esquema remoto de Supabase;
- migraciones registradas;
- Edge Functions desplegadas;
- invariantes de onboarding/identidad;
- estado real del motor de Flujos de Trabajo validado durante las pruebas E2E del 18/09/2026.

Referencia de código auditada antes de esta actualización documental:

`68d6a7a0b50181702518cda292cb8a40997054e0`

## 2. Resultado ejecutivo

No se detectó una deriva crítica activa entre emails de negocio/onboarding/identidad Auth en los tres grupos auditados.

Comprobación remota:

| Invariante | Resultado |
| --- | ---: |
| OWNER/TENANT pendientes con email de ficha distinto al onboarding | 0 |
| ADMIN/EMPLOYEE con `invitation_email` distinto de perfil/Auth | 0 |
| Operadores con `identity_email` distinto de Auth | 0 |

La regla global queda definida así:

> **Una invitación pertenece a una identidad concreta y a un email canónico concreto. Nunca se traslada silenciosamente a otro correo.**

## 3. Evidencia remota de Supabase

Migraciones recientes verificadas como registradas:

- `20260918193000_workflow_accept_reject_decision`;
- `20260918210000_external_onboarding_email_change_guard`;
- `20260918224500_invitation_email_invariant`.

Edge Functions relevantes verificadas como `ACTIVE`:

| Función | Versión auditada |
| --- | ---: |
| `send-external-welcome` | 6 |
| `revoke-external-welcome` | 1 |
| `create-organization-user` | 9 |
| `resend-staff-invitation` | 6 |
| `operator-mfa-recovery` | 2 |
| `manage-platform-operators` | 3 |

También se verificó la existencia remota de:

- `internal_staff_onboarding.invitation_email`;
- `platform_operators.identity_email`;
- trigger de coherencia del onboarding interno;
- trigger de protección del email de perfil de personal interno;
- trigger de identidad/email de operadores de plataforma.

## 4. Auditoría de onboarding e invitaciones

### OWNER / TENANT

Estado implementado:

- ficha de negocio separada de Auth;
- bienvenida explícita;
- onboarding pendiente ligado al email concreto;
- cambio de email con invitación pendiente requiere confirmación;
- la identidad Auth pendiente anterior se deshabilita;
- el onboarding anterior queda `revoked`;
- solo después se guarda el nuevo email;
- la nueva dirección requiere una nueva bienvenida;
- una cuenta ya activada no cambia de email desde la edición ordinaria.

Se corrigió además la sincronización visual de las tarjetas de Cartera para que el estado **Sin invitación / Enviar bienvenida** vuelva a aparecer después de editar/revocar.

### ADMIN / EMPLOYEE

Estado implementado:

- el onboarding conserva `invitation_email`;
- `invitation_email` debe coincidir con `profiles.email` y `auth.users.email`;
- el reenvío comprueba la coincidencia antes de generar un enlace;
- la activación comprueba `email_consistent`;
- un cambio directo de email con onboarding pendiente/activo queda bloqueado;
- cambiar de dirección requiere reprovisionar una identidad o un futuro flujo explícito de cambio de cuenta.

### Operadores de emergencia

Estado implementado:

- cada operador conserva `identity_email`;
- el valor queda ligado a la identidad Auth técnica;
- la consola rechaza al operador si Auth e `identity_email` difieren;
- la activación inicial valida esa coincidencia;
- ROOT puede desactivar una identidad con deriva para contener el incidente;
- reactivarla o modificar capacidades queda bloqueado hasta reprovisionar una identidad nueva.

## 5. Auditoría de Flujos de Trabajo

El estado documental anterior era parcialmente obsoleto porque todavía presentaba el “primer flujo real” como pendiente.

El 18/09/2026 quedaron validados dos recorridos E2E reales:

### Aceptar + Foto

Se comprobó:

- definición persistida;
- versión publicada;
- aplicación concreta;
- ejecución manual;
- tarea materializada;
- `accept` atómico;
- patrón/version/snapshot congelados;
- captura y objeto de Storage;
- recurso `submitted`;
- tarea + ejecución `completed`;
- histórico/eventos sin duplicados.

### Foto sin Aceptar

Se comprobó:

- `steps.accept=false`;
- Foto disponible directamente desde `pending`;
- ausencia total de acción/evento/histórico `accept`;
- una captura completa recurso + tarea + ejecución;
- un único run/ítem/objeto.

Conclusión: el recorrido manual con Foto ya es operativo dentro de su alcance implementado.

Siguen pendientes y no deben presentarse como completos:

- revisión humana genérica del workflow;
- checklist;
- documento;
- recurrencias automáticas;
- adaptador de Limpieza;
- historial transversal completo de todos los tipos de paso.

## 6. Desajustes documentales detectados

### Corregidos en esta actualización

1. `README.md` todavía describía el proyecto como **bootstrap inicial**.
2. No existía un índice documental general.
3. `SECURITY_CONTRACT.md` no recogía todavía el invariante global de email/identidad.
4. `PERMISSIONS_CONTRACT.md` no diferenciaba invitar de trasladar una identidad a otro email.
5. `DATA_CONTRACT.md` no documentaba los emails canónicos de onboarding/operador.
6. `TESTING_STRATEGY.md` no incluía negativas específicas de deriva de email.
7. `RELEASE_CONTRACT.md` no exigía explícitamente verificar migración/Edge Functions remotas después de un cambio R3/R4.
8. `WORKFLOW_STATUS.md` seguía indicando que el primer flujo real estaba pendiente.

## 7. Riesgos y límites abiertos

Estos puntos siguen abiertos y deben mantenerse explícitos:

- **Cambio de email de una cuenta ya activa:** no existe todavía un flujo universal de migración de identidad. La edición ordinaria debe permanecer bloqueada.
- **Reasignación automática tras Rechazar una tarea de workflow:** no está implementada como asistente genérico.
- **Notificación operativa específica tras rechazo de workflow:** pendiente.
- **Checklist / documento / revisión humana / recurrencia:** pendientes en el motor transversal.
- **Adaptador de Limpieza:** pendiente; el legacy sigue protegido.
- Un check verde de PR no sustituye a verificar que migraciones y Edge Functions hayan llegado al proyecto remoto.

## 8. Reglas documentales de no regresión

A partir de esta auditoría:

- usar `DOCUMENTATION_INDEX.md` como entrada general;
- un cambio R3/R4 debe actualizar contrato + prueba + documentación de estado cuando corresponda;
- una capacidad solo se marca **operativa** cuando existe implementación y evidencia suficiente;
- un informe fechado no se reescribe para ocultar el estado histórico;
- los contratos son autoritativos y prevalecen sobre informes de auditoría;
- cualquier nuevo proceso de invitación debe cumplir el invariante de email canónico desde su diseño.

## 9. Criterio de cierre de esta auditoría

La auditoría documental se considera cerrada cuando:

- los documentos corregidos pasan Governance Guard, PWA Smoke y Schema Guard;
- la PR se fusiona sin checks críticos fallando;
- no se introduce DDL ni cambio funcional dentro de la PR documental;
- el informe queda enlazado desde `README.md` y `DOCUMENTATION_INDEX.md`.
