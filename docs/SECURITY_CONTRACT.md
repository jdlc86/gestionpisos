# Contrato de seguridad

ROOT es un rol protegido. RLS es obligatoria en datos sensibles. La autorización se valida en backend y base de datos. QR no concede acceso. MFA es obligatorio para ROOT y ADMIN. Los cambios de contraseña invalidan las demás sesiones. Las acciones críticas se auditan. La IA no toma decisiones de seguridad.

## Recuperación de emergencia MFA

- La interfaz normal nunca permite que ROOT/ADMIN elimine su último factor MFA verificado.
- Si se pierden todos los autenticadores disponibles, el usuario puede crear una solicitud `break-glass`, pero la solicitud por sí sola no modifica factores, contraseña, sesiones, roles ni permisos.
- La recuperación destructiva solo puede ejecutarse desde backend/plataforma tras una verificación humana independiente de la identidad; el código de solicitud no constituye prueba de identidad ni autorización.
- Antes de retirar los factores, el proceso debe revocar las sesiones activas. La contraseña anterior debe quedar invalidada y el usuario debe completar recuperación de contraseña antes de volver a operar.
- Tras retirar los factores, ROOT/ADMIN queda obligado a enrolar MFA de nuevo antes del acceso operativo.
- Solicitud, ejecución, resultado, operador y evidencia resumida de verificación deben quedar auditados. Los estados parciales no se ocultan ni se corrigen borrando histórico.
- El procedimiento operativo completo está en `docs/MFA_RECOVERY_RUNBOOK.md`.

## Privacidad del inquilino

- **Suspendido** debe impedir acceso sin destruir la ficha.
- **Baja · pendiente de eliminación** revoca acceso e inicia el proceso de salida, pero no garantiza borrado inmediato.
- La purga definitiva debe inventariar referencias, respetar retenciones aplicables, eliminar datos eliminables en Storage/BD/Auth y verificar el resultado.
- Nunca comunicar «no conservamos ningún dato» sin verificación posterior.
- Los documentos de identidad viven exclusivamente en Storage privado y solo se visualizan mediante acceso autorizado temporal.
