# Nota de seguridad · finalización del onboarding interno

El onboarding de ADMIN/EMPLOYEE usa dos capas de autorización: la base de datos (`user_roles` y accesos) y los claims de Supabase Auth (`app_metadata`) que todavía consumen varias políticas RLS y la navegación cliente.

La finalización debe respetar este orden obligatorio:

1. el usuario demuestra control del correo mediante el enlace de un solo uso;
2. el usuario define su propia contraseña;
3. el backend activa primero el rol y los accesos autorizados en la base de datos;
4. solo después de una activación de base de datos correcta, un Edge Function con service role sincroniza `app_metadata.role` y `app_metadata.organization_id`;
5. el usuario cierra sesión y vuelve a entrar para obtener un JWT nuevo con los claims actualizados.

Nunca se deben publicar claims de rol/organización antes de que exista el rol autoritativo en base de datos. Si la sincronización de Auth falla después del paso 3, el resultado seguro es denegar temporalmente acceso; el proceso es reintentable e idempotente.

La función cliente no puede escribir `app_metadata`. La finalización privilegiada se realiza mediante `complete-staff-onboarding`, con JWT válido y verificación del registro `internal_staff_onboarding` del propio usuario.
