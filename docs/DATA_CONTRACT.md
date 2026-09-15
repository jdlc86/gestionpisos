# Contrato de datos

## Entidades principales

- organizations / empresa gestora
- users / perfiles
- roles y asignaciones
- owners / propietarios
- properties / pisos
- rooms / habitaciones
- tenants_v2 / identidad estable del inquilino
- occupancies_v2 / ocupaciones-contratos
- tenant_documents_v2 / dossier documental privado del inquilino
- tenant_privacy_events_v2 / auditoría mínima del ciclo de privacidad
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
- La identidad del inquilino no se duplica por cada estancia: `tenants_v2` se relaciona con `occupancies_v2`.
- Una ocupación con salida indefinida usa `ends_on = NULL`; la UI debe deshabilitar Fecha de salida mientras Indefinido esté activo.
- Los documentos del inquilino viven en bucket privado y su metadata en `tenant_documents_v2`; nunca usar URL pública.
- El borrado definitivo del inquilino es un workflow privilegiado y verificable, no un DELETE cliente.
- No sobrescribir patrones: versionarlos.
- No borrar históricos de negocio para representar una baja.
- Documentos conservan autor, entidad, tipo, visibilidad, versión y timestamps.
- Incidencia, visita y verificación son conceptos distintos.
- Toda referencia entre empresa/piso/usuario debe poder validarse por RLS.
- Datos de prueba deben poder identificarse y limpiarse sin afectar históricos reales.
