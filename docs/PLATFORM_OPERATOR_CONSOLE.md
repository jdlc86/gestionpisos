# Consola de operador de plataforma Allaiso

La consola de recuperación MFA es una herramienta técnica separada de GestionPisos. Su única finalidad inicial es revisar y resolver solicitudes `break-glass` de ROOT/ADMIN que han perdido todos sus autenticadores.

## Separación de privilegios

- Ser ROOT o ADMIN de GestionPisos **no convierte** a nadie en operador de plataforma.
- ROOT designa y revoca operadores explícitamente desde la zona de seguridad de GestionPisos, usando una sesión `aal2`.
- Los operadores autorizados se registran en `public.platform_operators` únicamente a través de backend privilegiado; la tabla no tiene acceso directo para `anon` ni `authenticated`.
- La identidad elegida como operador debe ser una cuenta Auth técnica independiente, distinta del ROOT que podría necesitar recuperación y sin rol operativo ROOT/ADMIN/EMPLOYEE/OWNER/TENANT en GestionPisos.
- Cada operador usa su propia identidad Auth y debe alcanzar `aal2` mediante TOTP antes de listar, aprobar o rechazar solicitudes.
- La sesión de la consola usa una clave de almacenamiento distinta de la sesión normal de GestionPisos.
- Un operador nunca recibe ni visualiza la credencial de servicio del proyecto.

## Capacidades

`operator-mfa-recovery` expone solo las acciones controladas `status`, `list`, `approve` y `reject`.

- `status`: valida que la identidad sea un operador activo. Puede responder en `aal1` únicamente para permitir completar el MFA del propio operador.
- `list`: requiere `aal2` y devuelve solicitudes pendientes y vigentes.
- `approve`: requiere `aal2`, una nota de verificación independiente, prohíbe autoaprobar la propia recuperación y, para un objetivo ROOT, exige `can_recover_root=true`.
- `reject`: requiere `aal2` y una justificación; registra el rechazo en auditoría.

La aprobación no ejecuta operaciones administrativas desde JavaScript. El gateway backend llama a `recover-privileged-mfa` usando la credencial de servicio únicamente dentro del entorno de Edge Functions.

## Gestión desde ROOT

La configuración ordinaria se realiza desde **GestionPisos → Gestión de Permisos → Operadores de emergencia**.

1. ROOT debe tener una sesión válida con MFA `aal2`.
2. ROOT introduce el correo y nombre del operador. Si todavía no existe una identidad Auth técnica para ese correo, el backend la crea sin contraseña conocida por ROOT.
3. El backend comprueba que la cuenta sea distinta del ROOT actual y que no tenga un rol operativo de GestionPisos.
4. Si la identidad es nueva, se envía mediante el proveedor profesional de correo un enlace de un solo uso para que el operador cree personalmente su contraseña.
5. ROOT puede activar/desactivar al operador y conceder o retirar `can_recover_root`.
6. No se borran filas para revocar acceso: se conserva el registro y cada cambio genera auditoría.
7. La protección no se considera lista mientras no exista al menos un operador activo, autorizado para ROOT y con MFA verificado.

La consola independiente de Allaiso **no permite** crear operadores, elevarse a sí misma ni modificar `can_recover_root`; solo consume la autorización previamente otorgada por ROOT para gestionar incidentes de recuperación.

### Bootstrap técnico excepcional

La inserción administrativa directa en `public.platform_operators` queda reservada a recuperación técnica excepcional cuando no sea posible usar la interfaz ROOT. No es el flujo normal y debe conservar la misma trazabilidad y separación de identidad.

## Preparación de un operador

1. ROOT designa el correo desde Gestión de Permisos y decide si puede recuperar ROOT.
2. Si la cuenta técnica no existía, el operador recibe el correo profesional de activación, crea su propia contraseña y no recibe ninguna contraseña temporal.
3. El operador abre `operator-recovery.html`, inicia sesión y registra/verifica TOTP.
4. Probar primero `list` y `reject` con una solicitud de ensayo. Una aprobación real es destructiva para la contraseña, sesiones y factores MFA del usuario objetivo.

No se debe reutilizar como único operador la misma cuenta ROOT cuya recuperación se pretende garantizar. La función bloquea la autoaprobación.

## Operación normal

El operador abre la consola, inicia sesión con su identidad técnica y completa MFA. La lista muestra únicamente solicitudes vigentes y no resueltas. Antes de aprobar debe verificar la identidad por un canal independiente y escribir un resumen de esa verificación.

Al aprobar, el backend ejecuta el procedimiento definido en `MFA_RECOVERY_RUNBOOK.md`: revocación de sesiones, invalidación de contraseña, retirada de factores y recuperación de contraseña. Al rechazar, el estado terminal queda auditado y la solicitud ya no puede aprobarse posteriormente.
