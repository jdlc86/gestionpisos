# Beta 0 estado

Proyecto Supabase: qsxtmmkftsohkqqmytbb
Actualizado: 2026-09-14

## Estado actual

La aplicación sigue en Beta 0 y producción se utiliza como entorno de pruebas.

El Auth mínimo de la PWA está desplegado: login email/contraseña, sesión persistida, recuperación, logout y protección de páginas. El login con el ROOT real fue probado correctamente desde móvil. La matriz multiusuario y MFA para ROOT/ADMIN siguen pendientes antes de incorporar usuarios reales.

Fotoverificación dispone ya de cámara fullscreen y alineación local probadas en móvil. La IA queda aplazada. Las migraciones remotas de alineación, restricción de ruta y retirada del RPC público, junto con el source desplegado de `submit-photo-verification`, están reconciliadas con Git. La persistencia privada de capturas sigue en curso y no debe considerarse cerrada hasta verificar el ciclo completo de captura.

No hay usuarios operativos de prueba creados todavía.

## Condición de estabilidad

No declarar Beta 0 estable hasta completar y probar las políticas v2 con identidades reales, MFA administrativo, persistencia segura de fotoverificación y los demás bloqueos registrados en docs/OPEN_BLOCKERS.md.
