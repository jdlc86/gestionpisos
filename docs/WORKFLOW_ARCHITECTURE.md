# Arquitectura funcional — Flujos de Trabajo

## Estado de esta decisión

Este documento define la arquitectura objetivo del módulo transversal **Flujos de Trabajo** de GestionPisos.

Es una decisión de producto y arquitectura. No implica que todos los componentes descritos estén implementados todavía.

La intención es evitar que Limpieza, Inspecciones, Mantenimiento, Check-in, Check-out u otros procesos futuros desarrollen motores independientes para tareas, recurrencias, asignaciones, evidencias y revisiones.

La regla principal es:

> **Los procesos de negocio son configuraciones de un motor común de flujos; los recursos reutilizables viven fuera de esos procesos.**

---

## 1. Objetivo

Crear un sistema escalable en el que nuevos procesos puedan componerse reutilizando piezas existentes, sin duplicar infraestructura.

Ejemplos de procesos que deben poder construirse sobre el mismo motor:

- limpieza periódica;
- inspección de vivienda;
- comprobación de humedad;
- mantenimiento preventivo;
- comprobación posterior a una reparación;
- entrada de inquilino;
- salida de inquilino;
- inventario;
- revisión extraordinaria;
- cualquier flujo futuro basado en tareas, evidencias o aprobaciones.

El motor debe poder responder siempre a las mismas preguntas:

1. ¿Qué proceso existe?
2. ¿Qué lo activa?
3. ¿Sobre qué ámbito se ejecuta?
4. ¿Quién debe realizarlo?
5. ¿Qué pasos tiene?
6. ¿Qué recursos reutilizables consume?
7. ¿Qué evidencias produce?
8. ¿Cómo se revisa o cierra?
9. ¿Qué queda en el histórico?

---

## 2. Navegación de producto

### Pantalla principal

La pantalla principal de GestionPisos tendrá un mosaico de primer nivel:

**🔄 Flujos de Trabajo**

Los conceptos de Limpieza e Inspecciones dejan de necesitar mosaicos independientes de primer nivel cuando estén integrados completamente en el nuevo motor.

Esto no significa eliminar sus reglas de negocio. Significa que pasan a ser **tipos de flujo** construidos sobre una infraestructura compartida.

### Dentro de Flujos de Trabajo

Se definen cinco mosaicos principales:

#### ➕ Creador de Flujos

Asistente para crear o editar una receta de trabajo.

Define:

- nombre y propósito;
- ámbito;
- activación;
- asignación;
- pasos;
- recursos consumidos;
- reglas de revisión;
- cierre y resultados.

#### 🧩 Mis Flujos

Inventario de definiciones existentes.

Permite consultar y administrar, según permisos:

- activos;
- pausados;
- borradores;
- versiones;
- próxima ejecución;
- ámbito;
- reglas de asignación;
- historial relacionado.

Acciones futuras posibles:

- editar;
- duplicar;
- pausar/reactivar;
- ejecutar ahora;
- versionar;
- archivar sin destruir histórico.

#### 📷 Banco Fotográfico

Repositorio visual reutilizable de cada vivienda.

Organización conceptual:

`Piso → Zona → Elemento → Patrón de referencia → Versiones`

Ejemplo:

`Piso A → Cocina → Fregadero → Patrón v3`

El Banco Fotográfico no pertenece a Limpieza, Inspecciones ni Mantenimiento.

Es un **recurso transversal** que cualquiera de esos flujos puede consumir.

La interfaz puede permitir navegar también hacia evidencias históricas relacionadas con un elemento, pero técnicamente las evidencias producidas por una ejecución siguen perteneciendo a esa ejecución. Esto evita mezclar patrón de referencia con evidencia histórica.

#### 📋 Tareas

Trabajo concreto que debe realizar una persona.

Una tarea no es el flujo. Es una unidad de trabajo creada por una **ejecución concreta** del flujo.

Ejemplo:

`Limpieza Piso A · 21/09 · Juan · Pendiente`

La vista debe poder adaptarse al rol del usuario:

- "Mis tareas" para ejecutores;
- supervisión de tareas para empleados autorizados, ADMIN y ROOT;
- filtros por piso, estado, tipo de flujo, responsable y fecha.

#### 🕘 Historial

Registro de lo que realmente ocurrió.

Incluye, según permisos:

- ejecuciones;
- tareas;
- evidencias;
- decisiones;
- revisiones;
- cambios de estado;
- cierres;
- resultados;
- auditoría.

El historial no se reconstruye a partir de la definición actual del flujo: conserva la versión y recursos que fueron utilizados realmente.

---

## 3. Conceptos fundamentales

### 3.1 Recurso

Pieza reutilizable que un flujo puede consumir.

Primer recurso real de GestionPisos:

**Banco Fotográfico**.

Recursos futuros posibles:

- formularios;
- checklists;
- plantillas documentales;
- firmas;
- lecturas de contadores;
- instrucciones;
- catálogos de elementos.

Un recurso no debe conocer qué flujos lo utilizan.

### 3.2 Definición de Flujo

Es la **receta**.

Ejemplos:

- Limpieza semanal de una vivienda;
- Inspección trimestral de una vivienda;
- Check-out de una habitación;
- Revisión posterior a reparación;
- Comprobación de humedad bajo fregadero.

La definición describe el comportamiento, pero no representa una ejecución concreta.

### 3.2.1 Aplicación concreta

Es la vinculación entre una **versión publicada de la receta** y una entidad real.

Ejemplos:

- `Limpieza semanal v1 → Piso A`;
- `Inspección de habitación v2 → Piso B → Habitación 3`;
- `Check-out v1 → ocupación vigente X`.

El Creador solo define el tipo lógico de ámbito. El UUID del piso, habitación u ocupación se selecciona después, al aplicar la versión publicada. Así una misma receta puede reutilizarse en varios destinos sin duplicarse.


### 3.3 Disparador

Regla que decide cuándo debe iniciarse una ejecución.

Tipos previstos:

- manual;
- fecha concreta;
- recurrencia;
- evento del sistema.

Ejemplos:

- cada lunes;
- cada cuatro semanas;
- el día de salida de un inquilino;
- 48 horas después de cerrar una reparación;
- cuando un empleado autorizado pulse "Ejecutar ahora".

La automatización forma parte de la definición del flujo. No necesita ser un módulo independiente de primer nivel.

### 3.4 Regla de asignación

Define quién ejecutará el trabajo.

Tipos previstos:

- usuario fijo;
- responsable operativo del piso;
- empleado asignado;
- ocupante activo;
- rotación entre ocupantes activos;
- rotación entre una lista explícita;
- selección manual al lanzar la ejecución.

La asignación debe resolverse server-side y quedar congelada en la ejecución creada.

### 3.5 Paso

Unidad lógica de una definición de flujo.

Ejemplos:

- aceptar tarea;
- leer instrucciones;
- realizar captura fotográfica;
- completar checklist;
- introducir lectura;
- confirmar operación;
- solicitar firma;
- enviar resultado.

Los pasos deben poder enlazar recursos reutilizables.

### 3.6 Ejecución

Es una instancia concreta de una definición de flujo.

Ejemplo:

Definición:

`Limpieza semanal Piso A`

Ejecuciones:

- `07/09 → Pedro → completada`
- `14/09 → María → completada`
- `21/09 → Juan → pendiente`
- `28/09 → Laura → futura`

La ejecución debe conservar qué versión de la definición la originó.

### 3.7 Tarea

Trabajo asignado a una persona dentro de una ejecución.

Un flujo simple puede crear una sola tarea.

Un flujo futuro más complejo puede crear varias tareas para diferentes responsables.

### 3.8 Evidencia

Resultado producido durante una ejecución.

Puede ser:

- fotografía;
- formulario;
- lectura;
- documento;
- firma;
- decisión;
- comentario estructurado.

La evidencia original no debe alterarse para reflejar resultados posteriores de IA o revisión humana.

### 3.9 Resultado e histórico

El resultado resume el cierre de una ejecución.

El histórico conserva hechos, no solo el estado final.

Debe ser posible saber:

- qué flujo y versión se ejecutaron;
- qué reglas estaban vigentes;
- quién fue asignado;
- qué recursos y versiones se utilizaron;
- qué evidencia se produjo;
- quién revisó;
- qué decisiones se tomaron;
- cuándo ocurrió cada cambio.

---

## 4. Cómo se unen las piezas

La cadena general es:

`Definición de Flujo`

→ se publica una **Versión inmutable**

→ se crea una **Aplicación concreta** sobre una entidad real

→ el **disparador** de esa aplicación decide cuándo ejecutarla

→ se crea una **Ejecución**

→ la **regla de asignación** resuelve responsables

→ se crean una o varias **Tareas**

→ cada tarea ejecuta **Pasos**

→ los pasos pueden consumir **Recursos**

→ se producen **Evidencias**

→ se aplican reglas de **revisión/cierre**

→ todo queda en **Historial**.

La relación debe ser referencial y versionada, no mediante copia arbitraria de datos.

---

## 5. Ejemplo completo — Limpieza periódica

### Definición

**Nombre:** Limpieza semanal

**Ámbito lógico:** Piso

**Aplicación de ejemplo:** Piso A

**Disparador:** cada lunes

**Asignación:** rotación entre ocupantes activos

**Pasos:**

1. aceptar tarea;
2. consultar zonas requeridas;
3. realizar fotografías guiadas;
4. enviar limpieza.

**Recursos fotográficos:**

- Cocina / Fregadero;
- Cocina / Encimera;
- Baño / Lavabo;
- Salón / Suelo.

**Revisión:** política de auditoría configurada.

**Cierre:** generar resultado único y conservar evidencias.

### Juan cada cuatro semanas

No se crea una regla específica "Juan limpia cada 4 semanas" si el comportamiento real proviene de una rotación.

Si existen cuatro ocupantes activos y el flujo se ejecuta semanalmente:

- semana 1 → Juan;
- semana 2 → Pedro;
- semana 3 → María;
- semana 4 → Laura;
- semana 5 → Juan.

La periodicidad individual de Juan es una consecuencia de:

`recurrencia semanal + regla de rotación + cuatro participantes`.

Esto evita mantener reglas redundantes y reduce errores cuando entra o sale un ocupante.

Si el negocio realmente exige una periodicidad fija para una persona concreta, se modelará con la misma infraestructura genérica:

- disparador: cada cuatro semanas;
- asignación: usuario fijo Juan.

No se necesita una arquitectura especial de "planes de limpieza".

---

## 6. Ejemplo — Mantenimiento

**Flujo:** Comprobación posterior a reparación de fregadero

**Disparador:** evento `incident.resolved` publicado al cerrar la reparación

**Asignación:** responsable operativo del piso

**Recurso:**

`Banco Fotográfico → Cocina → Fregadero`

**Pasos:**

1. abrir tarea;
2. tomar fotografía usando el patrón vigente;
3. responder checklist de comprobación;
4. enviar.

El flujo reutiliza el mismo Banco Fotográfico que Limpieza sin depender de Limpieza.

La reparación conserva su expediente en `incidents_v2`, pero la gestión operativa y la inspección posterior producen ejecuciones y tarjetas distintas del mismo motor. El vínculo con el expediente es explícito; la resolución usa el outbox común y nunca crea la inspección dentro de la transacción de negocio.

---

## 7. Ejemplo — Check-out

**Flujo:** Salida de inquilino

Puede consumir varios tipos de recursos:

- patrones fotográficos de Cocina, Baño, Salón y Habitación;
- formulario de lectura de contadores;
- inventario;
- documento de entrega;
- firma.

El motor ejecuta la receta y conserva cada evidencia con su propósito.

No se necesita desarrollar un motor específico de Check-out.

---

## 8. Banco Fotográfico

### Propósito

Ser la memoria visual estructurada y reutilizable de una vivienda.

### Jerarquía conceptual

`Organización → Piso → Zona → Elemento → Patrón → Versión`

### Patrón

Un patrón contiene, según el sistema ya existente:

- fotografía de referencia;
- etiqueta/nombre;
- zona;
- geometría de silueta en `contour_data`;
- versión;
- autoría;
- estado de publicación/actividad.

La autoría de siluetas sigue siendo manual. No se reintroduce generación automática de contornos.

### Versionado

Modificar un patrón crea una nueva versión lógica sin reinterpretar evidencias históricas.

### Congelación de recursos en una ejecución

La receta puede declarar que necesita evidencia fotográfica, pero los patrones ligados físicamente a una vivienda se seleccionan en la aplicación concreta. Cuando una ejecución se genera, debe quedar asociada a la **versión exacta** del patrón realmente utilizada.

Ejemplo:

- ejecución del 21/09 usa `Fregadero v3`;
- el 22/09 se publica `Fregadero v4`;
- el histórico del 21/09 sigue apuntando a `v3`.

Esta regla es obligatoria para que el histórico sea reproducible.

### Relación con evidencias históricas

La UI del Banco Fotográfico puede ofrecer una vista cronológica de capturas relacionadas con una zona o elemento.

Sin embargo:

- el **patrón** sigue siendo un recurso;
- la **foto capturada** sigue siendo evidencia de una ejecución;
- el vínculo entre ambos permite navegar la evolución temporal sin confundir responsabilidades.

---

## 9. Creador de Flujos

### Primera versión

No se requiere inicialmente un editor gráfico de nodos.

La primera versión será un asistente paso a paso, más simple de validar y mantener.

### Pasos del asistente

#### Paso 1 — Identidad

- nombre;
- descripción;
- tipo/categoría;
- ámbito.

#### Paso 2 — Activación

- manual;
- fecha;
- recurrencia;
- evento.

#### Paso 3 — Asignación

- usuario fijo;
- responsable;
- empleado;
- ocupante;
- rotación;
- selección manual.

#### Paso 4 — Pasos del flujo

Ordenar y configurar las acciones que debe realizar el ejecutor.

#### Paso 5 — Recursos

Seleccionar elementos existentes del Banco Fotográfico u otros recursos futuros.

#### Paso 6 — Revisión y cierre

Definir:

- revisión humana;
- IA como recomendación cuando corresponda;
- ventanas temporales;
- cierre automático;
- notificaciones;
- informe o resultado.

#### Paso 7 — Resumen y publicación

Antes de activar un flujo debe mostrarse una previsualización legible de la receta completa.

---

## 10. Mis Flujos

Cada tarjeta de flujo debería mostrar como mínimo:

- nombre;
- estado;
- ámbito;
- activación;
- regla de asignación;
- número de pasos;
- recursos asociados;
- próxima ejecución si existe.

Estados de definición previstos:

- `draft`;
- `active`;
- `paused`;
- `archived`.

Archivar no destruye ejecuciones históricas.

---

## 11. Separación entre definición y ejecución

Esta separación es estructural.

### Definición

La receta editable.

### Ejecución

Una fotografía inmutable de la receta relevante en un momento determinado.

Si una definición cambia después de generar una ejecución, la ejecución ya creada no debe mutar silenciosamente.

Cambios incompatibles deben aplicarse solo a nuevas ejecuciones o mediante una operación explícita y auditable.

---

## 12. Reutilización de una misma evidencia

Una captura física puede ser útil para más de un propósito, pero no debe perderse la semántica.

Ejemplo:

Durante una limpieza se fotografía el fregadero y existe además una comprobación pendiente de humedad.

Puede evitarse pedir al usuario dos fotografías idénticas si las reglas lo permiten, pero internamente debe quedar claro:

- qué ejecución originó la captura;
- qué otros propósitos la consumieron;
- qué decisión corresponde a Limpieza;
- qué observación corresponde a Mantenimiento.

Una aprobación de limpieza nunca debe convertirse automáticamente en una aprobación de mantenimiento.

---

## 13. Integración con lo ya construido

No se parte de cero.

### Fotoverificación existente

Se conserva y reutiliza:

- patrones reales por piso/zona;
- editor manual de siluetas;
- `contour_data`;
- cámara fullscreen;
- alineación local;
- JPEG en Storage privado;
- metadatos de alineación;
- runs/items actuales;
- historial de fotoverificación;
- revisión humana segura;
- RLS y Edge Functions existentes.

La herramienta actual de creación de patrones pasa conceptualmente a formar parte de:

`Flujos de Trabajo → Banco Fotográfico`.

### Limpieza existente

Se conserva su contrato de negocio:

- tareas;
- estados;
- intercambio controlado;
- deuda no monetaria;
- auditoría aleatoria;
- revisión por evidencia;
- cierre automático;
- comunicación final.

Pero Limpieza deja de ser propietaria de la infraestructura fotográfica y, progresivamente, se representa como una definición/configuración del motor común.

### Historial existente

No reinterpretar datos históricos antiguos como nuevas categorías si no existe evidencia explícita.

La migración debe ser aditiva y versionada.

---

## 14. Modelo lógico propuesto

Los nombres finales de tablas se decidirán después de auditar el esquema actual. Conceptualmente se necesitan entidades equivalentes a:

- `workflow_definitions` — receta;
- `workflow_definition_versions` — versiones publicadas;
- `workflow_applications` — vinculación de una versión publicada con una entidad real de su ámbito;
- `workflow_triggers` — reglas de activación;
- `workflow_assignment_rules` — reglas de asignación;
- `workflow_steps` — pasos ordenados;
- `workflow_resource_links` — enlaces a recursos reutilizables;
- `workflow_runs` — ejecuciones;
- `workflow_tasks` — trabajo asignado;
- `workflow_evidence` — evidencias producidas o vinculadas;
- `workflow_reviews` — decisiones/revisiones cuando apliquen;
- `workflow_events` — historial/auditoría del ciclo de vida.

El Banco Fotográfico conserva sus entidades especializadas de patrones/versiones y Storage.

### Regla importante

No crear tablas nuevas con estos nombres hasta completar un mapeo contra las tablas actuales.

Primero debe identificarse qué estructuras existentes pueden generalizarse sin perder histórico ni introducir duplicidad.

---

## 15. Motor de ejecución

Responsabilidades del motor:

1. detectar o recibir un disparador;
2. seleccionar una aplicación concreta;
3. cargar la versión publicada asociada y validar su ámbito real;
4. resolver la asignación server-side;
5. congelar recursos/versiones relevantes;
6. crear ejecución y tareas de forma idempotente;
7. controlar transiciones de estado válidas;
8. recibir evidencias mediante vías autorizadas;
9. lanzar revisión/cierre cuando proceda;
10. registrar eventos y auditoría.

### Idempotencia

Un mismo disparador no debe generar dos ejecuciones equivalentes por reintentos, cron duplicado o problemas de red.

### Seguridad

El cliente nunca decide por sí solo:

- organización;
- piso accesible;
- usuario asignado;
- versión de patrón no autorizada;
- transición privilegiada;
- resultado de revisión administrativa.

Las decisiones sensibles deben resolverse o validarse server-side con RLS y/o servicio autorizado.

---

## 16. Permisos

El motor debe respetar los contratos actuales de GestionPisos.

Como principio:

- ROOT supervisa globalmente según contrato;
- ADMIN opera dentro de su organización y de sus permisos;
- empleados solo acceden a pisos/operaciones autorizados;
- inquilinos solo ven y ejecutan tareas permitidas de su ámbito;
- recursos privados no se vuelven públicos para facilitar un flujo;
- acciones críticas permanecen auditadas;
- AAL2 se exige donde el contrato de seguridad lo requiera.

Un flujo no puede ampliar permisos del usuario que lo ejecuta.

---

## 17. Qué no debe hacerse

Para preservar la escalabilidad:

- no crear un motor de recurrencia separado para Limpieza;
- no crear otro motor de tareas para Mantenimiento;
- no duplicar patrones fotográficos por cada flujo;
- no copiar una imagen de referencia dentro de cada tarea;
- no hacer que Banco Fotográfico conozca reglas de Limpieza;
- no guardar "Juan cada 4 semanas" si es solo una consecuencia de una rotación;
- no modificar ejecuciones históricas cuando cambia la receta actual;
- no mezclar aprobación de limpieza con diagnóstico de mantenimiento;
- no convertir IA en autoridad histórica única;
- no eliminar histórico al archivar una definición;
- no crear tablas paralelas antes de mapear el esquema existente.

---

## 18. Estrategia de evolución

### Fase 1 — Arquitectura y mapeo

- congelar esta decisión conceptual;
- inventariar tablas, Edge Functions y pantallas existentes de tareas, limpieza y fotoverificación;
- mapear qué se reutiliza;
- detectar duplicidades;
- definir contrato del motor.

### Fase 2 — Navegación

- crear mosaico principal **Flujos de Trabajo**;
- crear pantalla contenedora con los cinco mosaicos;
- mover conceptualmente el acceso a patrones bajo **Banco Fotográfico** sin romper URLs existentes.

### Fase 3 — Banco Fotográfico

- adaptar la UI existente de patrones al nuevo contexto;
- conservar cámara/editor/Storage/RLS;
- formalizar navegación Piso → Zona → Elemento → Patrón → Versiones.

### Fase 4 — Motor mínimo

- definición/versiones;
- activación manual y recurrente;
- asignación básica;
- pasos;
- recursos;
- ejecución idempotente;
- tareas.

### Fase 5 — Migrar Limpieza como primer flujo

- representar el comportamiento actual con el nuevo motor;
- mantener compatibilidad histórica;
- eliminar dependencia de introducir UUID manualmente en la UI;
- validar ciclo completo con usuarios reales de prueba.

### Fase 6 — Generalización

- Inspecciones;
- Mantenimiento;
- Check-in/Check-out;
- nuevos recursos y pasos.

---

## 19. Criterios de aceptación de la arquitectura

La arquitectura se considera correctamente aplicada cuando:

1. un patrón fotográfico puede ser utilizado por varios tipos de flujo sin duplicarse;
2. crear un nuevo tipo de proceso no exige crear otro motor de tareas/recurrencias;
3. definición y ejecución están claramente separadas;
4. una ejecución conserva versiones exactas de definición y recursos;
5. una rotación se modela como regla, no como muchas recurrencias personales redundantes;
6. tareas y evidencias tienen trazabilidad hasta la ejecución que las originó;
7. el histórico no cambia cuando se edita un flujo;
8. los permisos se resuelven server-side y RLS sigue siendo efectiva;
9. la fotoverificación existente se reutiliza en vez de reimplementarse;
10. Limpieza puede expresarse como configuración del motor común;
11. Mantenimiento o Check-out pueden reutilizar las mismas piezas sin depender de Limpieza;
12. las migraciones son aditivas y no reinterpretan histórico sin evidencia.

---

## 20. Resumen ejecutivo

La arquitectura objetivo puede resumirse así:

**Recurso** = pieza reutilizable.

**Flujo** = receta.

**Disparador** = cuándo se ejecuta.

**Asignación** = quién lo hace.

**Paso** = qué debe hacer.

**Ejecución** = una instancia concreta de la receta.

**Tarea** = trabajo asignado a una persona.

**Evidencia** = resultado producido.

**Historial** = hechos conservados y auditables.

Cadena:

`Flujo → Versión publicada → Aplicación concreta → Disparador → Ejecución → Asignación → Tareas → Recursos → Evidencias → Revisión/Cierre → Historial`

Esta separación permite que GestionPisos añada nuevos procesos sin multiplicar subsistemas independientes y convierte la infraestructura fotográfica ya construida en una capacidad transversal del producto.
