# Recuperación de emergencia de MFA (break-glass)

Este procedimiento existe únicamente para una cuenta **ROOT o ADMIN** que conserva su email/contraseña pero ha perdido el acceso a **todos** sus autenticadores TOTP. No sustituye al factor de respaldo: el camino normal sigue siendo entrar con otro autenticador verificado.

## Principios de seguridad

- GestionPisos nunca permite eliminar el último factor verificado desde la interfaz normal.
- La solicitud de recuperación **no elimina ni modifica nada**. Solo crea un evento pendiente y un `request_id` auditable.
- El `request_id` no es un secreto, una contraseña ni una autorización. Nunca aprobar una recuperación únicamente por conocer el código de solicitud.
- La ejecución destructiva es exclusiva de backend/plataforma y las credenciales privilegiadas nunca se exponen en GitHub Pages.
- El operador usa la consola técnica `operator-recovery.html`, con una identidad de plataforma separada y MFA `aal2`; el navegador nunca llama directamente a `recover-privileged-mfa`.
- Ser ROOT o ADMIN de GestionPisos no concede automáticamente la condición de operador de plataforma.
- Un operador no puede aprobar su propia recuperación. Recuperar una cuenta ROOT exige además `can_recover_root=true`.
- Antes de ejecutar hay que verificar por un canal independiente la identidad del titular y documentar esa comprobación en `verification_note`.
- Cada solicitud, aprobación/rechazo, resultado y estado parcial queda registrado en `audit_log_v2`.

La autorización y alta de operadores se documenta en `docs/PLATFORM_OPERATOR_CONSOLE.md`.

## Flujo del usuario

1. Tras introducir email y contraseña, ROOT/ADMIN llega al desafío MFA.
2. Si no dispone de ninguno de sus autenticadores pulsa **No tengo acceso a mis autenticadores**.
3. `request-mfa-recovery` comprueba sesión, rol privilegiado y que realmente existen factores verificados. Si la sesión ya es `aal2`, rechaza la solicitud porque la recuperación no es necesaria.
4. Se registra `mfa_recovery_requested` con estado `pending` y se muestra un `request_id` que caduca operativamente a los 60 minutos.
5. Ningún factor, contraseña ni sesión se modifica en este punto.

## Verificación humana obligatoria

Un operador de Allaiso debe comprobar la identidad por un canal independiente del dispositivo perdido. La verificación concreta depende del contexto contractual de la organización, pero debe dejar evidencia suficiente para explicar quién fue verificado, por qué canal y por qué el operador consideró válida la recuperación.

No son prueba suficiente por sí solas: conocer el email, conocer la contraseña, disponer del `request_id`, una captura de pantalla o afirmar que se perdió el móvil.

## Ejecución por plataforma

Tras verificar la identidad, el operador abre la consola técnica Allaiso, completa su propio MFA y revisa la solicitud pendiente. La consola habla únicamente con `operator-mfa-recovery`, que revalida que el usuario sea un operador activo en `platform_operators` y que la sesión esté en `aal2`.

Al aprobar, el gateway backend llama internamente a `recover-privileged-mfa` con:

- `request_id`: solicitud pendiente vigente.
- `operator_reference`: referencia generada por backend a partir de la identidad técnica del operador.
- `verification_note`: resumen de la verificación externa realizada.

La función destructiva solo acepta la credencial backend de plataforma. Revalida que la solicitud esté pendiente, tenga menos de 60 minutos y que el objetivo siga siendo ROOT/ADMIN.

El orden de ejecución es deliberado:

1. Elimina primero un factor verificado mediante la API administrativa de MFA, provocando la revocación de las sesiones activas del usuario.
2. Sustituye la contraseña por un valor aleatorio desconocido para invalidar la contraseña anterior.
3. Elimina el resto de factores MFA.
4. Solicita un correo de recuperación de contraseña hacia la pantalla de producción de GestionPisos.
5. Registra `mfa_recovery_completed`. Si una fase intermedia falla, registra `mfa_recovery_partial` para poder reanudar sin ocultar el estado alcanzado.

La contraseña aleatoria nunca se devuelve, registra ni entrega al operador o al usuario.

## Vuelta a servicio

1. El usuario abre el correo de recuperación y crea una contraseña nueva conforme a la política vigente.
2. Inicia sesión de nuevo.
3. Al ser ROOT/ADMIN y no tener ya factores verificados, GestionPisos fuerza `mfa-setup.html` antes de permitir acceso operativo.
4. El usuario registra y verifica un nuevo autenticador principal.
5. Debe añadir después un autenticador de respaldo en un dispositivo independiente.

Si el correo automático de recuperación falla, la recuperación de MFA puede quedar completada igualmente, pero el usuario deberá iniciar el flujo normal **He olvidado mi contraseña**. Nunca se comunica la contraseña aleatoria.

## Pruebas y operación

- No ejecutar una recuperación completa sobre una cuenta ROOT/ADMIN real como smoke test: por diseño invalida contraseña, sesiones y factores.
- Las pruebas normales deben comprobar alta/uso de factores, creación no destructiva de solicitud, acceso del operador, listado y rechazo.
- Un simulacro completo requiere una cuenta objetivo de prueba, una cuenta de operador independiente, ventana controlada y plan de recuperación de contraseña/MFA.
- Ante cualquier resultado parcial, no borrar registros ni repetir a ciegas; revisar `audit_log_v2`, identificar la última etapa completada y reanudar de forma controlada.
