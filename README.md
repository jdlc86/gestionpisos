# GestionPisos

Plataforma para la gestión integral de viviendas alquiladas por habitaciones.

> Estado: bootstrap inicial del proyecto. La documentación funcional, de seguridad, permisos y release se mantiene en `docs/`.

## Infraestructura inicial

- Frontend: PWA desplegable en GitHub Pages.
- Backend: Supabase (`qsxtmmkftsohkqqmytbb`).
- Repositorio: `jdlc86/gestionpisos`.

## Gobierno del proyecto

Antes de implementar funcionalidad deben leerse y respetarse:

- `AGENTS.md`
- `docs/PRODUCT_CONTRACT.md`
- `docs/SECURITY_CONTRACT.md`
- `docs/PERMISSIONS_CONTRACT.md`
- `docs/AUTH_CONTRACT.md`
- `docs/AUTH_EMAIL_DELIVERY_MIGRATION.md`
- `docs/TESTING_STRATEGY.md`
- `docs/RELEASE_CONTRACT.md`

Los cambios que contradigan estos contratos se consideran defectos aunque técnicamente funcionen.

## Recuperación de contraseña en producción

La recuperación de contraseña no puede depender del SMTP incorporado de Supabase ni de su límite reducido de correo. La arquitectura objetivo mantiene Supabase Auth para tokens y sesiones, pero usa SMTP transaccional propio, con Resend como proveedor preferido inicial. La migración completa y sus criterios de aceptación están definidos en `docs/AUTH_EMAIL_DELIVERY_MIGRATION.md`.
