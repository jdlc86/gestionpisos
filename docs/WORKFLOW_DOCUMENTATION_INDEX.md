# Índice documental — Flujos de Trabajo

Usar estos documentos en este orden:

1. **`WORKFLOW_ARCHITECTURE.md`** — decisión funcional y de producto. Explica qué es un flujo, cómo se separan recursos, ejecución, tareas, evidencias e histórico, y por qué Limpieza/Mantenimiento/Inspección no deben tener motores independientes.
2. **`WORKFLOW_IMPLEMENTATION_MAP.md`** — traducción de la arquitectura al esquema y componentes actuales de GestionPisos. Indica qué se reutiliza, qué se conserva como legacy y qué falta.
3. **`WORKFLOW_ENGINE_CONTRACT.md`** — contrato técnico obligatorio del motor persistente: versionado, idempotencia, asignación server-side, RLS, snapshots, tareas, evidencias y adaptador de Limpieza.
4. **`WORKFLOW_APPLICATIONS_CONTRACT.md`** — separación obligatoria entre receta lógica y destino real; publicación, aplicación concreta, RLS y límites de ejecución.
5. **`WORKFLOW_STATUS.md`** — fotografía fechada del estado real de implementación, PRs integrados, límites actuales y siguiente incremento.

## Regla de mantenimiento

- Cambios de **concepto/arquitectura** → actualizar `WORKFLOW_ARCHITECTURE.md`.
- Cambios en **reutilización o mapeo de piezas existentes** → actualizar `WORKFLOW_IMPLEMENTATION_MAP.md`.
- Cambios en **invariantes del motor o seguridad técnica** → actualizar `WORKFLOW_ENGINE_CONTRACT.md` antes del código que dependa de ellos.
- Cambios en **vinculación receta ↔ entidad real** → actualizar `WORKFLOW_APPLICATIONS_CONTRACT.md`.
- Cambios de **estado real de implementación** → actualizar `WORKFLOW_STATUS.md` con fecha, sin reescribir decisiones históricas.

La documentación nunca debe presentar como operativo un componente que solo existe como UI, borrador o propuesta.
