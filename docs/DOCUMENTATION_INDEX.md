# Índice general de documentación — GestionPisos

Este índice es la puerta de entrada documental del proyecto. Los contratos son autoritativos; los informes de auditoría son fotografías fechadas del estado real y no sustituyen contratos.

## 1. Gobierno y producto

1. **`AGENTS.md`** — reglas obligatorias para cualquier desarrollador o agente.
2. **`PRODUCT_CONTRACT.md`** — propósito, actores y límites funcionales del producto.
3. **`RELEASE_CONTRACT.md`** — condiciones mínimas para publicar cambios.
4. **`TESTING_STRATEGY.md`** — capas de prueba, negativas mínimas y criterio de merge.
5. **`MIGRATION_HISTORY_CONTRACT.md`** — disciplina obligatoria para migraciones y drift.

## 2. Seguridad, permisos y datos

1. **`SECURITY_CONTRACT.md`** — invariantes generales de seguridad, MFA, recuperación y operaciones críticas.
2. **`PERMISSIONS_CONTRACT.md`** — matriz de capacidades y reglas por rol.
3. **`DATA_CONTRACT.md`** — responsabilidades de datos, históricos, soft-delete y separación de entidades.
4. **`AUTH_CONTRACT.md`** — autenticación, onboarding, recuperación y regla global de email de invitación.
5. **`EXTERNAL_ONBOARDING_CONTRACT.md`** — OWNER/TENANT: separación ficha ↔ Auth, bienvenida, activación y cambio de email.
6. **`PLATFORM_OPERATOR_CONSOLE.md`** — identidad técnica y autorización de operadores de emergencia.
7. **`MFA_RECOVERY_RUNBOOK.md`** — procedimiento operativo para recuperación privilegiada.
8. **`AUTH_EMAIL_DELIVERY_MIGRATION.md`** — entrega profesional de correos críticos.

## 3. Flujos de Trabajo

Usar **`WORKFLOW_DOCUMENTATION_INDEX.md`** como índice específico. Allí se ordenan:

- arquitectura;
- implementación;
- motor;
- aplicaciones;
- ejecución;
- tareas;
- acciones;
- evidencia fotográfica;
- estado real.

## 4. Evidencia y auditorías fechadas

- **`DOCUMENTATION_AUDIT_2026-09-18.md`** — auditoría código ↔ Supabase ↔ documentación del 18/09/2026.

Los informes fechados pueden quedar históricos. No deben reescribirse para ocultar decisiones anteriores.

## 5. Regla de actualización

Cuando cambie una capacidad:

- **concepto de producto** → actualizar `PRODUCT_CONTRACT.md`;
- **seguridad/autenticación** → actualizar `SECURITY_CONTRACT.md` y/o `AUTH_CONTRACT.md`;
- **quién puede hacer qué** → actualizar `PERMISSIONS_CONTRACT.md`;
- **modelo/invariante de datos** → actualizar `DATA_CONTRACT.md`;
- **OWNER/TENANT onboarding** → actualizar `EXTERNAL_ONBOARDING_CONTRACT.md`;
- **operadores de emergencia** → actualizar `PLATFORM_OPERATOR_CONSOLE.md`;
- **Flujos de Trabajo** → seguir la regla de mantenimiento de `WORKFLOW_DOCUMENTATION_INDEX.md`;
- **cambio de esquema** → revisar `MIGRATION_HISTORY_CONTRACT.md`;
- **cambio de release/pruebas** → revisar `RELEASE_CONTRACT.md` y `TESTING_STRATEGY.md`.

Una funcionalidad no debe describirse como operativa solo porque exista una UI. La documentación de estado debe distinguir siempre entre propuesta, implementación, despliegue y validación E2E.
