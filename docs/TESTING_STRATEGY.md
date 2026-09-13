# Estrategia obligatoria de pruebas

## Capas

1. Unitarias: reglas de negocio, estados, permisos y selección de políticas.
2. Integración: Supabase Auth, RLS, Storage, funciones, notificaciones y auditoría.
3. Seguridad: intentos prohibidos y aislamiento entre recursos.
4. E2E: recorridos completos por rol.
5. Smoke: validación rápida tras despliegue.

## Golden path

ADMIN → propietario → piso → habitación → ocupación → QR → solicitud → aprobación → activación → login → tarea/verificación → incidencia → empleado → propietario consulta.

Debe permanecer automatizado cuando exista frontend funcional.

## Pruebas negativas mínimas

- inquilino A no ve piso B;
- propietario A no ve recursos de propietario B;
- empleado sin permiso no escribe piso ajeno;
- ADMIN no modifica ROOT;
- usuario bloqueado no opera;
- QR revocado no inicia acceso válido;
- sesión antigua queda inutilizada tras recuperación/cambio de contraseña;
- URL de Storage caducada no accede;
- cliente no puede elevar rol;
- acceso directo por API no evade permisos.

## Regla de regresión

Todo defecto relevante corregido debe incorporar prueba reproducible cuando sea viable.

## Criterio de merge

Un check crítico fallando bloquea merge. R3/R4 requieren pruebas negativas relacionadas con el cambio.
