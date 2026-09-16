# Migración profesional del correo de autenticación

## Decisión

GestionPisos no puede depender en producción del SMTP incorporado de Supabase para recuperación de contraseña, activaciones, invitaciones ni otros correos críticos de autenticación.

El SMTP incorporado se considera únicamente una ayuda de desarrollo/pruebas. En el momento de esta decisión se ha observado un límite operativo de 2 correos/hora, insuficiente para un servicio real. Aunque Supabase cambie ese límite en el futuro, esta decisión arquitectónica se mantiene: **producción debe usar un proveedor de correo controlado por el proyecto**.

Arquitectura objetivo:

- Supabase Auth continúa generando y validando tokens, sesiones y enlaces de recuperación.
- El envío de email se realiza mediante SMTP personalizado.
- Proveedor preferido inicial: **Resend**, sin acoplar la lógica de aplicación al proveedor.
- Evolución futura, si se necesita redundancia/colas/failover: Supabase Send Email Auth Hook con proveedor primario y secundario.

## Objetivos

1. Eliminar la dependencia del límite del SMTP incorporado de Supabase.
2. Mantener el flujo seguro de recuperación de Supabase Auth.
3. Usar dominio/remitente de la empresa con buena entregabilidad.
4. Disponer de límites configurables, observabilidad y protección antiabuso.
5. Evitar que un fallo del proveedor de email obligue a degradar la seguridad.

## Flujo de recuperación objetivo

1. Usuario pulsa `He olvidado mi contraseña`.
2. La aplicación solicita a Supabase Auth un enlace de recuperación para el email introducido.
3. La respuesta visible es neutra y no confirma si la cuenta existe.
4. Supabase genera un token/enlace de un solo uso.
5. El proveedor SMTP personalizado envía el correo.
6. El enlace vuelve exclusivamente a la URL de recuperación de producción.
7. La página valida que existe una sesión de recuperación válida antes de permitir cambiar la contraseña.
8. Usuario introduce y confirma la nueva contraseña.
9. Se actualiza la contraseña mediante Supabase Auth.
10. Se invalidan las demás sesiones conforme al contrato de autenticación.
11. El usuario vuelve al login.

## Configuración obligatoria antes de producción

### Supabase Auth

- `Site URL`: URL real de producción. No puede quedar `localhost`.
- `Redirect URL` de recuperación: ruta exacta de `reset-password.html` en producción.
- SMTP personalizado habilitado.
- Rate limits revisados explícitamente tras activar SMTP personalizado.
- El frontend no contiene claves SMTP ni secretos del proveedor.

### Dominio de correo

Usar un remitente transaccional dedicado, por ejemplo:

- `no-reply@auth.<dominio-empresa>`

Configurar y verificar:

- SPF
- DKIM
- DMARC

El dominio/remitente de autenticación debe mantenerse separado, cuando sea viable, del correo de marketing.

## Política de rate limiting

El límite de correo de producción no puede depender del valor del SMTP incorporado de Supabase.

Política inicial recomendada:

- límite global configurable según la capacidad contratada del proveedor;
- objetivo inicial de referencia: **100 correos de autenticación/hora** para primeras pruebas reales, ajustable por telemetría y plan del proveedor;
- intervalo mínimo por usuario para recuperación: aproximadamente 60 s o superior;
- el navegador nunca reintenta automáticamente múltiples envíos;
- ante abuso, incorporar CAPTCHA y/o controles adicionales antes de subir límites.

Criterio de aceptación: **un entorno que siga limitado por el SMTP incorporado de Supabase o por un techo equivalente a 2 correos/hora no se considera apto para producción**.

## Proveedor preferido inicial: Resend

Motivos:

- integración SMTP simple con Supabase Auth;
- orientado a correo transaccional;
- soporte de dominio autenticado;
- permite sustituir el transporte sin cambiar el flujo de Auth de la aplicación.

La selección del proveedor no debe aparecer codificada en el frontend. Debe ser una configuración de infraestructura de Supabase.

## Migración sin pérdida de servicio

1. Crear/configurar la cuenta del proveedor SMTP.
2. Verificar el dominio/remitente y completar SPF/DKIM/DMARC.
3. Corregir `Site URL` y `Redirect URLs` de Supabase Auth.
4. Configurar las credenciales SMTP en Supabase Authentication > Emails > SMTP Settings.
5. Enviar un correo de prueba al equipo.
6. Configurar los rate limits de Auth para la capacidad real del proveedor.
7. Ejecutar pruebas E2E de recuperación.
8. Verificar logs/errores y que no aparece ningún redirect a `localhost`.
9. Marcar el SMTP incorporado como no válido para producción.

## Pruebas obligatorias

Antes de considerar cerrada la migración deben pasar al menos estos casos:

- cuenta existente recibe enlace y cambia contraseña;
- email inexistente obtiene respuesta neutra;
- enlace usado una vez no puede reutilizarse;
- enlace caducado se rechaza con mensaje claro;
- redirect final apunta a producción, nunca a `localhost`;
- nueva contraseña permite login;
- contraseña anterior deja de funcionar;
- otras sesiones quedan invalidadas según política;
- dos solicitudes seguidas demasiado rápidas activan el control antiabuso esperado;
- múltiples recuperaciones de usuarios distintos no quedan bloqueadas por un límite global de 2/h;
- fallo SMTP se muestra como indisponibilidad temporal sin revelar existencia de cuentas;
- móvil y navegador de escritorio completan el flujo.

## Observabilidad

Registrar/monitorizar, sin almacenar tokens ni secretos:

- solicitudes de recuperación;
- errores/429;
- entregas fallidas del proveedor;
- rechazos/bounces relevantes;
- recuperaciones completadas;
- latencia aproximada de entrega;
- cambios de configuración de Auth cuando sea auditable.

Un aumento sostenido de 429 o fallos de entrega debe tratarse como incidente operativo.

## Resiliencia futura

Cuando el volumen o criticidad lo justifique, migrar del SMTP simple a `Send Email Auth Hook` para poder:

- usar colas;
- aplicar filtrado adicional;
- usar un proveedor secundario de respaldo;
- implementar failover controlado;
- observar y clasificar mejor los fallos de entrega.

El SMTP incorporado de Supabase **no** se considera un mecanismo profesional de failover.

## Estado actual

- Flujo frontend/backend de recuperación: implementado.
- Página de nueva contraseña: implementada.
- Redirección de recuperación de producción: debe quedar configurada en Supabase Auth.
- Migración a SMTP personalizado: **pendiente y bloqueante antes de usuarios reales**.

No se debe declarar el sistema de recuperación como listo para producción hasta completar y validar esta migración.