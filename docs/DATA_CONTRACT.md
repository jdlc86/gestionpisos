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
