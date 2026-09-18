# Contrato de release

Toda publicación requiere revisión, checks verdes, cambios reproducibles, pruebas relevantes superadas, riesgos conocidos documentados y un punto de rollback identificado.

La secuencia objetivo es: contratos, unitarias, integración, seguridad, E2E, smoke y release.

Mientras no haya usuarios reales, el entorno actual puede utilizarse para validación controlada. Antes del primer usuario externo debe declararse un punto estable y revisarse la separación de entornos.


## Verificación posterior para cambios R3/R4

Cuando una release modifica Auth, permisos, RLS, onboarding, migraciones o Edge Functions, el merge verde no basta por sí solo.

Después de `main` debe verificarse:

- que la migración canónica aparece en `supabase_migrations.schema_migrations`;
- que las columnas/triggers/RPC esperados existen realmente en el proyecto remoto;
- que cada Edge Function afectada está `ACTIVE` y contiene la versión desplegada esperada;
- que las invariantes de datos críticas no presentan deriva en producción;
- que no se despliega una Edge Function que dependa de un esquema todavía no aplicado.

Si una comprobación remota no puede ejecutarse desde el entorno disponible, debe quedar explícitamente indicada como **no verificada**, nunca asumida.
