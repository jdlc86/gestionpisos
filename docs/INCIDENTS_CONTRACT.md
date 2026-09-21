# Contrato funcional — Incidencias

## Principio

Las incidencias pertenecen a un piso de una organización gestora. Allaiso es el centro del flujo. No existe comunicación documental directa entre inquilino y propietario.

## Actores

- Inquilino: crea incidencias únicamente sobre el piso/habitación donde tenga ocupación activa; aporta texto y fotografías; consulta evolución visible.
- Empleado: consulta incidencias de los pisos asignados; actúa cuando tenga permiso operativo sobre el piso.
- ADMIN: supervisa, prioriza, asigna, cambia estado y resuelve dentro de su organización.
- Propietario: consulta el estado y las evidencias que Allaiso marque como visibles para propietario.
- ROOT: supervisión global y auditoría.

## Estados

Recorrido WF-05:

`reported -> in_progress -> waiting_info -> in_progress -> resolved`

Los estados legacy `triaged`, `assigned` y `closed` se conservan para registros históricos y compatibilidad.

Estados excepcionales:

- `rejected`: reporte no procedente, siempre con motivo.
- `reopened`: problema reaparece tras resolución.

No se permite borrar físicamente una incidencia cerrada.

`waiting_info` es no terminal. La información recibida se añade al histórico y la gestión continúa sobre la misma ejecución/tarea.

## Prioridad

- low
- normal
- high
- urgent

`urgent` no sustituye un servicio de emergencias. La interfaz debe indicarlo cuando corresponda.

## Datos mínimos

- organización
- piso
- habitación opcional
- creador
- categoría
- descripción
- prioridad
- estado
- empleado asignado opcional
- timestamps
- fecha de resolución/cierre
- motivo de rechazo opcional

## Evidencias

Las fotografías se almacenan fuera de la tabla principal y se vinculan a la incidencia.

Cada evidencia registra:

- autor;
- momento;
- tipo;
- ruta de almacenamiento;
- visibilidad;
- hash/identificador de integridad cuando proceda.

No sobrescribir una evidencia existente. Una nueva fotografía crea una nueva evidencia.

## Visibilidad

Tres ámbitos:

- `tenant`: visible para el inquilino afectado y personal autorizado.
- `internal`: solo Allaiso.
- `owner`: visible para propietario y Allaiso.

Una evidencia subida por un inquilino no se comparte automáticamente con el propietario. Allaiso controla esa publicación.

## Comentarios

Separar:

- actualizaciones visibles al inquilino;
- notas internas de Allaiso;
- actualizaciones publicables al propietario.

No reutilizar un único campo de comentarios para los tres públicos.

## Asignación y escritura

La lectura sigue las reglas generales por ámbito.

La escritura operativa del piso respeta el modelo de responsable: por defecto una persona mantiene permiso de escritura. Otro empleado debe solicitar transferencia/autorización cuando corresponda.

ADMIN puede supervisar el flujo según sus capacidades.

La gestión nueva se materializa como `tenant_tasks_v2.task_type=workflow`, enlazada a una ejecución. El tipo legacy `incident` permanece solo por compatibilidad y no se crea en paralelo para una incidencia WF-05.

La apertura publica `incident.created` en el outbox común. La resolución publica `incident.resolved`, que puede activar una Inspección posterior basada en Foto/Checklist/Documento. Véase `WORKFLOW_INCIDENT_MAINTENANCE_INSPECTION_CONTRACT.md`.

## Auditoría

Auditar como mínimo:

- creación;
- cambio de prioridad;
- asignación/reasignación;
- cambio de estado;
- rechazo;
- resolución;
- reapertura;
- publicación de evidencia al propietario;
- modificaciones administrativas.

## Notificaciones

Eventos candidatos:

- incidencia creada;
- asignada;
- cambio relevante de estado;
- solicitud de información;
- resuelta;
- reabierta.

Las notificaciones in-app y email se generan desde eventos de dominio, no directamente desde componentes de interfaz.

## Seguridad

- RLS obligatoria.
- El inquilino no puede crear incidencias para otro piso.
- Un propietario no puede acceder a notas internas.
- Un empleado no puede modificar incidencias de pisos ajenos.
- Ninguna URL pública permanente para fotografías privadas.
- Storage privado con acceso autorizado/URLs firmadas.
- Validar tipo, tamaño y metadatos de archivos.
- No confiar en IDs de organización/piso enviados por el cliente sin validación backend.

## Criterio Beta

El módulo no se considera cerrado hasta probar al menos:

1. tenant A crea incidencia en su habitación;
2. tenant A no puede crear/leer la del piso B;
3. empleado A puede leer su piso;
4. empleado B no puede modificarlo;
5. propietario ve solo contenido publicado;
6. propietario no ve notas internas;
7. resolución queda auditada;
8. evidencia privada no es accesible anónimamente;
9. reapertura conserva histórico.
