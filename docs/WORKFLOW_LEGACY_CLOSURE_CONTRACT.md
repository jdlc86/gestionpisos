# Contrato WF-09 · Cierre controlado de compatibilidad legacy

## Objetivo

WF-09 no consiste en borrar tablas antiguas por nombre. Su objetivo es cerrar la migración al motor transversal sin perder histórico, expedientes de dominio ni rutas que todavía necesita el E2E final.

La regla es:

> retirar una superficie legacy solo cuando exista equivalencia funcional, seguridad demostrada y E2E del reemplazo. Mientras tanto se conserva de forma explícita y se impide que nuevas piezas dependan de ella.

## Estado real al iniciar WF-09

En producción, al iniciar este bloque:

- `tenant_tasks_v2` contiene 16 tareas y las 16 son `task_type='workflow'` con `source_kind='workflow_execution'`;
- no existen filas operativas en `cleaning_plans_v2`, `cleaning_tasks_v2`, `cleaning_swap_requests_v2` ni `cleaning_debts_v2`;
- `tenant_task_workflow_templates_v2` conserva 53 transiciones históricas para 11 tipos legacy;
- Cartera sigue ofreciendo el diálogo **Tareas** que crea tareas antiguas mediante `create_tenant_task_v2` y las opera mediante `apply_tenant_task_action_v2`;
- `cleaning.html` sigue admitiendo `task_id` legacy y `workflow_task_id`, porque también es la vista de dominio usada por WF-03;
- el motor nuevo ya reserva `task_type='workflow'` + `source_kind='workflow_execution'`.

Estos conteos son una fotografía de producción, no una precondición destructiva. WF-09 no elimina datos si el estado cambia.

## Clasificación obligatoria

### A. Núcleo transversal — CONSERVAR

No es legacy aunque se originara antes del motor completo:

- `tenant_tasks_v2`;
- `tenant_task_actions_v2`;
- `tenant_task_history_v2`.

Son la capa operativa compartida del motor actual.

### B. Expedientes/adaptadores de dominio — CONSERVAR

No se eliminan por WF-09 porque el motor actual los reutiliza:

- `cleaning_tasks_v2` y las tablas `cleaning_* ` necesarias para fotoverificación, auditoría, cambios y deuda;
- `incidents_v2`;
- `payment_obligations_v2`;
- `claims_v2`;
- `security_deposits_v2`.

En particular, WF-03 crea idempotentemente un expediente `cleaning_tasks_v2` enlazado a `workflow_execution_id`, mientras `tenant_tasks_v2` sigue siendo la única tarjeta operativa.

### C. Compatibilidad legacy temporal — MANTENER HASTA E2E FINAL

Superficies aprobadas temporalmente:

1. `public.create_tenant_task_v2`;
2. `public.apply_tenant_task_action_v2`;
3. `tenant_task_workflow_templates_v2`;
4. diálogo **Tareas** de Cartera (`portfolio.html/js`);
5. entrada `task_id` de `cleaning.html/js`;
6. retorno legacy de cámara hacia `cleaning.html?task_id=...`.

No se deben crear nuevas dependencias sobre estas superficies.

### D. Candidatos a retirar después del E2E final

Si la batería final confirma equivalencia:

- retirar de Cartera la creación/operación de tareas legacy y redirigir la operativa al Creador/Tareas del motor común;
- retirar `EXECUTE` cliente de `create_tenant_task_v2` y `apply_tenant_task_action_v2` cuando ya no exista UI autorizada que los necesite;
- retirar la entrada `task_id` de Limpieza y el retorno de cámara asociado cuando ningún histórico/flujo activo dependa de ella;
- evaluar entonces si `tenant_task_workflow_templates_v2` puede quedar solo como histórico o eliminarse mediante una migración específica.

Ninguno de esos pasos se ejecuta en WF-09 antes de la batería E2E.

## Fronteras de seguridad que deben permanecer

- `apply_tenant_task_action_v2` debe rechazar cualquier tarjeta con `task_type='workflow'` o `source_kind='workflow_execution'` mediante `workflow_task_requires_atomic_action`.
- `create_tenant_task_v2` no debe aceptar `task_type='workflow'`.
- `tenant_tasks_v2_subject_or_workflow_check` debe reservar `source_kind='workflow_execution'` a tarjetas `task_type='workflow'` con `source_id` y asignado.
- `tenant_task_workflow_templates_v2` no debe contener plantilla `task_type='workflow'`.
- El materializador del motor sigue siendo la única vía de creación de tarjetas workflow.

## Política de referencias frontend

Hasta el E2E final, las llamadas cliente a los RPC legacy están autorizadas únicamente en `docs/portfolio.js`.

La compatibilidad de Limpieza con `task_id` está autorizada únicamente en la vista/retorno de Limpieza y cámara. Toda nueva operativa debe usar `workflow_task_id`.

Un smoke de WF-09 debe fallar si aparece una nueva llamada cliente a `create_tenant_task_v2` o `apply_tenant_task_action_v2` fuera de Cartera.

## Criterio de cierre de WF-09 antes del E2E

WF-09 puede quedar `IMPLEMENTED_E2E_GATE` cuando:

- el inventario está documentado;
- las fronteras legacy↔workflow tienen regresión;
- las referencias frontend autorizadas están congeladas por smoke;
- no se ha retirado una compatibilidad necesaria;
- la batería final tiene una lista explícita de decisiones de retirada.

La retirada efectiva se realiza solo tras el E2E final y una verificación de datos/refs en producción.
