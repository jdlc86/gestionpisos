# Contrato de seguridad

ROOT es un rol protegido. RLS es obligatoria en datos sensibles. La autorización se valida en backend y base de datos. QR no concede acceso. MFA es obligatorio para ROOT y ADMIN. Los cambios de contraseña invalidan las demás sesiones. Las acciones críticas se auditan. La IA no toma decisiones de seguridad.


## Privacidad del inquilino

- **Suspendido** debe impedir acceso sin destruir la ficha.
- **Baja · pendiente de eliminación** revoca acceso e inicia el proceso de salida, pero no garantiza borrado inmediato.
- La purga definitiva debe inventariar referencias, respetar retenciones aplicables, eliminar datos eliminables en Storage/BD/Auth y verificar el resultado.
- Nunca comunicar «no conservamos ningún dato» sin verificación posterior.
- Los documentos de identidad viven exclusivamente en Storage privado y solo se visualizan mediante acceso autorizado temporal.
