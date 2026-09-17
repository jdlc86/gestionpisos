# Consola de operador de plataforma Allaiso

La consola de recuperación MFA es una herramienta técnica separada de GestionPisos. Su única finalidad inicial es revisar y resolver solicitudes `break-glass` de ROOT/ADMIN que han perdido todos sus autenticadores.

## Separación de privilegios

- Ser ROOT o ADMIN de GestionPisos **no convierte** a nadie en operador de plataforma.
- Los operadores se autorizan explícitamente en `public.platform_operators`.
- La tabla no tiene acceso directo para `anon` ni `authenticated`; solo backend con privilegios de servicio puede consultarla.
- Cada operador usa una identidad Auth propia y debe alcanzar `aal2` mediante TOTP antes de listar, aprobar o rechazar solicitudes.
- La sesión de la consola usa una clave de almacenamiento distinta de la sesión normal de GestionPisos.
- Un operador nunca recibe ni visualiza la credencial de servicio del proyecto.

## Capacidades

`operator-mfa-recovery` expone solo las acciones controladas `status`, `list`, `approve` y `reject`.

- `status`: valida que la identidad sea un operador activo. Puede responder en `aal1` únicamente para permitir completar el MFA del propio operador.
- `list`: requiere `aal2` y devuelve solicitudes pendientes y vigentes.
- `approve`: requiere `aal2`, una nota de verificación independiente, prohíbe autoaprobar la propia recuperación y, para un objetivo ROOT, exige `can_recover_root=true`.
- `reject`: requiere `aal2` y una justificación; registra el rechazo en auditoría.

La aprobación no ejecuta operaciones administrativas desde JavaScript. El gateway backend llama a `recover-privileged-mfa` usando la credencial de servicio únicamente dentro del entorno de Edge Functions.

## Alta inicial de un operador

La primera identidad de operador se provisiona de forma técnica y deliberada:

1. Crear o seleccionar una identidad Supabase Auth **distinta** de la cuenta ROOT que podría necesitar recuperación.
2. Insertar su `user_id` en `public.platform_operators`, con un nombre visible y `active=true`.
3. Conceder `can_recover_root=true` solo a operadores expresamente autorizados para recuperar ROOT.
4. El operador abre `operator-recovery.html`, inicia sesión y registra/verifica TOTP si todavía no lo tiene.
5. Probar primero `list` y `reject` con una solicitud de ensayo. Una aprobación real es destructiva para la contraseña, sesiones y factores MFA del usuario objetivo.

No se debe reutilizar como único operador la misma cuenta ROOT cuya recuperación se pretende garantizar. La función bloquea la autoaprobación.

## Operación normal

El operador abre la consola, inicia sesión con su identidad técnica y completa MFA. La lista muestra únicamente solicitudes vigentes y no resueltas. Antes de aprobar debe verificar la identidad por un canal independiente y escribir un resumen de esa verificación.

Al aprobar, el backend ejecuta el procedimiento definido en `MFA_RECOVERY_RUNBOOK.md`: revocación de sesiones, invalidación de contraseña, retirada de factores y recuperación de contraseña. Al rechazar, el estado terminal queda auditado y la solicitud ya no puede aprobarse posteriormente.
