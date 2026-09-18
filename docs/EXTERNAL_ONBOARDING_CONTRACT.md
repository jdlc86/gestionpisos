# Contrato de bienvenida y activación de propietarios e inquilinos

## Separación entre ficha de negocio e identidad Auth

Un propietario o inquilino puede existir en Cartera sin tener cuenta de acceso. Guardar la ficha **no crea ni concede acceso automáticamente**.

La bienvenida es una acción explícita y separada:

- `Guardar sin enviar` conserva únicamente la ficha de negocio.
- `Guardar y enviar bienvenida` prepara una identidad Auth pendiente y solicita el correo profesional de activación.
- Las tarjetas de propietario/inquilino permiten enviar o reenviar la bienvenida posteriormente.

## Estados

- **Sin invitación**: existe la ficha, pero no existe onboarding Auth actual.
- **Pendiente de activación**: existe identidad Auth sin contraseña definida por terceros y sin rol/acceso externo activo.
- **Correo pendiente / envío no confirmado**: la identidad sigue pendiente; nunca se concede acceso por un fallo de entrega.
- **Acceso activado**: el usuario verificó su correo, creó su propia contraseña y se completó la vinculación autoritativa.

## Flujo de activación

1. Un actor autorizado solicita la bienvenida desde Cartera.
2. Backend valida organización, sujeto, email y permisos del actor.
3. Backend rechaza conflictos de identidad antes de crear o reutilizar Auth.
4. Se crea una identidad Auth sin contraseña conocida por el gestor y un onboarding `pending`.
5. Se genera un enlace de un solo uso en backend y se entrega por el proveedor transaccional profesional; el SMTP incorporado de Supabase no es dependencia de producción.
6. El correo pasa por una landing de confirmación humana antes del enlace Auth para reducir consumo automático por escáneres.
7. El usuario crea una contraseña de al menos 12 caracteres.
8. Backend vincula primero la identidad a la ficha y activa el rol DB (`owner` o `tenant`).
9. Solo después del éxito DB se publican `app_metadata.role` y `app_metadata.organization_id` mediante una Edge Function privilegiada.
10. La sesión de activación se cierra y el usuario vuelve a iniciar sesión para obtener un JWT nuevo.

El orden DB → Auth claims es obligatorio. Un fallo de sincronización de claims puede denegar temporalmente el acceso, pero nunca debe conceder permisos antes de la vinculación autoritativa.

## Alcance por tipo de usuario

### Propietario

- La bienvenida solo puede enviarla ROOT o el ADMIN que tenga el control administrativo de escritura.
- Al activar, `owners.user_id` queda vinculado a la identidad Auth.
- Las políticas existentes de propietarios/pisos/habitaciones usan esa vinculación para el acceso de lectura correspondiente.
- Un propietario sin email no puede recibir bienvenida hasta completar su ficha.

### Inquilino

- ROOT o el ADMIN autorizado pueden enviar la bienvenida.
- Un EMPLOYEE puede hacerlo únicamente para un inquilino asociado a una vivienda sobre la que tenga permiso operativo de escritura.
- Al activar, `tenants_v2.user_id` y las ocupaciones de ese inquilino se vinculan a la identidad Auth sin sobrescribir identidades ajenas.
- El inquilino obtiene lectura de su propia identidad y documentación conforme a RLS; ampliar otros módulos requiere políticas específicas y no se presupone por el simple onboarding.

## Regla anti-cruce de identidades

El modelo actual publica un único `role` y una única `organization_id` en `app_metadata`. Por tanto, **no se fusionan silenciosamente identidades con roles distintos**.

Mientras no exista un modelo multirol explícito:

- un email de ADMIN/EMPLOYEE no puede reutilizarse para crear acceso de OWNER/TENANT;
- un email de OWNER no puede reutilizarse como TENANT ni viceversa;
- una cuenta Auth existente sin relación verificable con el sujeto provoca conflicto y no se adopta;
- el conflicto se muestra al gestor y no modifica ninguna relación de negocio.

Esta regla es especialmente importante porque una misma dirección de email puede aparecer accidentalmente en fichas distintas durante pruebas o importaciones.

## Cambio de email con invitación pendiente

El email de la ficha y el email de la identidad pendiente deben representar la misma intención de acceso.

Si una ficha OWNER/TENANT tiene una invitación `pending` y el gestor intenta cambiar su email:

1. la interfaz debe advertir qué dirección recibió la invitación anterior;
2. el gestor debe confirmar explícitamente el cambio;
3. la identidad Auth pendiente anterior se deshabilita mediante backend privilegiado;
4. solo después se marca el onboarding anterior como `revoked`, conservando histórico y auditoría;
5. el cambio de email de la ficha queda permitido;
6. la tarjeta pasa a **Sin invitación** / **Email cambiado · nueva invitación necesaria**;
7. una nueva bienvenida crea una nueva identidad pendiente para el email actual.

La invitación anterior nunca se considera transferida al nuevo email.

Un trigger de base de datos impide cambiar directamente el email mientras exista un onboarding `pending` o `active` sin resolver. Así, saltarse la UI no puede dejar la ficha apuntando a un email distinto del acceso pendiente.

Si el onboarding ya está `active`, el email de acceso **no puede cambiarse desde la edición ordinaria de Cartera**. Ese caso requiere un flujo específico de cambio de identidad/cuenta para no romper la relación Auth ya activa.

Para inconsistencias históricas donde la ficha ya cambió pero el onboarding todavía apunta al email antiguo, la tarjeta debe mostrar **Email cambiado · nueva invitación necesaria**. Al enviar una nueva bienvenida, el backend revoca primero la identidad pendiente antigua y después prepara la nueva.

## Entrega y antiabuso

- Proveedor inicial preferido: Resend.
- Secretos: `RESEND_API_KEY` y `AUTH_EMAIL_FROM`, solo en backend.
- Cooldown mínimo actual de reenvío: 60 s por onboarding.
- SPF, DKIM y DMARC son obligatorios antes de usuarios reales.
- `not_configured` o fallo del proveedor deja la identidad en `pending`; nunca activa acceso.
- Los reenvíos y resultados de entrega quedan auditados.

## Revocación y bajas

Archivar una ficha impide completar una activación pendiente porque el backend exige que el sujeto siga activo. La revocación/baja completa de cuentas externas debe preservar histórico y se implementará como flujo explícito; nunca se borra histórico para resolver inconsistencias.
