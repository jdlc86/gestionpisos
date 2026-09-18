# Contrato de historial de migraciones Supabase

## Objetivo

Mantener una única historia reproducible entre Git y la tabla remota `supabase_migrations.schema_migrations`.

La regla es:

`supabase/migrations/<version>_<name>.sql` ↔ `schema_migrations(version,name)`

Una migración que ya fue aplicada remotamente conserva para siempre su `version` y su nombre histórico.

## Fuente de verdad

- Antes de desplegar una migración nueva, Git es la fuente de verdad.
- Después de que esa migración queda registrada por Supabase, su versión remota pasa a formar parte del historial inmutable que Git debe conservar.
- El contenido histórico recuperado de `schema_migrations.statements` puede usarse para reconstruir Git cuando exista drift probado.
- Un baseline consolidado de pruebas no sustituye al historial real de migraciones.

El antiguo baseline consolidado del 13 de septiembre se conserva como fixture en:

`tests/fixtures/20260913_remote_baseline.sql`

y no pertenece a `supabase/migrations`.

## Reglas obligatorias

1. No renombrar ni cambiar el timestamp de una migración después de que haya sido aplicada.
2. No reutilizar un timestamp para dos migraciones distintas.
3. No crear cambios de esquema manualmente en Dashboard/SQL Editor salvo recuperación excepcional documentada.
4. Una aplicación excepcional directa debe reconciliarse inmediatamente en Git con la versión y SQL realmente registrados.
5. `supabase db push --dry-run` debe poder comparar historia local/remota antes del despliegue.
6. `supabase db push` es la ruta normal de despliegue desde `main`.
7. `migration repair` solo puede tocar historial después de demostrar cuál de los dos lados es incorrecto. Está prohibido ejecutar reparaciones masivas `--status reverted` como forma de silenciar drift.
8. No borrar una migración histórica aplicada para sustituirla por un archivo distinto.
9. Los fixtures de tests pueden consolidar esquema, pero deben vivir fuera de `supabase/migrations`.
10. Todo cambio que altere migraciones requiere Schema Guard y los guards obligatorios antes de merge.

## Drift histórico corregido el 18 de septiembre de 2026

Se detectó:

- 155 migraciones registradas remotamente;
- 94 archivos locales;
- 113 versiones remotas sin fichero local;
- 51 versiones locales no presentes remotamente;
- numerosos cambios equivalentes con el mismo nombre y timestamp diferente.

La reconciliación segura consistió en:

1. leer el historial remoto y sus `statements`;
2. comprobar que no contenía correos ni credenciales literales;
3. reconstruir `supabase/migrations` con las 155 versiones remotas reales;
4. retirar 52 rutas locales que no pertenecían al historial remoto;
5. conservar el antiguo baseline solo como fixture de regresión;
6. actualizar las referencias de tests a los timestamps canónicos;
7. no modificar `supabase_migrations.schema_migrations` ni ejecutar `migration repair`.

Criterio de cierre: el conjunto local de rutas de migración debe coincidir exactamente con el conjunto remoto y el workflow de Supabase debe superar el dry-run antes del push.

## Procedimiento para una migración nueva

1. Crear el archivo versionado en una rama.
2. Ejecutar regresiones locales/Schema Guard.
3. Abrir PR y esperar guards.
4. Fusionar solo en verde.
5. CI ejecuta `db push --dry-run`.
6. Si el dry-run es correcto, CI ejecuta `db push`.
7. Si alguna herramienta excepcional registra una versión remota distinta, reconciliar el filename en una PR inmediata antes de continuar con más DDL.
