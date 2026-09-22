# GestionPisos

Plataforma para la gestión integral de viviendas alquiladas por habitaciones, con la empresa gestora como núcleo operativo, documental y de permisos.

> Estado: **beta técnico activo / validación controlada**. El proyecto ya dispone de frontend PWA, backend Supabase, RLS, onboarding profesional, permisos administrativos, fotoverificación, tareas y un motor transversal de Flujos de Trabajo en evolución. No debe describirse como “bootstrap inicial”.

## Infraestructura

- Frontend: PWA desplegada mediante GitHub Pages.
- Backend: Supabase (`qsxtmmkftsohkqqmytbb`).
- Repositorio: `jdlc86/gestionpisos`.
- Autenticación: Supabase Auth con entrega profesional de correos críticos.
- Persistencia y autorización: PostgreSQL + RLS + RPC/Edge Functions para operaciones sensibles.
- Storage: privado para evidencias/documentos según contrato de cada módulo.
- Orquestación QA masiva (base documental, todavía no operativa): `jdlc86/Allaiso-QA-Orchestrator`. Ver `docs/QA_ORCHESTRATION_LINK.md`.

## Gobierno del proyecto

Antes de implementar funcionalidad deben leerse y respetarse:

- `AGENTS.md`
- `docs/PRODUCT_CONTRACT.md`
- `docs/SECURITY_CONTRACT.md`
- `docs/PERMISSIONS_CONTRACT.md`
- `docs/DATA_CONTRACT.md`
- `docs/AUTH_CONTRACT.md`
- `docs/EXTERNAL_ONBOARDING_CONTRACT.md`
- `docs/AUTH_EMAIL_DELIVERY_MIGRATION.md`
- `docs/TESTING_STRATEGY.md`
- `docs/RELEASE_CONTRACT.md`
- `docs/MIGRATION_HISTORY_CONTRACT.md`
- `docs/DOCUMENTATION_INDEX.md`

Los cambios que contradigan estos contratos se consideran defectos aunque técnicamente funcionen.

## Estado validado de onboarding y correo

A 18 de septiembre de 2026:

- OWNER/TENANT separan ficha de negocio e identidad Auth;
- cambiar el email con una invitación externa pendiente revoca primero la identidad/invitación anterior;
- ADMIN/EMPLOYEE guardan un `invitation_email` canónico que debe coincidir con perfil y Auth;
- operadores de emergencia guardan un `identity_email` inmutable y separado de los roles operativos de GestionPisos;
- una invitación **nunca se traslada silenciosamente a otro correo**;
- los conflictos o derivas de identidad se bloquean en backend/base de datos, no solo en UI.

La política autoritativa está en `docs/AUTH_CONTRACT.md`, `docs/EXTERNAL_ONBOARDING_CONTRACT.md` y `docs/PLATFORM_OPERATOR_CONSOLE.md`.

## Flujos de Trabajo

El motor transversal ya soporta, entre otros componentes:

- definiciones persistentes y versiones publicadas;
- aplicaciones a una entidad real;
- ejecución manual idempotente;
- materialización sobre `tenant_tasks_v2`;
- decisión del asignado **Aceptar / Rechazar**;
- evidencia fotográfica mediante la cámara y fotoverificación existentes;
- cierre transaccional de tarea + ejecución para los recorridos implementados.

El estado real, límites y siguiente incremento se mantienen en `docs/WORKFLOW_STATUS.md` y el índice específico `docs/WORKFLOW_DOCUMENTATION_INDEX.md`.

## Recuperación de contraseña en producción

La recuperación de contraseña no puede depender del SMTP incorporado de Supabase ni de su límite reducido de correo. La arquitectura mantiene Supabase Auth para tokens y sesiones, pero usa entrega transaccional propia, con Resend como proveedor preferido inicial.

La migración, seguridad y criterios de aceptación se definen en `docs/AUTH_EMAIL_DELIVERY_MIGRATION.md`.

## Auditoría documental

La última auditoría integral de consistencia código ↔ Supabase ↔ documentación está registrada en:

- `docs/DOCUMENTATION_AUDIT_2026-09-18.md`

Ese informe no sustituye a los contratos: resume evidencia y desajustes detectados en una fecha concreta.
