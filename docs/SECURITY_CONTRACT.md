# Contrato de seguridad

ROOT es un rol protegido. RLS es obligatoria en datos sensibles. La autorización se valida en backend y base de datos. QR no concede acceso. MFA es obligatorio para ROOT y ADMIN. Los cambios de contraseña invalidan las demás sesiones. Las acciones críticas se auditan. La IA no toma decisiones de seguridad.

## Invariante de identidad e invitaciones

- Toda invitación de acceso queda ligada a un usuario/identidad y a un email canónico concretos.
- Cambiar el email no transfiere automáticamente la invitación ni los privilegios asociados.
- OWNER/TENANT con invitación pendiente requieren revocar la identidad/invitación anterior antes de guardar el nuevo correo y crear una bienvenida nueva.
- ADMIN/EMPLOYEE requieren coincidencia entre `internal_staff_onboarding.invitation_email`, `profiles.email` y `auth.users.email`; cualquier deriva bloquea reenvío y activación.
- Los operadores de emergencia requieren coincidencia entre `platform_operators.identity_email` y el email Auth; una deriva bloquea la consola y las capacidades hasta reprovisión.
- Las comprobaciones anteriores deben existir en backend/base de datos. Una tarjeta o botón correcto en frontend no constituye por sí solo una garantía de seguridad.
- Una cuenta ya activada no cambia de email mediante una edición ordinaria de ficha; debe existir un flujo explícito de cambio de identidad/cuenta.

## Recuperación de emergencia MFA

- La interfaz normal nunca permite que ROOT/ADMIN elimine su último factor MFA verificado.
- Si se pierden todos los autenticadores disponibles, el usuario puede crear una solicitud `break-glass`, pero la solicitud por sí sola no modifica factores, contraseña, sesiones, roles ni permisos.
- La recuperación destructiva solo puede ejecutarse desde backend/plataforma tras una verificación humana independiente de la identidad; el código de solicitud no constituye prueba de identidad ni autorización.
- Antes de retirar los factores, el proceso debe revocar las sesiones activas. La contraseña anterior debe quedar invalidada y el usuario debe completar recuperación de contraseña antes de volver a operar.
- Tras retirar los factores, ROOT/ADMIN queda obligado a enrolar MFA de nuevo antes del acceso operativo.
- Solicitud, ejecución, resultado, operador y evidencia resumida de verificación deben quedar auditados. Los estados parciales no se ocultan ni se corrigen borrando histórico.
- ROOT puede designar, desactivar y limitar operadores de emergencia desde GestionPisos únicamente con una sesión `aal2`; la autorización se ejecuta en backend y nunca mediante acceso directo del navegador a `platform_operators`.
- Una identidad de operador de emergencia debe ser independiente de la cuenta ROOT a recuperar y no debe reutilizar un rol operativo ROOT/ADMIN/EMPLOYEE/OWNER/TENANT.
- La consola técnica de operador no puede crear operadores, concederse `can_recover_root` ni elevar sus propios privilegios. Solo consume autorizaciones previamente otorgadas por ROOT.
- Si no queda ningún operador activo con `can_recover_root=true`, la aplicación debe advertir a ROOT del riesgo de bloqueo, sin ocultar ni falsificar un mecanismo de recuperación inexistente.
- El procedimiento operativo completo está en `docs/MFA_RECOVERY_RUNBOOK.md` y la separación de la consola en `docs/PLATFORM_OPERATOR_CONSOLE.md`.

## Factory reset del entorno de pruebas

- El reset total de datos de prueba es una operación **R4 destructiva** y nunca forma parte de la operativa normal.
- Solo puede iniciarlo un usuario con rol `root`, sesión válida y `aal2`.
- El helper debe exigir una vista previa previa con caducidad corta y una confirmación explícita; una llamada directa sin esos pasos se rechaza.
- El baseline protegido es exactamente: ROOT activo, una identidad técnica de operador de emergencia activa y con `can_recover_root=true`, la organización activa y la configuración estructural/plantillas expresamente preservadas.
- Si no existe exactamente un operador técnico válido para recuperación de ROOT, el reset se bloquea en vez de adivinar qué identidad conservar.
- El reset puede purgar auditoría histórica **solo en este flujo de pruebas**; inmediatamente después debe crear un nuevo evento `factory_reset_completed` que identifique ROOT, operador preservado, organización y momento de ejecución.
- Los objetos de Storage se eliminan mediante la API oficial de Storage, nunca borrando filas de `storage.objects` por SQL.
- El backend debe eliminar todas las identidades Auth no protegidas después de limpiar las referencias de negocio. Debe verificar como postcondición que solo permanecen ROOT y el operador técnico seleccionado.
- Un fallo parcial debe devolverse como tal y el helper debe ser idempotente para permitir completar la limpieza sin reconstruir datos eliminados.
- Este flujo solo es válido mientras el entorno siga siendo de pruebas y no contenga usuarios/datos reales. Antes de una puesta en producción real debe deshabilitarse o sustituirse por políticas de borrado/retención específicas.

## Privacidad del inquilino

- **Suspendido** debe impedir acceso sin destruir la ficha.
- **Baja · pendiente de eliminación** revoca acceso e inicia el proceso de salida, pero no garantiza borrado inmediato.
- La purga definitiva debe inventariar referencias, respetar retenciones aplicables, eliminar datos eliminables en Storage/BD/Auth y verificar el resultado.
- Nunca comunicar «no conservamos ningún dato» sin verificación posterior.
