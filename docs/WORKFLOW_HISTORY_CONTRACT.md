# Contrato — Historial transversal de Flujos de Trabajo

## Propósito

Historial es una **vista de lectura** del motor existente. No crea una tabla de histórico paralela ni reinterpreta decisiones pasadas.

Cadena reconstruida:

`Definición/versión → Aplicación → Ejecución → Tarea → Evidencias → Decisiones/Revisión → Cierre`

## Fuentes de verdad

La vista compone únicamente información ya persistida:

- `workflow_executions_v2`: identidad, snapshot, asignación, ámbito y estado de ejecución;
- `tenant_tasks_v2`: tarea materializada y estado sincronizado;
- `workflow_execution_events_v2`: línea temporal funcional del workflow;
- `tenant_task_history_v2`: notas/motivos asociados a acciones de tarea;
- `workflow_execution_photo_resources_v2` + `photo_verification_runs_v2`: evidencia y revisión fotográfica;
- `workflow_execution_documents_v2`: evidencia documental;
- `workflow_executions_v2.checklist_state`: estado final del checklist;
- `profiles`, `properties_v2`, `rooms_v2`, `occupancies_v2`: etiquetas legibles, nunca autorización.

No se usa `audit_log_v2` como histórico funcional de usuario. Su función sigue siendo auditoría administrativa/seguridad.

## Seguridad

La vista no introduce RPC privilegiado ni bypass de RLS.

Cada consulta usa las políticas existentes de las tablas fuente. Si un actor no puede leer una ejecución o una evidencia, Historial tampoco puede concederle acceso.

Los documentos privados se abren mediante URL firmada temporal y requieren la política SELECT vigente de Storage.

## Presentación

La interfaz muestra:

- nombre del flujo desde el snapshot de ejecución;
- destino y persona asignada;
- estado de ejecución/tarea;
- versión publicada cuando es visible;
- resumen de Foto, Checklist y Documento;
- eventos cronológicos;
- transición de estado cuando existe;
- actor legible;
- motivo de rechazo cuando está disponible.

No se muestran en UI:

- UUID;
- request keys;
- rutas de Storage;
- claves idempotentes;
- detalles técnicos internos sin valor operativo.

## Eventos

`workflow_execution_events_v2` es la línea temporal canónica. El histórico de tarea se usa solo para enriquecer notas/motivos cuando corresponda, evitando duplicar la misma transición visualmente.

Los tipos desconocidos se conservan y se presentan con una etiqueta neutral; no se eliminan del histórico.

## Inmutabilidad

Historial nunca modifica una ejecución pasada. Editar una definición futura no cambia el snapshot, evidencias ni eventos de una ejecución existente.

Archivar una definición con historial no elimina ni oculta sus ejecuciones históricas si el actor conserva autorización de lectura.

## Alcance inicial

La primera versión carga hasta 100 ejecuciones autorizadas recientes y permite:

- búsqueda contextual;
- filtro Todas / En curso / Completadas / Rechazadas;
- expansión de cada ejecución;
- apertura segura de documentos enviados.

La paginación histórica profunda y filtros avanzados por fechas/actor se añadirán cuando el volumen real lo justifique.
