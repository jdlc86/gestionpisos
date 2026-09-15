# Contrato de seguridad

ROOT es un rol protegido. RLS es obligatoria en datos sensibles. La autorización se valida en backend y base de datos. QR no concede acceso. MFA es obligatorio para ROOT y ADMIN. Los cambios de contraseña invalidan las demás sesiones. Las acciones críticas se auditan. La IA no toma decisiones de seguridad.


## Privacidad y ciclo de vida del inquilino

- Estados visibles: **Alta**, **Suspendido**, **Baja · pendiente de eliminación**.
- Suspendido conserva datos pero debe impedir acceso a la plataforma.
- Baja revoca acceso y marca candidatura a eliminación; no garantiza borrado inmediato.
- La purga definitiva debe ejecutarse server-side con privilegios mínimos, inventariar referencias, eliminar los objetos privados y datos eliminables, tratar Auth y verificar el resultado.
- Nunca comunicar “no conservamos ningún dato” sin una verificación posterior de todas las dependencias y posibles obligaciones de retención.
- La comunicación final debe distinguir datos eliminados de datos que deban conservarse bloqueados por obligación legal.
- Los documentos de identidad se almacenan exclusivamente en Storage privado; las URLs de visualización deben ser firmadas y de corta duración.
