# Contrato de autenticación y acceso

## Alta de personal interno

1. ROOT o el ADMIN titular del control de escritura crea el ADMIN/EMPLOYEE con nombre, email y rol previsto.
2. La identidad Auth y el perfil se crean en estado **pendiente de activación**. Mientras esté pendiente no puede existir un rol interno activo ni acceso operativo activo a viviendas.
3. La aplicación genera un enlace de activación de un solo uso en backend y lo envía mediante el proveedor transaccional profesional; nunca se entrega una contraseña temporal al administrador.
4. El correo abre primero una página del dominio de GestionPisos que requiere una acción humana antes de seguir el enlace de Auth, reduciendo el riesgo de consumo automático por escáneres de correo.
5. El usuario demuestra control de su correo y crea personalmente una contraseña de al menos 12 caracteres.
6. Solo después de completar la activación se activa su rol previsto. Las asignaciones históricas migradas desde el flujo antiguo solo se restauran si siguen siendo seguras y no pisan un responsable/acceso actual.
7. El rol/acceso se activa primero en base de datos y solo después se sincronizan los claims de Auth. La sesión de activación se cierra para forzar un JWT nuevo.
8. Una invitación pendiente puede reenviarse con antiabuso/cooldown o revocarse sin borrar la identidad ni el histórico.
9. ADMIN y ROOT deben completar MFA conforme a la política de seguridad antes de acciones sensibles.

Un usuario pendiente **no es un empleado operativo todavía**. La interfaz puede mostrarlo para administración del onboarding, pero no puede ofrecerlo como responsable, acceso adicional ni titular de capacidades administrativas.

## Bienvenida de propietario e inquilino

La ficha de Cartera y la identidad de acceso son conceptos separados. Dar de alta un propietario o un inquilino no le concede acceso automáticamente.

1. El gestor puede **Guardar sin enviar** o **Guardar y enviar bienvenida**.
2. El envío crea/prepara una identidad Auth pendiente sin contraseña conocida por el gestor.
3. El backend valida organización, sujeto, permisos e identidad de email antes de crear o reutilizar Auth.
4. El correo de bienvenida se entrega por el proveedor transaccional profesional y utiliza un enlace de un solo uso.
5. El propietario/inquilino crea personalmente una contraseña de al menos 12 caracteres.
6. Backend vincula primero la identidad a `owners` o `tenants_v2`/`occupancies_v2` y activa el rol DB `owner` o `tenant`.
7. Solo después del éxito DB se sincronizan `app_metadata.role` y `app_metadata.organization_id`; luego se fuerza un nuevo login.
8. Las tarjetas de Cartera muestran el estado del acceso y permiten enviar/re-enviar una bienvenida pendiente.

El modelo actual es de una identidad/rol principal por cuenta. Si un email ya corresponde a ADMIN/EMPLOYEE, OWNER, TENANT u otra identidad Auth no compatible, el alta de acceso **se bloquea** en vez de cruzar o fusionar cuentas silenciosamente. La política completa está en `docs/EXTERNAL_ONBOARDING_CONTRACT.md`.

### Inquilino por QR

El futuro/autoservicio mediante QR conserva estas reglas: el QR solo inicia identificación/solicitud, nunca concede acceso. La ocupación debe coincidir con la solicitud, el acceso requiere aprobación cuando proceda y la activación termina con contraseña personal y vínculo Auth verificable.

## Invariante global de email de invitación

Toda invitación de acceso queda ligada a **una identidad concreta y a un email canónico concreto**.

- Una invitación nunca se traslada silenciosamente a otro correo.
- Si cambia el correo antes de activar una cuenta externa (OWNER/TENANT), la invitación anterior debe revocarse y la identidad pendiente anterior debe quedar inutilizada antes de crear una nueva.
- El onboarding de ADMIN/EMPLOYEE conserva `invitation_email`; mientras esté `pending` o `active`, ese valor debe coincidir con el email del perfil y con el email de Auth.
- Reenviar o completar una activación interna debe fallar si existe cualquier deriva entre esos tres valores.
- El email de una identidad interna ya activada no se modifica desde una edición ordinaria: requiere un flujo específico de cambio de cuenta.
- Los operadores de emergencia conservan `identity_email` como vínculo inmutable de su identidad técnica. Cambiar el correo exige desactivar/reprovisionar otra identidad; la consola de recuperación rechaza identidades cuyo email Auth ya no coincide.
- Los controles anteriores se validan en backend/base de datos además de en interfaz. No dependen de que el cliente se comporte correctamente.

Esta regla se aplica a todo nuevo flujo de invitación que se añada al producto.

## Recuperación

- “Olvidé mi contraseña” → email → enlace de un solo uso → nueva contraseña.
- Respuesta neutra para evitar enumeración de cuentas.
- El enlace debe volver a una URL de producción autorizada; `localhost` está prohibido fuera de desarrollo local.
- La pantalla de nueva contraseña solo se habilita tras validar una sesión/token de recuperación legítimo.
- Al completar recuperación/cambio se invalidan todas las demás sesiones.
- ROOT/ADMIN deben completar MFA según política.

### Recuperación de emergencia MFA de ROOT/ADMIN

- Perder todos los autenticadores no autoriza a omitir MFA. La interfaz solo permite crear una solicitud de recuperación pendiente y auditable.
- La solicitud requiere una sesión válida de la cuenta privilegiada en `aal1`, que el usuario siga teniendo rol ROOT/ADMIN y que existan factores MFA verificados. Si ya alcanzó `aal2`, no procede una recuperación de emergencia.
- El `request_id` es únicamente un correlador de auditoría: no es secreto y nunca basta para aprobar el proceso.
- La ejecución se realiza exclusivamente desde backend/plataforma tras verificación humana independiente de la identidad. Nunca se expone una credencial administrativa en frontend.
- El proceso revoca sesiones, invalida la contraseña anterior, elimina los factores perdidos y dispara recuperación de contraseña. Después, el siguiente acceso obliga a enrolar MFA nuevamente antes de permitir uso operativo.
- Cualquier resultado parcial debe quedar auditado y ser reanudable sin borrar el histórico.
- El procedimiento detallado está en `docs/MFA_RECOVERY_RUNBOOK.md`.

## Entrega profesional de correos de autenticación

El envío de correos críticos de autenticación en producción **no puede depender del SMTP incorporado de Supabase**.

- El SMTP incorporado solo se acepta para desarrollo/pruebas.
- Producción debe usar SMTP personalizado o entrega transaccional propia con un proveedor controlado por el proyecto.
- Proveedor preferido inicial: Resend; la aplicación no debe quedar acoplada al proveedor.
- Las credenciales de correo nunca pueden residir en frontend, GitHub Pages, commits ni documentación pública.
- El dominio remitente debe tener SPF, DKIM y DMARC configurados.
- Los límites de Auth deben revisarse y configurarse explícitamente tras activar el proveedor profesional.
- Un entorno limitado por el SMTP incorporado de Supabase o por un techo equivalente a 2 correos/hora no se considera apto para producción.
- La política completa de migración, pruebas, observabilidad y resiliencia está en `docs/AUTH_EMAIL_DELIVERY_MIGRATION.md`.

## Bloqueo/revocación

Bloquear acceso no borra al usuario ni su histórico. Debe impedir nuevas operaciones y hacer inefectivas las sesiones conforme a la política de seguridad.

## Eventos de email mínimos

- solicitud recibida cuando proceda
- acceso aprobado/rechazado
- activación/bienvenida de personal interno
- bienvenida/activación de propietario
- bienvenida/activación de inquilino
- recuperación de contraseña
- cambio de rol de empleado
- eventos/reclamaciones configuradas
