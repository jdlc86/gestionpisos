# Batería E2E final · Motor transversal WF-04 → WF-09

## Objetivo

Esta batería es el gate final antes de marcar WF-04..WF-09 como `VERIFIED` y antes de retirar compatibilidad legacy.

No introduce un motor nuevo ni cambia reglas de negocio. Separa:

1. **preflight automático**: invariantes de esquema, permisos, unicidad y frontera legacy;
2. **E2E humano en PWA**: navegación, creación, ejecución y observación real de cada dominio;
3. **decisión de retirada legacy**: solo después de que los reemplazos hayan pasado E2E.

## Reglas de ejecución

- Producción sigue siendo entorno de prueba, pero no se hacen DDL ni DML ad hoc.
- Todo dato de prueba se crea mediante la PWA o RPC públicos ya autorizados.
- No modificar migraciones aplicadas.
- Usar un único piso/habitación/ocupación de prueba y un responsable vigente con escritura.
- Conservar trazabilidad: definición, aplicación, ejecución, tarea, eventos, historial y notificaciones.
- Si un caso falla, detener únicamente ese caso, documentar el primer fallo reproducible y corregir por rama → PR → guards → merge.

## Gate 0 · Preflight automático

Ejecutar `tests/workflow-final-e2e-preflight.sql` contra un esquema actualizado.

Debe confirmar:

- router workflow vigente ejecutable por `authenticated`;
- router `pre_wf07` sin EXECUTE externo;
- RPC legacy todavía disponibles hasta terminar la batería;
- ninguna plantilla legacy puede crear `task_type=workflow`;
- ninguna tarjeta workflow está materializada dos veces para la misma ejecución;
- `tenant_tasks_v2`, `claims_v2` y `security_deposits_v2` no exponen escritura directa al cliente donde el contrato exige RPC;
- tablas de dominio WF-05/06/07 y motor transversal presentes.

### Preparación humana mínima

Antes de empezar la PWA deben existir:

- 1 piso operativo elegible;
- 1 habitación activa;
- 1 ocupación/inquilino activo;
- 1 empleado responsable vigente con `can_write=true`;
- ROOT/ADMIN con MFA/AAL2 para acciones privilegiadas;
- email profesional operativo para probar comunicaciones WF-07.

Si falta cualquiera, prepararlo mediante la UI/RPC oficial y volver a ejecutar el preflight. No parchear producción con SQL manual.

---

## Gate 1 · Motor transversal genérico

### 1.1 Checklist

1. Crear un flujo manual con Checklist.
2. Publicarlo y ejecutarlo.
3. Confirmar que aparece una sola tarjeta en Tareas.
4. Marcar items uno a uno.
5. Verificar que no cierra antes del último requisito.
6. Confirmar Historial y evento `checklist_item_changed`.
7. Repetir una acción con la misma request key y comprobar idempotencia.

**PASS:** una ejecución, una tarjeta, estado sincronizado y cierre conforme a `closeType`.

### 1.2 Documento

1. Crear un flujo con Documento.
2. Ejecutarlo con un asignado.
3. Preparar subida, subir al storage privado y confirmar evidencia.
4. Abrir el documento como gestor autorizado.
5. Verificar que otro usuario no puede adjuntar en nombre del asignado.

**PASS:** evidencia `submitted`, acceso por URL firmada y sin escritura cruzada.

### 1.3 Fecha concreta

1. Programar una ejecución futura cercana.
2. No ejecutar manualmente.
3. Confirmar disparo único.
4. Verificar que una segunda pasada del cron no duplica ejecución/tarea.

**PASS:** una sola ocurrencia y programación consumida correctamente.

### 1.4 Recurrente

1. Crear recurrencia con primera fecha explícita.
2. Observar una primera ocurrencia.
3. Cambiar el responsable operativo por la vía oficial.
4. Observar la segunda ocurrencia.

**PASS:** cada ocurrencia crea una ejecución/tarea nueva y la segunda resuelve al responsable vigente, no al anterior.

---

## Gate 2 · WF-04 · Check-in / Check-out + llaves

1. Crear/publicar aplicaciones compatibles para Check-in y Check-out.
2. Dar de alta/reactivar una ocupación usando el flujo oficial.
3. Confirmar evento → una ejecución → una tarjeta.
4. Completar pasos y llaves según configuración.
5. Ejecutar salida/Baja.
6. Confirmar que el acceso del inquilino queda revocado al finalizar la Baja.
7. Verificar que el historial de la ocupación permanece visible a roles autorizados.

**PASS:** lifecycle, llaves, tarea, ejecución y Auth permanecen coherentes; ningún evento obsoleto bloquea la cola.

---

## Gate 3 · WF-05 · Incidencia → Mantenimiento → Inspección

1. Abrir una incidencia real desde la UI.
2. Confirmar un solo expediente `incidents_v2`.
3. Procesar `incident.created` y verificar un único gestor Mantenimiento compatible.
4. Aceptar y, si aplica, solicitar información.
5. Responder la solicitud desde el actor autorizado.
6. Completar Foto/Checklist/Documento configurados.
7. Resolver la incidencia.
8. Confirmar `incident.resolved`.
9. Si existe aplicación de Inspección, verificar ejecución downstream y sus evidencias.

**PASS:** una única tarjeta operativa por ejecución, expediente enlazado, acciones idempotentes y fan-out de inspección solo según aplicaciones compatibles.

---

## Gate 4 · WF-06 · Pago de alquiler + Reclamación

### 4.1 Pago

1. Crear/ejecutar un flujo `rent_payment` sobre la ocupación.
2. Verificar obligación única.
3. Probar aplazamiento válido.
4. Registrar pago.
5. Repetir request key y comprobar que no duplica historial/estado.

### 4.2 Reclamación

1. Usar una obligación vencida según la zona horaria configurada.
2. Ejecutar `claim`.
3. Confirmar una sola reclamación enlazada a la obligación.
4. Notificar al inquilino.
5. Probar ciclo `request_info → provide_info → continue` dos veces.
6. Resolver el expediente.

**PASS:** fecha de negocio local correcta, sin doble obligación/reclamación y sin reutilizar respuestas antiguas.

---

## Gate 5 · WF-07 · Fianza + Daños

### 5.1 Recepción y revisión

1. Registrar una fianza para la ocupación.
2. Confirmar una única fila `security_deposits_v2`.
3. Completar `deposit_receipt`.
4. Ejecutar la Baja para disparar `deposit_review`.
5. Confirmar que el antiguo inquilino sigue sin acceso a PWA.

### 5.2 Sin daños

1. Completar evidencia de revisión.
2. Devolver la fianza completa.
3. Confirmar email y estado final.

### 5.3 Con daños

1. Abrir una reclamación de daños.
2. Intentar abrir una segunda y verificar rechazo.
3. Completar evidencia.
4. Notificar por email.
5. Registrar aceptación o disputa externa.
6. Resolver con importe reconocido.
7. Probar retención parcial coherente con daño reconocido.
8. En un caso separado, probar retención total solo cuando el daño reconocido cubra toda la fianza.

### 5.4 Baja sin fianza

1. Ejecutar Baja sobre una ocupación sin fianza recibida.
2. Confirmar `workflow_domain_lifecycle_mismatch` terminal y que el outbox no reintenta indefinidamente.

**PASS:** una fianza por ocupación, máximo una reclamación de daños, ninguna reactivación del tenant y emails idempotentes.

---

## Gate 6 · WF-08 · Presets del Creador

Probar los cinco presets:

- Limpieza;
- Inspección;
- Mantenimiento;
- Check-in;
- Check-out.

Para cada uno:

1. seleccionar tipo nuevo;
2. comprobar que solo rellena campos vacíos/no tocados;
3. modificar una decisión manualmente;
4. cambiar de tipo y volver;
5. comprobar que no destruye la decisión;
6. abrir un borrador existente y confirmar que `applyDraft()` no reaplica preset;
7. comprobar que no inventa fecha/hora;
8. comprobar que `custom`, WF-06 y WF-07 no reciben preset.

**PASS:** preset = sugerencia de autoría, nunca autoridad de ejecución.

---

## Gate 7 · WF-09 · Frontera legacy

1. Confirmar que Cartera sigue siendo la única UI que llama a `create_tenant_task_v2` / `apply_tenant_task_action_v2`.
2. Crear una tarea legacy desde Cartera y comprobar que sigue funcionando durante la batería.
3. Confirmar que ese RPC no puede actuar sobre una tarjeta `task_type=workflow`.
4. Probar Limpieza por la ruta nueva `workflow_task_id`.
5. Verificar que `task_id` legacy solo se usa en el camino temporal documentado.
6. Tras completar Gates 1–6, decidir qué superficies pueden retirarse.

### Decisiones post-E2E

Solo con todos los Gates anteriores en PASS:

- retirar creación/operación legacy de Cartera;
- retirar EXECUTE cliente de `create_tenant_task_v2` y `apply_tenant_task_action_v2`;
- retirar `task_id` legacy de Limpieza/cámara cuando no haya consumidores;
- evaluar `tenant_task_workflow_templates_v2` como histórico o retirada mediante migración específica.

Cada retirada será un PR separado y no se hará dentro de la propia batería.

---

## Evidencia mínima por caso

Registrar:

- SHA de `main`;
- usuario/rol utilizado, sin contraseñas;
- ID de definición/aplicación/ejecución/tarea;
- ID de expediente de dominio cuando exista;
- estado inicial y final;
- request keys usadas;
- eventos/historial relevantes;
- captura de la PWA cuando el resultado sea visual;
- email recibido cuando corresponda;
- PASS/FAIL y primer error reproducible.

## Criterio de cierre

WF-04..WF-08 solo pasan a `VERIFIED` cuando sus Gates humanos correspondientes están en PASS.

WF-09 solo pasa de `IMPLEMENTED_E2E_GATE` a cierre cuando:

1. Gates 1–6 están en PASS;
2. Gate 7 confirma equivalencia;
3. se decide explícitamente qué legacy retirar;
4. cada retirada posterior pasa nuevamente Governance, PWA y Schema.
