# Factory reset del entorno de pruebas

Este helper devuelve GestionPisos a un baseline técnico conocido sin reconstruir el proyecto ni tocar esquema, Edge Functions o configuración de autenticación.

## Qué conserva

- la organización activa de ROOT;
- el usuario Auth ROOT, su perfil, rol y MFA;
- exactamente un operador técnico activo con `can_recover_root=true`, su usuario Auth y MFA;
- la fila `platform_operators` del operador protegido;
- plantillas estructurales como `tenant_task_workflow_templates_v2`;
- un recibo nuevo `factory_reset_completed` después de la purga.

## Qué elimina

- todos los usuarios Auth que no sean ROOT ni el operador protegido;
- personal interno, onboarding, permisos, capacidades y solicitudes;
- propietarios, inquilinos, pisos, habitaciones y ocupaciones;
- documentos/metadatos de inquilino;
- tareas, incidencias, pagos, reclamaciones, notificaciones y comunicaciones;
- patrones y ejecuciones de fotoverificación;
- auditoría histórica de pruebas;
- objetos de los buckets operativos `photo-verification` y `tenant-documents-v2` mediante la API oficial de Storage.

## Barreras de seguridad

La Edge Function `factory-reset-test-data` exige:

1. sesión autenticada;
2. rol exacto `root`;
3. `aal2` (MFA completado);
4. exactamente un operador activo capaz de recuperar ROOT;
5. MFA verificado en ese operador;
6. una fase `preview` que genera una confirmación firmada válida durante 5 minutos;
7. una fase `execute` con confirmación explícita;
8. verificación final de que quedan exactamente dos usuarios Auth: ROOT y el operador técnico.

El navegador nunca recibe la service role key. La mutación de base de datos se hace mediante `factory_reset_test_data_service`, RPC disponible únicamente para `service_role`.

## Uso desde la aplicación

Abrir `factory-reset.html` con la sesión ROOT ya iniciada y MFA completado. La página no está enlazada en la navegación normal y tiene `noindex`.

1. Pulsar **Preparar restablecimiento**.
2. Revisar los dos usuarios que serán preservados y los buckets que se vaciarán.
3. Marcar que el entorno solo contiene datos de prueba.
4. Escribir `RESTABLECER`.
5. Confirmar el diálogo destructivo.

Si falla Storage, no se inicia la limpieza de base de datos. Si el fallo ocurre después de limpiar la base de datos, el helper devuelve un estado parcial y puede ejecutarse de nuevo: el procedimiento es idempotente.

## Restricción de ciclo de vida

Este helper existe mientras GestionPisos se utilice como entorno de pruebas sin usuarios/datos reales. Antes de una puesta en producción real debe deshabilitarse, retirarse de la interfaz o sustituirse por procedimientos de retención/borrado específicos. No debe utilizarse como mecanismo normal de baja de usuarios ni como solución a inconsistencias de datos.
