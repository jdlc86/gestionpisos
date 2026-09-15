# Contrato de producto — GestionPisos

## Propósito

GestionPisos gestiona integralmente viviendas alquiladas por habitaciones, con la empresa gestora como núcleo operativo y documental.

## Actores

- ROOT: autoridad máxima protegida.
- ADMIN: administración de la empresa gestora.
- PROPIETARIO: consulta y seguimiento de sus inmuebles.
- EMPLEADO: operación sobre pisos asignados/autorizados.
- INQUILINO: ocupación, tareas, incidencias, documentos y verificaciones.

Una misma identidad puede soportar más de un rol si el modelo futuro lo requiere.

## Jerarquía funcional

Empresa gestora → propietarios → pisos → habitaciones → ocupaciones/inquilinos.

Un propietario puede tener varios pisos. Los pisos conservan histórico de propietario, gestión y ocupación.

## Funciones núcleo

- Alta, baja lógica, bloqueo, archivo y estados de pisos/habitaciones.
- Gestión de propietarios, empleados e inquilinos.
- Check-in/check-out, inventario y evidencias.
- Solicitudes de acceso mediante QR revocable.
- Incidencias de inquilinos con texto/foto.
- Visitas de empleados y documentación fotográfica.
- Tareas de limpieza, intercambios y deuda de tareas.
- Verificación del estado del inmueble con foto patrón, silueta y revisión IA/manual.
- Solicitudes aleatorias/configurables de evidencia de zonas/equipos.
- Documentos centralizados por la gestora.
- Notificaciones internas, push PWA y email.
- Broadcast de empresa por piso, conjunto de pisos, rol o toda la organización.
- Recordatorios de pagos, impagos y reclamaciones.
- Contratos, renovaciones, vencimientos y aceptación digital.
- Mantenimiento, proveedores, SLA, prioridades y escalados.
- Calendario operativo y automatizaciones.
- Estadísticas específicas para inquilino, propietario y empresa.
- Timeline completo por piso.
- Informes PDF/Excel.
- Panel de salud, backups y recuperación.
- Operación móvil tolerante a conectividad deficiente.

## Regla de comunicación

La empresa gestora es el emisor visible de comunicaciones institucionales y broadcasts. Propietario e inquilino no mantienen un canal documental directo dentro de la plataforma.

## Estado y baja

Las bajas deben preservar histórico. El borrado físico de datos de negocio no es el mecanismo normal de baja.


## Ciclo de vida del inquilino

La identidad del inquilino se mantiene separada de sus ocupaciones históricas. Los estados visibles son **Alta**, **Suspendido** y **Baja · pendiente de eliminación**. Suspender conserva la ficha pero debe impedir el acceso. La baja inicia offboarding y no equivale a borrado inmediato. Solo una purga server-side verificada puede sustentar una comunicación final sobre qué datos fueron eliminados y cuáles deban conservarse bloqueados por obligación legal.

El dossier del inquilino admite múltiples documentos privados con nombre descriptivo y clasificación; nunca se publican mediante URL permanente.
