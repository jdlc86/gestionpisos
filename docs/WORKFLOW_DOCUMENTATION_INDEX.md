# Índice documental — Flujos de Trabajo

Usar estos documentos en este orden:

1. **`WORKFLOW_ARCHITECTURE.md`** — decisión funcional y de producto. Explica qué es un flujo, cómo se separan recursos, ejecución, tareas, evidencias e histórico, y por qué Limpieza/Mantenimiento/Inspección no deben tener motores independientes.
2. **`WORKFLOW_IMPLEMENTATION_MAP.md`** — traducción de la arquitectura al esquema y componentes actuales de GestionPisos. Indica qué se reutiliza, qué se conserva como legacy y qué falta.
3. **`WORKFLOW_ENGINE_CONTRACT.md`** — contrato técnico obligatorio del motor persistente: versionado, idempotencia, asignación server-side, RLS, snapshots, tareas, evidencias y adaptador de Limpieza.
4. **`WORKFLOW_APPLICATIONS_CONTRACT.md`** — separación obligatoria entre receta lógica y destino real; publicación, aplicación concreta, RLS y límites de ejecución.
5. **`WORKFLOW_EXECUTION_CONTRACT.md`** — contrato del primer runner manual idempotente, asignación congelada, seguridad e histórico mínimo.
6. **`WORKFLOW_TASKS_CONTRACT.md`** — generalización aditiva de `tenant_tasks_v2`, materialización idempotente, RLS y límites de acciones.
7. **`WORKFLOW_ACTIONS_CONTRACT.md`** — acciones derivadas de la receta, autorización del asignado, idempotencia y transición atómica tarea ↔ ejecución.
8. **`WORKFLOW_PHOTO_EVIDENCE_CONTRACT.md`** — binding de patrones, snapshot por ejecución, cámara reutilizada y cierre transaccional de evidencia fotográfica.
9. **`WORKFLOW_STATUS.md`** — fotografía fechada del estado real de implementación, PRs integrados, límites actuales y siguiente incremento.
10. **`WORKFLOW_CHECKLIST_CONTRACT.md`** — contrato específico del primer checklist genérico: autoría, snapshot, permisos, idempotencia y cierre.
11. **`WORKFLOW_DOCUMENT_EVIDENCE_CONTRACT.md`** — contrato del paso Documento: Storage privado, permisos, idempotencia y cierre coordinado con Foto/Checklist.
12. **`WORKFLOW_HISTORY_CONTRACT.md`** — contrato de la vista Historial: fuentes de verdad, RLS, eventos, evidencias e inmutabilidad.
13. **`WORKFLOW_SCHEDULE_CONTRACT.md`** — contrato de Fecha concreta automática: tiempo exacto, asignación, scheduler, idempotencia y bloqueos.

## Regla de mantenimiento

- Cambios de **concepto/arquitectura** → actualizar `WORKFLOW_ARCHITECTURE.md`.
- Cambios en **reutilización o mapeo de piezas existentes** → actualizar `WORKFLOW_IMPLEMENTATION_MAP.md`.
- Cambios en **invariantes del motor o seguridad técnica** → actualizar `WORKFLOW_ENGINE_CONTRACT.md` antes del código que dependa de ellos.
- Cambios en **vinculación receta ↔ entidad real** → actualizar `WORKFLOW_APPLICATIONS_CONTRACT.md`.
- Cambios en **creación/idempotencia/asignación de ejecuciones** → actualizar `WORKFLOW_EXECUTION_CONTRACT.md`.
- Cambios en **materialización/visibilidad de tareas** → actualizar `WORKFLOW_TASKS_CONTRACT.md`.
- Cambios en **acciones/transiciones atómicas tarea ↔ ejecución** → actualizar `WORKFLOW_ACTIONS_CONTRACT.md`.
- Cambios en **patrones/snapshots/captura fotográfica de workflows** → actualizar `WORKFLOW_PHOTO_EVIDENCE_CONTRACT.md`.
- Cambios en **evidencia documental de workflows** → actualizar `WORKFLOW_DOCUMENT_EVIDENCE_CONTRACT.md`.
- Cambios en **presentación histórica transversal** → actualizar `WORKFLOW_HISTORY_CONTRACT.md`.
- Cambios en **disparadores automáticos / Fecha concreta / recurrencia** → actualizar `WORKFLOW_SCHEDULE_CONTRACT.md`.
- Cambios de **estado real de implementación** → actualizar `WORKFLOW_STATUS.md` con fecha, sin reescribir decisiones históricas.

La documentación nunca debe presentar como operativo un componente que solo existe como UI, borrador o propuesta.
