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

PENDIENTE / BLOQUEADO

La tabla `public.owners` dispone de política de lectura, pero no se pudo aplicar la política definitiva de alta/edición para ROOT/ADMIN.

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

No debe habilitarse en la PWA la escritura real de propietarios hasta cerrar este punto.

---

## B-02 — Una sola ocupación abierta por habitación

### Estado

PENDIENTE / BLOQUEADO

Se necesita impedir estructuralmente que una habitación tenga dos ocupaciones activas simultáneas.

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

No declarar cerrado el flujo de ocupaciones hasta que esta regla exista y sea probada.

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

---

## B-04 — Protección nativa de la rama main

### Estado

PENDIENTE

El proyecto ya dispone de:

- Governance Guard
- PWA Smoke
- Schema Guard

Sin embargo, `main` aparece actualmente como rama no protegida en GitHub.

### Diseño esperado

GitHub debe exigir:

- cambios mediante Pull Request;
- checks obligatorios verdes;
- impedir push directo a `main` salvo emergencia documentada.

### Causa

La conexión GitHub disponible permite operaciones normales del repositorio y la cuenta tiene permiso `admin`, pero no se dispone de una acción autorizada para configurar Branch Protection/Rulesets desde esta sesión.

### Impacto

Los contratos se están respetando por proceso, pero GitHub todavía no los impone técnicamente.

---

## B-05 — Cartera Allaiso

### Estado

IMPLEMENTACIÓN VISUAL EN RAMA / NO FUSIONADA

En `auth-bootstrap-docs` se han creado:

- `docs/portfolio.html`
- `docs/portfolio.css`
- `docs/portfolio.js`
- enlace desde la pantalla principal hacia Cartera.

Incluye vistas para:

- Propietarios
- Pisos
- Habitaciones

Los formularios son únicamente de experiencia visual y no escriben datos en Supabase.

### Motivo de no fusión

No debe llegar a `main` hasta cerrar:

1. B-01 escritura segura de propietarios;
2. B-02 unicidad de ocupación abierta;
3. actualización del smoke test;
4. PR con Governance Guard, PWA Smoke y Schema Guard verdes.

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

## Causa técnica observada

Los plugins de GitHub y Supabase están configurados en **Allow all actions**.

La cuenta GitHub `jdlc86` tiene permiso **admin** sobre el repositorio.

El proyecto Supabase está en estado **ACTIVE_HEALTHY**.

Por tanto, los bloqueos descritos no provienen de falta de permisos del usuario ni de un proyecto Supabase caído.

Las operaciones fallidas devuelven explícitamente mensajes indicando que la llamada fue bloqueada por los controles de seguridad de OpenAI antes de llegar al servicio externo.

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
