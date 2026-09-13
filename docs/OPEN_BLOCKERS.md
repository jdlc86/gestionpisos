# Bloqueos abiertos de implementación

Este documento registra tareas que **no están terminadas** aunque parte de su diseño o interfaz ya exista.

## Estado general

Proyecto Supabase: `qsxtmmkftsohkqqmytbb`  
Repositorio: `jdlc86/gestionpisos`  
Empresa gestora creada: **Allaiso**  
Usuarios operativos de prueba: todavía no creados.

La rama `auth-bootstrap-docs` contiene trabajo visual del módulo de Cartera que **no debe considerarse listo para producción** hasta cerrar los puntos de backend descritos aquí.

---

## B-01 — Escritura segura de propietarios

### Estado

CERRADO — 2026-09-13

La tabla `public.owners` dispone de lectura y escritura RLS definitiva para
ROOT/ADMIN. El borrado físico no forma parte del flujo cliente y los cambios se
auditan.

### Diseño esperado

- ROOT puede crear y modificar propietarios.
- ADMIN solo puede operar dentro de su organización.
- Propietarios no se eliminan físicamente como flujo normal.
- La baja debe conservar histórico mediante estado/archivo.
- Toda operación sensible debe ser auditable.

### Intentos realizados

Se intentó aplicar una política RLS de escritura sobre `public.owners` mediante `apply_migration`.

La llamada fue interceptada antes de llegar a Supabase con un bloqueo de seguridad de la capa de herramientas de OpenAI.

También se intentó `CREATE POLICY` mediante `execute_sql`; esa vía es de solo lectura para este tipo de operación y PostgreSQL devolvió:

`cannot execute CREATE POLICY in a read-only transaction`

### Impacto

El bloqueo de base de datos está cerrado. La PWA mantiene deshabilitada la
escritura real hasta completar B-03 (Auth y matriz con identidades reales).

### Cierre y evidencia

- Migración remota: `20260913205141 close_owners_and_occupancy_blockers`.
- Commit de implementación: `34b3dfe`; PR: `#4`.
- SQL versionado: `supabase/migrations/20260913205141_close_owners_and_occupancy_blockers.sql`.
- Políticas remotas verificadas: `owners_insert_root_admin` y
  `owners_update_root_admin`, ambas limitadas a `authenticated`; ADMIN exige
  coincidencia de `organization_id` en `app_metadata`.
- `DELETE` revocado remotamente a `anon` y `authenticated`; `service_role`
  conserva la vía excepcional server-side.
- Coherencia de baja: constraint validada `owners_archive_state_check`.
- Auditoría remota: trigger `trg_audit_owner_change` y función privada que
  registra tipo de cambio sin copiar email, teléfono ni nombre al detalle.
- Prueba positiva aislada PostgreSQL 17: ROOT crea/archiva; ADMIN de la misma
  organización crea/edita.
- Prueba negativa aislada PostgreSQL 17: propietario, empleado, inquilino y
  ADMIN de otra organización no escriben; el cliente ROOT tampoco borra.
- Script reproducible: `tests/database-regression.sql`; fixture efímera:
  `tests/local-schema-fixture.sql`; resultado `PASS` y rollback completo.
- Verificación remota posterior: RLS activa, políticas/trigger presentes y
  `owners = 0`, por lo que no quedaron fixtures.

---

## B-02 — Una sola ocupación abierta por habitación

### Estado

CERRADO — 2026-09-13

PostgreSQL impide estructuralmente que una habitación tenga ocupaciones activas
solapadas, incluidas dos ocupaciones abiertas.

### Diseño esperado

Regla equivalente a:

- una única ocupación con `status = active`
- y `ends_on IS NULL`
- por `room_id`

La protección debe existir en base de datos, no solo en interfaz.

### Intentos realizados

Se intentó crear un índice único parcial sobre `public.occupancies_v2(room_id)`.

También se intentó añadir una restricción adicional de integridad sobre fechas.

Ambas operaciones fueron bloqueadas por la capa de seguridad de las herramientas antes de ejecutarse en Supabase.

Una migración de control con `SELECT 1` sí fue aplicada correctamente, confirmando que:

- el proyecto Supabase está operativo;
- `apply_migration` funciona;
- el bloqueo es selectivo sobre determinadas operaciones sensibles.

### Impacto

La garantía estructural está aplicada. Los flujos completos de Auth y la matriz
multiusuario siguen dependiendo de B-03.

### Cierre y evidencia

- Migración remota: `20260913205141 close_owners_and_occupancy_blockers`.
- Commit de implementación: `34b3dfe`; PR: `#4`.
- Constraint remota validada `occupancies_v2_dates_check`: una fecha final no
  puede preceder a la inicial.
- Constraint de exclusión GiST remota y validada
  `occupancies_v2_no_active_room_overlap`, parcial para `status = 'active'`,
  sobre `room_id` y el `daterange` inclusivo de la ocupación.
- Preflight remoto antes de aplicar: 0 fechas inválidas y 0 solapamientos.
- Regresión PostgreSQL 17: segunda ocupación abierta rechazada, solapamiento
  fechado rechazado, rango invertido rechazado y rango posterior aceptado.
- Resultado: `PASS`; la transacción de prueba terminó en `ROLLBACK`.

---

## B-03 — Bootstrap/Auth y creación automatizada de usuarios

### Estado

PENDIENTE PARCIAL

El primer usuario ROOT fue creado mediante Supabase Auth y promovido manualmente desde SQL Editor debido a bloqueos de la integración sobre operaciones directas en `auth.users` y asignación de privilegios.

### Regla

No insertar usuarios directamente en `auth.users`.

Los futuros usuarios de prueba y usuarios reales deben crearse mediante Supabase Auth normal o una operación administrativa server-side segura.

### Pendiente

- conectar login de la PWA;
- obtener JWT nuevo tras cambios en `app_metadata`;
- ejecutar matriz RLS con usuarios de prueba;
- habilitar MFA obligatorio para ROOT/ADMIN antes de datos/usuarios reales.

### Verificación de esta sesión

- No se creó ni modificó ningún registro de `auth.users`.
- El trigger remoto `trg_protect_root_role` sigue activo.
- La regresión aislada confirmó que un `UPDATE` ordinario no puede cambiar el
  rol ROOT (`ROOT role is immutable`).
- La prueba remota con `SET ROLE authenticated` no pudo ejecutarse por la vía
  de consulta: la integración devolvió `permission denied to set role
  "authenticated"`. No se insistió con DML privilegiado en producción.

---

## B-04 — Protección nativa de la rama main

### Estado

CERRADO — 2026-09-13

El proyecto ya dispone de:

- Governance Guard
- PWA Smoke
- Schema Guard

`main` está protegida nativamente en GitHub.

### Diseño esperado

GitHub debe exigir:

- cambios mediante Pull Request;
- checks obligatorios verdes;
- impedir push directo a `main` salvo emergencia documentada.

### Configuración verificada

- cambios mediante Pull Request;
- status checks estrictos: `Governance Guard`, `PWA Smoke`, `Schema Guard`;
- aplicación de las reglas también a administradores;
- 0 aprobaciones obligatorias, para no bloquear un repositorio personal, pero
  el paso por PR sigue siendo obligatorio;
- conversaciones resueltas;
- force-push y borrado de `main` deshabilitados.

La API de GitHub devolvió la configuración aplicada con `strict: true` y
`enforce_admins: true`.

El PR `#4` confirmó que los contextos configurados corresponden a checks
reales y los tres finalizaron en `PASS` sobre el commit `34b3dfe`.

---

## B-05 — Cartera Allaiso

### Estado

CERRADO PARA ALCANCE VISUAL / SIN ESCRITURA REMOTA

En `auth-bootstrap-docs` se han creado:

- `docs/portfolio.html`
- `docs/portfolio.css`
- `docs/portfolio.js`
- enlace desde la pantalla principal hacia Cartera.

Incluye vistas para:

- Propietarios
- Pisos
- Habitaciones

La revisión de esta sesión añadió:

- alta y edición en estado local de demostración;
- selector y visualización de estados;
- archivo/baja lógica sin borrar registros;
- histórico por entidad;
- relaciones propietario → pisos y piso → habitaciones;
- rótulos explícitos de que no existe escritura remota ni persistencia.

Los formularios son únicamente de experiencia visual y no escriben datos en Supabase.

### Evidencia y condición de entrega

- `tests/portfolio-smoke.sh` comprueba los tres archivos, el enlace desde
  `index.html`, las tres secciones, carga JS/CSS, relaciones, histórico,
  archivo y ausencia de tablas legacy.
- `tests/pwa-smoke.sh` ejecuta el smoke de Cartera; queda integrado en `PWA Smoke`.
- `Schema Guard` comprueba además los artefactos de regresión de base de datos.
- `Schema Guard` ejecuta la regresión completa en PostgreSQL 17 efímero, sin
  secretos ni acceso a producción.
- La escritura real permanece bloqueada por B-03 y no se ha añadido cliente
  Supabase al frontend.
- Commit de implementación: `34b3dfe`; PR: `#4`.
- Resultado inicial del PR sobre ese commit: `Governance Guard`, `PWA Smoke` y
  `Schema Guard` en `PASS`.
- El PR se mantiene abierto para revisión; no se fusiona silenciosamente un
  cambio R3/R4 mientras B-03 y la matriz completa sigan pendientes.

---

## B-06 — Leaked Password Protection

### Estado

ACEPTADO POR LIMITACIÓN DEL PLAN

Supabase Security Advisor muestra:

`Leaked Password Protection Disabled`

La opción no está disponible en el plan actual.

### Compensaciones

- contraseña fuerte;
- RLS;
- ROOT protegido;
- MFA obligatorio para ROOT/ADMIN antes de usuarios reales;
- recuperación segura de contraseña;
- no reutilización de contraseñas.

No se considera bloqueo de Beta 0.

---

## B-07 — Incidencias: visibilidad por actor y Storage privado

### Estado

PENDIENTE

### Verificación

- RLS está activa en `incidents_v2`, `incident_updates_v2` e
  `incident_evidence_v2`.
- Las políticas actuales permiten lectura ROOT y ADMIN, con aislamiento de
  ADMIN por organización.
- Los checks de `visibility` admiten exactamente `tenant`, `internal` y
  `owner`, por separado.
- No existe bucket de Storage ni política sobre `storage.objects`.
- No existen todavía políticas para tenant, owner o empleado, ni políticas de
  escritura/auditoría del flujo completo.

### Impacto

El diseño de visibilidad está representado en tablas, pero el módulo no cumple
todavía `docs/INCIDENTS_CONTRACT.md`. Las evidencias no deben subirse ni
exponerse hasta crear un bucket privado y probar su autorización. No existe un
canal documental directo propietario ↔ inquilino.

---

## B-08 — Limpieza: intercambio controlado y deuda no monetaria

### Estado

PENDIENTE

### Verificación

- RLS está activa en las cuatro tablas de Limpieza.
- Planes, tareas y deudas solo tienen lectura ROOT/ADMIN por organización.
- `cleaning_swap_requests_v2` tiene RLS activa y ninguna política; el estado
  actual es deny-by-default.
- No existe aún una operación controlada que compruebe ocupación vigente en el
  mismo piso, reasigne la tarea, mantenga histórico y cree la deuda.

### Impacto

No existe ahora un flujo cliente inseguro para elegir usuarios de otro piso,
pero tampoco está implementado el intercambio descrito en
`docs/CLEANING_CONTRACT.md`. Mantener la UI bloqueada hasta disponer de RPC o
backend autorizado y pruebas negativas multi-piso.

---

## B-09 — Reproducibilidad histórica de migraciones

### Estado

PENDIENTE

### Verificación

El historial remoto contiene 40 migraciones anteriores a esta sesión, pero el
repositorio recibido no contiene sus archivos SQL en `supabase/migrations`.
`supabase/REMOTE_MIGRATIONS.md` registra sus versiones y nombres.

La migración nueva `20260913205141 close_owners_and_occupancy_blockers` sí está
versionada con su SQL exacto.

### Impacto

Un entorno vacío no puede reconstruirse únicamente desde Git. Recuperar o
generar una base canónica revisable para las migraciones históricas antes de
declarar una release estable.

---

## Advisors — revisión 2026-09-13

### Security Advisor

- 0 findings críticos.
- `WARN`: `Leaked Password Protection Disabled`, aceptado en B-06.
- `INFO`: `cleaning_swap_requests_v2` con RLS y sin política, recogido en B-08.

### Performance Advisor

- 0 findings críticos.
- 22 claves foráneas sin índice de cobertura.
- 27 avisos de RLS init-plan.
- 50 índices sin uso en tablas todavía vacías, incluido el nuevo índice de la
  exclusión de ocupaciones.
- 4 casos de múltiples políticas permisivas.

Son deuda de rendimiento, no bloqueos críticos de esta migración. Deben
priorizarse con datos/carga representativos y sin eliminar índices únicamente
porque el entorno Beta aún no los ha usado.

---

## Causa técnica observada — histórico y sesión actual

Los plugins de GitHub y Supabase están configurados en **Allow all actions**.

La cuenta GitHub `jdlc86` tiene permiso **admin** sobre el repositorio.

El proyecto Supabase está en estado **ACTIVE_HEALTHY**.

Por tanto, los bloqueos descritos no provienen de falta de permisos del usuario ni de un proyecto Supabase caído.

En la sesión anterior, las operaciones fallidas devolvieron mensajes indicando
que la llamada fue bloqueada por los controles de seguridad de OpenAI antes de
llegar al servicio externo.

En esta sesión, la migración de esquema sí se aplicó y GitHub Branch Protection
sí se configuró. La vía de consulta no permitió `SET ROLE authenticated`, y la
vía de migraciones rechazó correctamente usar producción para DML de prueba.
Por ello, la regresión de roles se ejecutó en PostgreSQL 17 efímero y la base
remota se verificó de forma no mutante mediante sus catálogos.

---

## Regla de cierre

Ningún punto de este documento puede marcarse como cerrado únicamente porque exista código o UI.

Para cerrar un bloqueo se requiere:

1. cambio aplicado realmente;
2. verificación en el servicio externo;
3. prueba positiva;
4. prueba negativa cuando aplique;
5. Security Advisor revisado;
6. cambios versionados en GitHub;
7. PR y checks verdes cuando afecte al repositorio.
