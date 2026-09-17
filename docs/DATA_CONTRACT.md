# Contrato de datos

## Entidades principales

- organizations / empresa gestora
- users / perfiles
- roles y asignaciones
- owners / propietarios
- properties / pisos
- rooms / habitaciones
- tenancies / ocupaciones-contratos
- property_responsibilities / responsables y delegaciones
- access_requests / solicitudes QR
- qr_tokens / QR revocables
- documents / documentos y metadatos
- incidents / incidencias
- inspections / visitas e inspecciones
- tasks / tareas
- cleaning_swaps / cambios y deudas de limpieza
- photo_templates / patrones y siluetas versionados
- photo_verifications / evidencias y resultados
- inventory / inventario
- maintenance / mantenimiento
- payments / pagos y cargos
- claims / reclamaciones
- notifications / campanita
- broadcasts / comunicaciones programadas
- audit_log / auditoría

Los nombres finales pueden variar, pero estas responsabilidades no deben mezclarse sin una razón documentada.

## Reglas

- No guardar “inquilino actual” como único histórico: usar ocupaciones con fechas.
- No sobrescribir patrones: versionarlos.
- No borrar históricos de negocio para representar una baja.
- Documentos conservan autor, entidad, tipo, visibilidad, versión y timestamps.
- Incidencia, visita y verificación son conceptos distintos.
- Toda referencia entre empresa/piso/usuario debe poder validarse por RLS.
- Datos de prueba deben poder identificarse y limpiarse sin afectar históricos reales.

## Baseline de factory reset para pruebas

El helper de reset total existe únicamente para volver el entorno de pruebas a un baseline conocido. No sustituye a los flujos normales de baja/archivo.

El reset conserva:
- la organización activa de ROOT;
- la identidad Auth de ROOT y su acceso/rol;
- exactamente una identidad Auth técnica de operador de emergencia activa, independiente de ROOT y capaz de recuperar ROOT;
- los factores MFA de esas dos identidades;
- `platform_operators` para el operador preservado;
- plantillas estructurales/seed como `tenant_task_workflow_templates_v2`;
- un único recibo de auditoría nuevo `factory_reset_completed` posterior a la purga.

El reset elimina datos operativos de prueba: propietarios, inquilinos, pisos, habitaciones, ocupaciones, personal no protegido, onboarding, permisos/asignaciones, solicitudes, tareas, incidencias, pagos, reclamaciones, comunicaciones, notificaciones, fotoverificación/patrones, documentos/metadatos, históricos de prueba y auditoría anterior. Las identidades Auth no protegidas se eliminan después de retirar sus referencias en BD.

Storage se vacía mediante la API oficial en los buckets operativos declarados por el helper. No se borran directamente filas de `storage.objects`.


## Modelo de inquilinos v2

- `tenants_v2`: identidad estable del inquilino.
- `occupancies_v2`: estancia histórica en piso/habitación; `ends_on = NULL` representa salida indefinida.
- `tenant_documents_v2`: metadatos del dossier privado multiarchivo.
- `tenant_privacy_events_v2`: auditoría mínima del ciclo de privacidad.

La identidad no se duplica por estancia. El borrado definitivo es un workflow privilegiado y verificable, no un DELETE cliente.
