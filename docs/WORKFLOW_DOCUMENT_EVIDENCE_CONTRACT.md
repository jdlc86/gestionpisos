# Contrato — Evidencia documental de Flujos de Trabajo

## Propósito

Este contrato define el paso **Documento** del motor transversal de Flujos de Trabajo.

Cadena operativa:

`Definición → Ejecución → Tarea → Preparar documento → Storage privado → Confirmar evidencia → Cierre`

Documento no crea un motor de tareas paralelo ni reutiliza de forma incorrecta el expediente documental de inquilinos.

## 1. Autoría

La receta activa Documento con:

`steps.document=true`

En la primera versión no se configura cantidad, plantilla, firma ni clasificación documental. El contrato mínimo es:

- se puede adjuntar uno o más archivos;
- **al menos un documento `submitted` satisface el paso**;
- formatos permitidos: PDF, JPEG, PNG y WebP;
- máximo 10 MiB por archivo.

La versión publicada conserva el flag en `spec_snapshot` de cada ejecución.

## 2. Persistencia

La evidencia vive en:

`workflow_execution_documents_v2`

Cada fila conserva:

- ejecución;
- tarea materializada;
- organización;
- usuario que adjunta;
- nombre original;
- MIME;
- tamaño;
- ruta privada de Storage;
- clave idempotente;
- estado `uploading/submitted`;
- fechas de preparación y envío.

No se crea una segunda tabla de tareas ni se modifica `tenant_documents_v2`, cuyo significado sigue siendo expediente privado de un inquilino.

## 3. Storage

Bucket privado:

`workflow-documents-v2`

Contrato de ruta:

`organization_id/execution_id/document_id.ext`

El nombre original nunca se usa como ruta física.

El bucket:

- no es público;
- limita cada objeto a 10 MiB;
- admite únicamente PDF/JPEG/PNG/WebP;
- no permite escritura arbitraria del cliente.

La carga se realiza con la API de Supabase Storage. La tabla `storage.objects` solo se consulta para verificar la existencia/propiedad del objeto; no se modifica directamente desde lógica de producción.

## 4. Seguridad

La persona asignada es la única que puede preparar y confirmar evidencia documental.

`prepare_workflow_document_upload_v1`:

- deriva ejecución y organización desde la tarea;
- valida que Documento esté configurado;
- valida actor, estado, MIME y tamaño;
- si la receta requiere Aceptar, bloquea Documento hasta que la tarea esté activa;
- genera la ruta de Storage server-side;
- es idempotente por `execution_id + request_key`.

La política INSERT de Storage exige que exista previamente una fila `uploading` autorizada para esa ruta.

`submit_workflow_document_v1`:

- valida nuevamente actor/tarea/ejecución;
- exige que el objeto privado exista y pertenezca al actor;
- cambia la evidencia a `submitted`;
- registra histórico funcional y auditoría;
- sincroniza tarea + ejecución.

ROOT/ADMIN autorizados pueden leer la evidencia por el mismo ámbito de workflow; no pueden convertirse en el autor del documento por disponer de lectura administrativa.

`anon` no tiene acceso.

## 5. Idempotencia

La misma selección/reintento conserva un `request_key`.

Un retry de preparación:

- devuelve la misma fila y ruta;
- no crea otro documento.

Un retry de confirmación:

- devuelve el resultado ya aplicado;
- no duplica eventos ni histórico.

Un mismo `request_key` no puede reutilizarse con otro archivo o documento.

## 6. Coordinación con otros pasos

Documento participa en el mismo cierre que Foto y Checklist.

Reglas:

- Foto completada + Checklist completado + Documento pendiente → ejecución activa;
- Foto completada + Documento completado + Checklist pendiente → ejecución activa;
- Checklist completado + Documento completado + Foto pendiente → ejecución activa;
- el **último requisito pendiente** decide el cierre.

Para `closeType=auto`:

- todos los pasos obligatorios completos → `completed`.

Para `closeType=human_review`:

- todos los pasos obligatorios completos → `waiting_review`.

La revisión posterior reutiliza la infraestructura ya existente de workflow; Documento no crea otra cola de revisión.

## 7. UI de Tareas

La tarjeta de una tarea muestra una sección **Documento** cuando `steps.document=true`.

El asignado puede:

- seleccionar un archivo permitido;
- reintentar la misma carga si fue interrumpida;
- adjuntar archivos adicionales mientras la tarea siga activa;
- abrir documentos ya enviados mediante URL firmada temporal.

Un gestor con lectura autorizada puede abrir documentos enviados para revisión, pero no adjuntar en nombre del asignado.

Si la receta exige Aceptar, la interfaz explica que Documento queda bloqueado hasta esa acción.

## 8. Límites deliberados de v1

No incluye todavía:

- firma electrónica;
- texto libre como sustituto de documento;
- número mínimo configurable mayor que uno;
- tipos documentales configurables por receta;
- reemplazo o borrado destructivo de evidencia enviada;
- OCR o clasificación por IA;
- vencimiento documental;
- reutilización automática de un documento de otra ejecución.

Esas capacidades solo se añadirán de forma explícita y sin reinterpretar evidencia histórica.
