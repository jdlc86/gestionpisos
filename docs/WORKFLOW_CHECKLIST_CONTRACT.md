# Contrato — Checklist de Flujos

Fecha de referencia: **2026-09-19**.

## 1. Alcance

Checklist es un tipo de paso del motor común de Flujos. No crea un segundo motor de tareas ni reutiliza el checklist fotográfico específico de Limpieza.

La primera versión admite una lista ordenada de elementos con:

- texto;
- marca obligatorio/opcional;
- máximo 30 elementos;
- máximo 160 caracteres por elemento.

No incluye campos de texto libre, firma, adjuntos propios, sublistas ni lógica condicional.

## 2. Autoría y publicación

El Creador envía `checklistItems` junto con `steps.checklist=true`.

El servidor normaliza cada elemento a:

```json
{"key":"item-1","text":"...","required":true}
```

Las claves se derivan del orden de la receta y quedan congeladas en la versión publicada.

Una receta con Checklist solo tiene `authoring_complete=true` cuando:

- existe al menos un elemento;
- todos tienen texto válido;
- existe al menos un elemento obligatorio.

Los borradores parciales siguen siendo guardables; simplemente no son publicables.

## 3. Snapshot por ejecución

`spec_snapshot` conserva la receta publicada e inmutable.

`workflow_executions_v2.checklist_state` conserva el estado operativo de esa ejecución. Al crearla se inicializa desde `spec_snapshot.checklistItems` con:

- `key`;
- `text`;
- `required`;
- `completed`;
- `completedAt`;
- `completedBy`.

Editar o publicar una versión posterior no cambia ejecuciones existentes.

## 4. Mutación

La única API de cliente para cambiar casillas es:

`set_workflow_checklist_item_v1(task_id, item_key, completed, request_key)`

Reglas:

- solo el usuario asignado;
- tarea y ejecución deben pertenecer al mismo workflow y estar sincronizadas;
- si `steps.accept=true`, no puede marcarse antes de Aceptar;
- solo se modifica en estados operativos `pending` o `active`;
- un reintento con la misma `request_key` recupera el resultado ya aplicado;
- reutilizar la clave para otro cambio se rechaza.

No existe permiso UPDATE directo del cliente sobre `workflow_executions_v2`.

## 5. Cierre

Los elementos opcionales no bloquean el cierre.

Al completarse el último obligatorio, el motor comprueba los demás pasos:

- Foto configurada: todos sus recursos deben estar `submitted`;
- Documento configurado: sigue bloqueando hasta que ese paso tenga implementación propia.

Si todos los pasos operativos están satisfechos:

- `closeType=auto` → tarea + ejecución `completed`;
- `closeType=human_review` → tarea + ejecución `waiting_review`.

Foto y Checklist pueden completarse en cualquier orden.

## 6. Historial y auditoría

Cada cambio de casilla registra:

- `tenant_task_history_v2`;
- evento `workflow_execution_events_v2.event_type='checklist_item_changed'`;
- `audit_log_v2`.

La clave de reintento queda en el evento funcional y dispone de índice único por ejecución.

## 7. Seguridad

RLS de la ejecución sigue protegiendo la lectura. La escritura se canaliza exclusivamente mediante RPC `SECURITY DEFINER` con autorización explícita del asignado.

`anon` no puede ejecutar el RPC. Un ADMIN/ROOT que no sea el asignado puede ver según sus permisos administrativos, pero no marcar elementos en nombre del ejecutor.
