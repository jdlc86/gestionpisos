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
- invitación OWNER/TENANT pendiente no puede conservar estado válido tras cambiar el email sin revocación;
- ADMIN/EMPLOYEE no puede reenviar ni activar si `invitation_email`, perfil y Auth difieren;
- operador de emergencia no puede usar la consola si `identity_email` y Auth difieren;
- una deriva de email de operador debe permitir contención/desactivación, pero no reactivación o elevación de capacidades.

## Infraestructura de QA masivo

GestionPisos tiene reservado `jdlc86/Allaiso-QA-Orchestrator` como repositorio canónico de la futura plataforma de orquestación de pruebas a gran escala.

El objetivo de esa plataforma es permitir alto volumen de E2E reales, paralelización, variantes combinatorias y evidencias reproducibles sin trasladar al repositorio del producto la infraestructura de ejecución.

La ruta pública de solo lectura ya está operativa y verificada mediante el runner `allaiso-qa-JDIA` y OpenClaw. El estado y el vínculo oficial se mantienen en `QA_ORCHESTRATION_LINK.md`. La autenticación y las escrituras E2E siguen sin activarse; por tanto, el smoke público no sustituye los Gates autenticados ni permite marcar como PASS los casos de la batería final.

## Regla de regresión

Todo defecto relevante corregido debe incorporar prueba reproducible cuando sea viable.

## Criterio de merge

Un check crítico fallando bloquea merge. R3/R4 requieren pruebas negativas relacionadas con el cambio.
