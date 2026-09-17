# Estado de implementación — Flujos de Trabajo

Fecha de referencia: **2026-09-18**.

Este documento resume el estado real de implementación de **Flujos de Trabajo** y complementa:

- `WORKFLOW_ARCHITECTURE.md` — arquitectura funcional objetivo;
- `WORKFLOW_IMPLEMENTATION_MAP.md` — reutilización de piezas existentes;
- `WORKFLOW_ENGINE_CONTRACT.md` — contrato del motor mínimo antes de DDL/server-side.

La cadena canónica permanece:

`Definición → Versión publicada → Disparador → Ejecución → Asignación → Tareas → Recursos → Evidencias → Revisión/Cierre → Historial`

## 1. Decisión arquitectónica vigente

Los procesos de negocio no tendrán motores independientes.

**Limpieza, Inspección, Mantenimiento, Check-in, Check-out y futuros procesos son tipos/configuraciones de un motor transversal de Flujos de Trabajo.**

Los recursos reutilizables viven fuera del flujo. El primer recurso transversal real es el **Banco Fotográfico**.

No se crearán motores paralelos de tareas, cámara, Storage, notificaciones o recurrencia para cada dominio.

## 2. Navegación ya implementada

Desde la pantalla principal existe el mosaico:

**🔄 Flujos de Trabajo**

Dentro están visibles:

- **➕ Creador de Flujos**;
- **🧩 Mis Flujos**;
- **📷 Banco Fotográfico**;
- **📋 Tareas**;
- **🕘 Historial**.

El acceso de **Banco Fotográfico** reutiliza directamente `photo-patterns.html` y la infraestructura fotográfica existente. No se ha creado un segundo banco ni otra cámara.

Los accesos legacy que todavía tienen funcionalidad no migrada, especialmente Limpieza, se mantienen temporalmente para evitar regresiones.

## 3. Creador de Flujos — estado actual

El mosaico **➕ Creador de Flujos** ya abre un asistente de autoría.

La primera versión implementada es deliberadamente un asistente paso a paso, no un editor gráfico de nodos.

El asistente cubre siete bloques conceptuales:

1. identidad del flujo;
2. ámbito;
3. activación;
4. asignación;
5. pasos y recursos;
6. cierre/revisión;
7. revisión final.

Actualmente permite definir, entre otros:

- nombre, tipo y descripción;
- ámbito conceptual;
- disparador manual, recurrente, fecha concreta o evento;
- asignación a responsable, rotación de ocupantes, persona fija, rol/capacidad o decisión manual;
- pasos como confirmación, evidencia fotográfica, checklist/formulario o documento;
- cierre automático, revisión humana o regla especializada del dominio;
- notificación al crear/cerrar.

### Límite intencional actual

El creador **todavía no publica ni persiste definiciones en Supabase**.

El borrador se conserva únicamente en `sessionStorage` y está presentado como borrador local. No crea:

- definiciones server-side;
- versiones publicadas;
- ejecuciones;
- tareas;
- notificaciones;
- cambios de permisos;
- registros de Limpieza.

Esta separación evita simular una funcionalidad backend que todavía no existe y permite validar primero la experiencia de autoría.

## 4. Banco Fotográfico — estado actual

El Banco Fotográfico ya dispone de infraestructura operativa reutilizable:

- `photo_patterns_v2`;
- editor manual de siluetas y `contour_data`;
- cámara fullscreen;
- alineación local;
- bucket privado existente;
- `photo_verification_runs_v2`;
- `photo_verification_items_v2`;
- revisión humana protegida;
- Edge Functions existentes de patrones y fotoverificación.

Conceptualmente queda desligado de Limpieza.

Un flujo podrá referenciar patrones del Banco Fotográfico y, al crear una ejecución, deberá congelarse la versión exacta del recurso utilizada.

## 5. Tareas — estado actual

No se ha creado una tabla nueva `workflow_tasks`.

`tenant_tasks_v2` sigue siendo el candidato principal para materializar trabajo de usuario, acompañado de:

- `tenant_task_actions_v2`;
- `tenant_task_history_v2`;
- `tenant_task_workflow_templates_v2` como subcomponente de transiciones, no como motor completo.

La decisión final debe ser aditiva y preservar histórico.

## 6. Limpieza — estado de transición

Limpieza será el primer dominio que se conectará al motor común.

Se conservan por ahora:

- `cleaning_plans_v2`;
- `cleaning_tasks_v2`;
- swaps;
- deudas no monetarias;
- auditoría y revisión por foto;
- solicitudes fotográficas;
- la ruta legacy `cleaning.html`.

Estas estructuras no se convierten en el motor universal.

Cuando el motor mínimo exista, Limpieza se conectará mediante un adaptador explícito que mantenga trazabilidad entre la ejecución genérica y las estructuras `cleaning_*` necesarias.

La UI legacy no se retirará hasta que el ciclo equivalente funcione extremo a extremo.

## 7. Contrato del motor mínimo

`WORKFLOW_ENGINE_CONTRACT.md` ya está versionado y define antes de cualquier DDL:

- identidad estable de definición;
- versiones publicadas inmutables;
- disparadores e idempotencia;
- resolución server-side de asignación;
- pasos ordenados;
- referencias versionadas a recursos;
- ejecuciones inmutables;
- reutilización de tareas/evidencias/notificaciones existentes;
- estados y cierres;
- RLS y autorización backend;
- concurrencia;
- adaptador de Limpieza.

Por tanto, la condición documental previa al primer DDL ya está cubierta.

## 8. Estado por módulo

| Módulo | Estado | Observación |
| --- | --- | --- |
| Flujos de Trabajo | Implementado | Hub visible desde Inicio |
| Creador de Flujos | Implementado como autoría local | Sin publicación server-side todavía |
| Mis Flujos | Pendiente | Depende de persistencia de definiciones/versiones |
| Banco Fotográfico | Operativo/reutilizado | Usa infraestructura existente |
| Tareas | Pendiente de integración genérica | Se evaluará reutilización de `tenant_tasks_v2` |
| Historial | Pendiente de capa transversal | No sustituye históricos existentes |
| Motor server-side | Pendiente | Sin DDL ni ejecución genérica aún |
| Adaptador Limpieza | Pendiente | Legacy preservado durante transición |

## 9. Cambios ya integrados

### PR #195 — Hub de Flujos de Trabajo

Introdujo:

- mosaico principal **🔄 Flujos de Trabajo**;
- pantalla contenedora con los cinco módulos;
- enlace real al Banco Fotográfico existente;
- mapa de implementación/reutilización;
- smoke tests del hub.

Merge en `main`: `37b0bd2520d7a57211f5e80df90fdc50bdde11f1`.

### PR #196 — Creador de Flujos

Introdujo:

- `WORKFLOW_ENGINE_CONTRACT.md`;
- asistente de autoría de siete pasos;
- borrador local explícito;
- enlace a Banco Fotográfico desde el creador;
- precache PWA del creador;
- smoke tests de navegación/protección.

Merge en `main`: `112dbbdbc78146bc7e2be52d83b5385bacfc0c02`.

Los checks requeridos del PR y del despliegue posterior pasaron correctamente.

## 10. Próximo incremento técnico

El siguiente incremento ya no debe crear más pantallas simuladas. Debe empezar el **motor mínimo persistente** de manera aditiva y segura.

Antes de publicar un flujo real, ese incremento debe incluir como mínimo:

1. migración mínima para definición estable + versión publicada + ejecución;
2. RLS positiva y negativa por organización/rol/ámbito;
3. servicio backend para crear/editar/publicar definiciones;
4. publicación inmutable de una versión;
5. activación manual inicial con `idempotency_key`;
6. resolución server-side de asignación;
7. enlace trazable a tareas existentes cuando sea viable;
8. snapshot de recursos/versiones;
9. histórico de eventos suficiente para reconstruir la ejecución;
10. pruebas de reintento para demostrar que no se duplican ejecución, tarea ni notificación.

La recurrencia automática puede incorporarse después de que la ejecución manual sea idempotente y auditable.

## 11. Reglas de no regresión

Durante los siguientes incrementos:

- no duplicar `photo_patterns_v2` por flujo;
- no crear una segunda cámara o bucket;
- no crear otro sistema de notificaciones;
- no reescribir histórico existente;
- no convertir `cleaning_plans_v2` en modelo universal;
- no retirar `cleaning.html` antes de sustitución funcional probada;
- no confiar en IDs/ámbitos enviados por cliente sin validación server-side;
- no presentar un borrador local como flujo publicado;
- no permitir que editar una definición cambie ejecuciones ya creadas.

## 12. Criterio para declarar el primer flujo real

Un flujo podrá considerarse realmente publicado solo cuando exista evidencia de que:

- la definición está persistida en servidor;
- existe una versión publicada inmutable;
- permisos/RLS bloquean accesos cruzados;
- una activación crea una única ejecución;
- la asignación se resuelve server-side;
- la tarea queda trazada hasta la ejecución;
- los recursos utilizados quedan congelados/versionados;
- el cierre deja histórico reproducible;
- los reintentos no duplican trabajo.

Hasta entonces, el Creador debe seguir presentándose como **autoría/borrador**, no como motor operativo completo.
