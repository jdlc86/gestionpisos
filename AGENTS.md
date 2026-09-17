# AGENTS.md — Contrato obligatorio de implementación

Aplica a cualquier desarrollador, agente IA o sesión que modifique GestionPisos.

## Principios no negociables
1. ROOT es protegido: ninguna operación normal puede degradarlo, bloquearlo, eliminarlo o retirarle permisos.
2. Ningún secreto puede residir en frontend, GitHub Pages, commits, logs o documentación pública.
3. RLS es obligatoria en tablas sensibles y no puede desactivarse como atajo.
4. La autorización debe validarse en backend/base de datos; ocultar botones no es seguridad.
5. QR nunca concede acceso: solo inicia identificación/solicitud y debe ser revocable.
6. La empresa gestora es el centro documental y de comunicaciones; no hay flujo documental directo inquilino ↔ propietario.
7. Cambios de esquema se versionan como migraciones reproducibles.
8. Entidades de negocio usan soft-delete/archivado salvo excepción documentada.
9. Toda operación sensible genera auditoría.
10. Un empleado solo escribe sobre pisos autorizados.
11. Cada piso tiene un responsable operativo de escritura por defecto; delegaciones son explícitas, auditables y revocables.
12. ROOT y ADMIN requieren MFA para acciones sensibles.
13. Recuperar/cambiar contraseña invalida las demás sesiones.
14. Fotoverificación separa validación de encuadre de evaluación de estado.
15. IA no es barrera única de seguridad y su política es configurable por empresa → piso → usuario/tipo.
16. Bug relevante corregido debe añadir prueba de regresión cuando sea viable.
17. Está prohibido borrar históricos para resolver inconsistencias. Única excepción: un **factory reset explícito del entorno de prueba**, solicitado por ROOT y ejecutado mediante el helper protegido, puede purgar históricos de prueba si conserva ROOT, el operador técnico de recuperación, la configuración estructural indicada en el contrato y deja un nuevo recibo de auditoría del reset.
18. Producción puede ser entorno de prueba mientras no haya usuarios reales, manteniendo trazabilidad y reversibilidad.
19. Los correos críticos de autenticación en producción no pueden depender del SMTP incorporado de Supabase; deben usar entrega transaccional propia según `docs/AUTH_EMAIL_DELIVERY_MIGRATION.md`.
20. Un ADMIN/EMPLOYEE pendiente de onboarding no tiene rol interno ni acceso operativo activo. Solo puede adquirirlos después de verificar su correo y crear personalmente su contraseña; nunca se usan contraseñas temporales conocidas por el administrador.
21. La ficha de OWNER/TENANT y su identidad Auth son independientes hasta completar un onboarding explícito. Guardar una ficha nunca concede acceso por sí solo.
22. Mientras el modelo Auth sea de un único rol/organización principal, un email ya vinculado a otro rol o identidad no se fusiona ni reutiliza silenciosamente. El conflicto debe bloquear la activación y preservar ambas relaciones de negocio sin cruzarlas.
23. En cualquier onboarding, la autorización/vinculación se activa primero en base de datos y los claims privilegiados de Auth solo se sincronizan después del éxito DB.

## Antes de modificar autorización, datos o seguridad
Leer: `docs/SECURITY_CONTRACT.md`, `docs/PERMISSIONS_CONTRACT.md`, `docs/DATA_CONTRACT.md`, `docs/AUTH_CONTRACT.md`, `docs/AUTH_EMAIL_DELIVERY_MIGRATION.md` y `docs/EXTERNAL_ONBOARDING_CONTRACT.md` cuando aplique.

Si implementación y contrato discrepan, manda el contrato hasta que una decisión explícita lo cambie.

## Flujo
- No desarrollar directamente en `main`.
- Rama → PR → checks → revisión → merge.
- Excepción histórica: commit bootstrap necesario para inicializar el repositorio vacío.
- Riesgo: R0 visual; R1 funcional; R2 datos; R3 auth/RLS/permisos; R4 crítico.
- R3/R4 requieren pruebas negativas.

## Prohibiciones
- No usar credenciales privilegiadas en cliente.
- No desactivar RLS.
- No crear bypasses “temporales”.
- No usar QR/IDs como credencial.
- No hacer cambios manuales no reproducibles desde Git.
- No fusionar con checks críticos fallando.
- No reescribir auditoría/históricos salvo mediante el factory reset de pruebas definido y protegido; ese flujo debe crear un nuevo recibo `factory_reset_completed` tras la purga.
- No considerar apto para producción un flujo de recuperación que dependa del SMTP incorporado de Supabase o de un límite equivalente a 2 correos/hora.
- No asignar viviendas, accesos adicionales ni capacidades administrativas a personal interno cuyo onboarding siga pendiente.
- No cruzar automáticamente una identidad de personal interno con OWNER/TENANT por coincidencia de email.
