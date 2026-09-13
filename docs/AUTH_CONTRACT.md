# Contrato de autenticación y acceso

## Alta de inquilino

1. ADMIN precarga ocupación: piso, habitación, email y datos requeridos.
2. ADMIN genera QR revocable asociado al piso.
3. Inquilino escanea QR e introduce email.
4. Backend valida que la solicitud concuerda con una ocupación prevista del piso.
5. Se crea solicitud pendiente sin conceder acceso.
6. ADMIN acepta o rechaza.
7. Si acepta, se envía enlace de activación de un solo uso.
8. Usuario establece su contraseña.
9. Accede a la PWA con email + contraseña.
10. Si el dispositivo conserva sesión válida, un QR puede resolver el contexto de piso sin pedir login de nuevo.

## Recuperación

- “Olvidé mi contraseña” → email → enlace de un solo uso → nueva contraseña.
- Respuesta neutra para evitar enumeración de cuentas.
- Al completar recuperación/cambio se invalidan todas las demás sesiones.
- ROOT/ADMIN deben completar MFA según política.

## Bloqueo/revocación

Bloquear acceso no borra al usuario ni su histórico. Debe impedir nuevas operaciones y hacer inefectivas las sesiones conforme a la política de seguridad.

## Eventos de email mínimos

- solicitud recibida cuando proceda
- acceso aprobado/rechazado
- activación
- recuperación de contraseña
- cambio de rol de empleado
- eventos/reclamaciones configuradas
