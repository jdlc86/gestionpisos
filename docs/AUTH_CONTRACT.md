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
- El enlace debe volver a una URL de producción autorizada; `localhost` está prohibido fuera de desarrollo local.
- La pantalla de nueva contraseña solo se habilita tras validar una sesión/token de recuperación legítimo.
- Al completar recuperación/cambio se invalidan todas las demás sesiones.
- ROOT/ADMIN deben completar MFA según política.

## Entrega profesional de correos de autenticación

El envío de correos críticos de autenticación en producción **no puede depender del SMTP incorporado de Supabase**.

- El SMTP incorporado solo se acepta para desarrollo/pruebas.
- Producción debe usar SMTP personalizado con un proveedor transaccional controlado por el proyecto.
- Proveedor preferido inicial: Resend; la aplicación no debe quedar acoplada al proveedor.
- Las credenciales SMTP nunca pueden residir en frontend, GitHub Pages, commits ni documentación pública.
- El dominio remitente debe tener SPF, DKIM y DMARC configurados.
- Los límites de Auth deben revisarse y configurarse explícitamente tras activar SMTP personalizado.
- Un entorno limitado por el SMTP incorporado de Supabase o por un techo equivalente a 2 correos/hora no se considera apto para producción.
- La política completa de migración, pruebas, observabilidad y resiliencia está en `docs/AUTH_EMAIL_DELIVERY_MIGRATION.md`.

## Bloqueo/revocación

Bloquear acceso no borra al usuario ni su histórico. Debe impedir nuevas operaciones y hacer inefectivas las sesiones conforme a la política de seguridad.

## Eventos de email mínimos

- solicitud recibida cuando proceda
- acceso aprobado/rechazado
- activación
- recuperación de contraseña
- cambio de rol de empleado
- eventos/reclamaciones configuradas
