# Contrato del motor mínimo de Flujos de Trabajo

## Propósito

Este contrato define la semántica mínima que debe respetar el futuro motor transversal de **Flujos de Trabajo** antes de introducir DDL o servicios server-side. Complementa `WORKFLOW_ARCHITECTURE.md` y `WORKFLOW_IMPLEMENTATION_MAP.md`.

Cadena canónica:

`Definición → Versión publicada → Aplicación concreta → Disparador → Ejecución → Asignación → Tareas → Recursos → Evidencias → Revisión/Cierre → Historial`

El motor no pertenece a Limpieza, Inspecciones, Mantenimiento ni Check-in. Es infraestructura común. Los dominios se expresan como recetas y adaptadores sobre este motor.

## 1. Definición de flujo

Una definición representa la identidad lógica estable de un flujo.

Estados mínimos:

- `draft`: estado técnico heredado y soporte de autoría de futuras versiones; una creación nueva incompleta no se persiste como borrador de producto;
- `published`: flujo terminado disponible en **Mis Flujos**;
- `paused`: reservado para impedir nuevas ejecuciones conservando histórico;
- `archived`: flujo con historial retirado de nuevas ejecuciones sin borrar sus datos.

Reglas:

1. una creación nueva vive solo en la sesión del Creador hasta **Listo**; abandonar antes de Publicar/Ejecutar no deja una definición parcial;
2. **Publicar** finaliza atómicamente definición + versión + destino/recursos y no crea ejecución ni tarea;
3. mientras una definición publicada no tenga ninguna ejecución, **Editar** modifica su configuración actual sin crear v2 y **Eliminar** puede retirarla completamente;
4. la **primera ejecución** es la frontera histórica: desde ese momento ninguna versión utilizada puede reescribirse ni eliminarse;
5. editar un flujo con historial crea un borrador separado en `workflow_definition_revision_drafts_v2`; publicar esa edición añade vN+1;
6. cada ejecución conserva la versión, aplicación, asignación, recursos y snapshots efectivos con los que nació;
7. un flujo con historial se **Archiva**, nunca se elimina para resolver cambios de negocio;
8. nombre, categoría y descripción no conceden permisos ni alteran autorización.

## 2. Versión publicada

Una versión publicada representa la configuración ejecutable de la definición.

Antes de la primera ejecución de la definición, la versión actual puede actualizarse **en sitio** mediante el RPC específico de flujo no ejecutado. Esa excepción existe porque todavía no hay ningún hecho histórico que deba reproducirse.

Desde el instante en que existe una ejecución:

- la versión referenciada por esa ejecución es inmutable;
- su `spec_snapshot` de ejecución permanece reproducible;
- una edición futura crea una nueva fila vN+1;
- la versión anterior nunca se reescribe para cambiar el pasado.

La versión congela al menos:

- tipo/categoría del flujo;
- tipo lógico de ámbito;
- disparador;
- regla de asignación;
- pasos ordenados;
- referencias a recursos y sus versiones cuando corresponda;
- política de cierre/revisión;
- política de notificación;
- versión de adaptador de dominio si existe.

Una ejecución siempre referencia una única versión publicada y una aplicación concreta de esa versión.

## 3. Ámbito y aplicación concreta

La definición contiene el **tipo lógico de ámbito**. Tipos iniciales:

- organización;
- piso;
- habitación;
- ocupación/inquilino;
- entidad futura expresamente soportada.

Seleccionar `piso` en el Creador significa “esta receta está diseñada para ejecutarse sobre un piso”; no selecciona todavía qué piso.

Después de publicar, una **aplicación concreta** vincula la versión inmutable con la entidad real. Esa capa vive en `workflow_applications_v2` y se rige por `WORKFLOW_APPLICATIONS_CONTRACT.md`.

No se acepta un nombre visible como credencial. Las referencias reales son UUID validados server-side contra organización, relaciones, estado y RLS.

Una misma versión puede aplicarse a varios destinos sin duplicar la definición. Para habitación, la relación real es `Piso → Habitación`; para ocupación, el piso puede usarse como filtro de navegación y el servidor valida la ocupación real.

## 4. Disparadores

Tipos mínimos:

- `manual`;
- `scheduled_once`;
- `recurring`;
- `event`.

Reglas de autoría de activación:

- `manual` no usa frecuencia ni fecha programada;
- `scheduled_once` exige una fecha/hora concreta antes de considerarse configurado;
- `recurring` exige frecuencia; si es personalizada, además exige intervalo entero y unidad (`día`, `semana` o `mes`);
- los campos que no corresponden al tipo seleccionado se eliminan server-side para impedir estado residual;
- `event` no usa frecuencia temporal; la fuente concreta del evento deberá validarse antes de publicación cuando se habilite esa capacidad.

Todo disparador automático debe producir una `idempotency_key` determinista para impedir duplicados ante reintentos.

Ejemplos conceptuales:

- recurrencia semanal: `workflow_application + periodo`;
- evento: `workflow_version + source_event_id`.

La idempotencia se valida en servidor/BD, nunca solo en cliente.

## 5. Asignación

Tipos iniciales:

- persona fija;
- responsable operativo del piso;
- ocupantes activos en rotación;
- rol/capacidad autorizada;
- asignación manual al iniciar ejecución.

La resolución de quién ejecuta una tarea ocurre server-side usando el estado vigente en el momento de crear la ejecución. La ejecución conserva la decisión resultante para trazabilidad.

La regla puede usar datos dinámicos, pero el resultado asignado no se recalcula silenciosamente después de crear la ejecución.

## 6. Pasos

Una receta contiene pasos ordenados. Tipos iniciales previstos:

- confirmación/aceptación;
- evidencia fotográfica;
- formulario/checklist;
- documento;
- aprobación/revisión;
- acción especializada mediante adaptador de dominio.

Cada paso tiene:

- identidad dentro de la versión;
- orden;
- obligatoriedad;
- configuración validada;
- política de finalización.

### Checklist v1

La receta guarda una lista ordenada `checklistItems` de hasta 30 elementos. La publicación exige al menos un elemento obligatorio. La ejecución copia esa lista a `workflow_executions_v2.checklist_state`, donde se conserva el resultado operativo sin modificar `spec_snapshot`.

El checklist no crea una tabla de tareas paralela. Solo el asignado modifica su estado mediante RPC y el cierre se evalúa junto con los demás pasos configurados.

No se introducirá una segunda cámara, bucket, notificador ni sistema de tareas para implementar un tipo de paso.

## 7. Recursos

Los recursos son reutilizables y viven fuera de la receta.

Primer recurso operativo: **Banco Fotográfico**, cuyo núcleo actual es `photo_patterns_v2`.

Reglas:

1. el flujo referencia recursos, no los copia;
2. al crear una ejecución se congela la versión efectiva necesaria para reproducirla;
3. modificar un recurso después no altera una ejecución ya creada;
4. una misma captura solo puede reutilizarse entre propósitos mediante vínculos explícitos, sin reinterpretar decisiones históricas.

## 8. Ejecución

Una ejecución es una instancia concreta e inmutable de una aplicación y de la versión publicada que esa aplicación referencia.

Debe conservar al menos:

- organización y ámbito;
- definición y versión;
- origen/disparador;
- `idempotency_key`;
- instante de creación;
- asignaciones resueltas;
- snapshot de pasos y recursos necesarios;
- estado de ejecución;
- cierre y resultado.

Estados mínimos previstos:

- `pending`;
- `active`;
- `waiting_review`;
- `completed`;
- `cancelled`;
- `failed` cuando exista fallo técnico no equivalente a cancelación de negocio;
- `rejected` cuando una decisión de negocio/aceptación/revisión rechaza explícitamente la ejecución.

Las transiciones se validan en servidor.

El runner inicial `execute_workflow_application_now_v1` crea una ejecución `pending` con `trigger_kind=manual_now`, clave idempotente, asignación congelada y una tarea materializada. Las transiciones de workflow usan un RPC atómico que cambia tarea + ejecución juntas; el RPC legacy de tareas no puede modificar una tarea de workflow.


## 9. Tareas

`tenant_tasks_v2` es el núcleo reutilizado para materializar trabajo de usuario. Las tareas de workflow se identifican por `source_kind='workflow_execution'`; no existe una tabla `workflow_tasks` paralela.

Una ejecución puede crear una o más tareas. Cada tarea debe poder enlazarse de forma inequívoca a la ejecución/origen.

Los históricos existentes `tenant_task_actions_v2` y `tenant_task_history_v2` se reutilizan cuando corresponda y no se reescriben.

## 10. Evidencias

La infraestructura fotográfica existente se reutiliza:

- `photo_verification_runs_v2`;
- `photo_verification_items_v2`;
- bucket privado actual;
- captura fullscreen y alineación local;
- revisión humana existente.

Otros tipos de evidencia se incorporarán como recursos/pasos compatibles, no como un segundo motor.

## 11. Cierre y revisión

El cierre puede ser:

- automático al completar pasos;
- tras revisión humana;
- especializado por adaptador de dominio.

La IA puede asistir, pero no es barrera única de seguridad ni puede otorgar permisos.

Una revisión ya decidida no se reinterpreta por cambiar después la receta o el recurso.

Para `closeType=human_review`, los pasos implementados pasan a `waiting_review`. La revisión administrativa reutiliza `tenant_task_actions_v2` cuando no existe Foto y la revisión de `photo_verification_runs_v2` cuando existe evidencia fotográfica. No se crea una segunda cola de revisión.

## 12. Historial y auditoría

El histórico funcional del motor debe registrar eventos suficientes para reconstruir:

- qué versión se ejecutó;
- por qué se ejecutó;
- a quién se asignó;
- qué pasos y recursos se usaron;
- qué evidencias/resultados se produjeron;
- quién revisó/cerró y cuándo.

`audit_log_v2` se conserva para operaciones sensibles/administrativas; no sustituye el histórico funcional de la ejecución.

No se borra histórico para resolver inconsistencias.

## 13. Notificaciones

El motor reutiliza `notifications_v2`. La receta puede declarar eventos que generan aviso, pero la entrega se delega a la infraestructura existente.

No se introduce un segundo sistema de notificaciones.

## 14. Permisos y seguridad

Reglas mínimas:

1. RLS obligatoria en nuevas tablas sensibles;
2. autorización de crear/publicar/pausar/archivar se valida server-side;
3. ROOT opera en su organización con las protecciones existentes;
4. ADMIN solo según su ámbito/autorización vigente;
5. responsable de piso puede operar flujos de su piso solo cuando la política explícita lo permita;
6. otro empleado no adquiere capacidad por ver un botón;
7. propietario e inquilino no crean/publican recetas administrativas por defecto;
8. ejecutar una tarea propia no concede permiso para editar la receta;
9. referencias a piso/persona/recurso se validan contra organización y permiso;
10. acciones sensibles generan auditoría.

La publicación y cambios que afecten reglas operativas se diseñarán como operaciones backend; nunca se confiará en validación únicamente cliente.

## 15. Concurrencia e idempotencia

El motor debe soportar reintentos seguros:

- índice/constraint de idempotencia para ejecuciones automáticas;
- creación de ejecución + snapshot + tareas en transacción o procedimiento atómico cuando sea viable;
- reintento no duplica tareas ni notificaciones;
- la resolución de rotación debe bloquear/serializar lo necesario para evitar dos asignaciones del mismo turno.

## 16. Adaptador de Limpieza

Limpieza es el primer dominio a migrar.

Se conservan `cleaning_plans_v2`, `cleaning_tasks_v2`, swaps, deudas, auditoría y solicitudes fotográficas durante la transición.

El adaptador de Limpieza debe:

- permitir que una definición genérica dispare la semántica de Limpieza existente;
- mantener trazabilidad entre ejecución genérica y registros `cleaning_*`;
- conservar intercambio, deuda no monetaria y auditoría como reglas propias del dominio;
- no convertir `cleaning_plans_v2` en una definición universal.

La ruta legacy solo se retira cuando el recorrido equivalente esté probado extremo a extremo.

## 17. Creador de Flujos

El Creador es una interfaz integrada de autoría y preparación:

`Diseño → Destino → Listo`

Diseño conserva los siete pasos:

1. identidad;
2. ámbito;
3. activación;
4. asignación;
5. pasos y recursos;
6. cierre/revisión;
7. revisión final.

Reglas de autoría:

- una **creación nueva incompleta no se guarda** en servidor ni en una lista de borradores para retomarla;
- salir antes de finalizar avisa de que los cambios se perderán;
- al pasar de Diseño a Destino, el estado se transporta temporalmente dentro de la misma sesión y todavía no se publica;
- en Listo existen tres decisiones de producto: **Publicar**, **Ejecutar** y **Descartar**;
- **Publicar** guarda el flujo completo con su destino y recursos en Mis Flujos, pero crea cero tareas;
- **Ejecutar** realiza la misma finalización y, si las condiciones actuales son válidas, crea una ejecución/tarea idempotente;
- un flujo publicado sin ejecuciones se edita como la misma entidad lógica y puede eliminarse;
- un flujo que ya tiene historial se edita sobre un borrador separado de futura versión; abandonar esa edición no altera la versión operativa;
- **Mis Flujos** muestra las acciones de negocio `Ejecutar / Editar / Eliminar` o `Ejecutar / Editar / Archivar`; la UI no obliga al usuario a decidir si técnicamente necesita una nueva versión;
- ninguna selección de tipo, ámbito, activación, asignación, pasos o cierre se presupone;
- el backend mantiene autorización, AAL2, idempotencia y trazabilidad aunque la UX oculte las capas técnicas.

## 18. Condiciones antes del primer DDL

Antes de crear tablas del motor:

- este contrato debe estar versionado en `main`;
- el mapa de reutilización debe seguir vigente;
- debe definirse la migración mínima y aditiva;
- deben añadirse pruebas RLS positivas y negativas;
- no se deben duplicar tareas, cámara, Storage, notificaciones ni históricos existentes.

El primer DDL será aditivo, reversible por migración posterior y preservará íntegramente los datos históricos actuales.


## Evidencia fotográfica operativa

El primer recurso transversal ejecutable es Fotografía. La definición declara `steps.photo=true`; la Aplicación vincula patrones reales del piso y cada ejecución congela versión + silueta en `workflow_execution_photo_resources_v2`.

La cámara y persistencia siguen siendo las existentes. El envío de workflow se finaliza con `submit_workflow_photo_verification_v1`, que verifica el objeto privado y mantiene recurso, tarea y ejecución coherentes en una transacción. Véase `WORKFLOW_PHOTO_EVIDENCE_CONTRACT.md`.
