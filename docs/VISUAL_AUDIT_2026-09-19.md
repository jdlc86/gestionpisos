# Auditoría visual global — 2026-09-19

## Objetivo

Extender a toda la PWA autenticada el patrón validado en Creador de Flujos: menos ruido, navegación separada de las acciones y jerarquía operativa consistente.

## Hallazgos

- La mayoría de módulos repetían Inicio en cabecera aunque la bottom navigation ya ofrece navegación global en móvil.
- Tema/iluminación aparecía en múltiples pantallas.
- Algunos submódulos mezclaban volver, Home y acciones operativas en el mismo bloque.
- Varios heroes ocupaban demasiado espacio antes de llegar al trabajo real.
- El botón primario global seguía usando negro/blanco mientras el Creador ya había validado azul para la acción principal.
- Los secundarios seguían usando relleno gris, compitiendo visualmente con las acciones.
- Banco Fotográfico y Fotoverificaciones mantenían paletas locales y media queries de tema independientes.
- El dashboard y el hub de Flujos seguían usando pictogramas emoji mientras la navegación global ya usa SVG monocromo.
- Algunas pantallas mostraban mensajes técnicos de implementación en lugar de información útil para el usuario.

## Política aplicada

- Tema/iluminación, MFA y Salir: solo Inicio.
- Navegación global móvil: Inicio / Cartera / Flujos / Tareas / Más.
- Home superior: oculto en móvil; se conserva únicamente como fallback discreto de escritorio.
- Volver contextual: icon-only con SVG, aria-label y title.
- Acción principal: azul compartido mediante --ui-action.
- Acción secundaria: outline neutro.
- Destructiva/rechazo: rojo semántico.
- Heroes: compactados globalmente y eliminados cuando duplicaban el título o el contenido operativo.
- Módulos de Inicio y Flujos: iconos SVG monocromos.
- Tema: controlado por html[data-theme="dark"] y la elección persistida desde Inicio.

## Pantallas auditadas

- Inicio
- Cartera
- Centro Operativo
- Incidencias
- Limpieza
- Gestión de Permisos
- Configuración y Recursos
- Flujos de Trabajo
- Creador de Flujos
- Mis Flujos
- Aplicaciones del flujo
- Tareas
- Banco Fotográfico
- Fotoverificaciones
- Cámara de fotoverificación
- Editor de silueta

Las pantallas de autenticación y recuperación conservan su shell específico. Cámara y Editor de silueta siguen excluidos de la bottom navigation por ser experiencias fullscreen.

## Seguridad

No se cambia schema, RLS, RPC, datos, roles, MFA/AAL ni lógica de negocio. Los cambios son HTML/CSS/JS de presentación y navegación.


## Ajuste posterior de Inicio

Tras validar la auditoría global en dispositivo real, Inicio queda como excepción de marca: recupera los pictogramas de color de las tarjetas que existían antes de la homogeneización SVG. La bottom navigation y los controles contextuales mantienen SVG monocromos. También se incorpora un pie institucional con copyright dinámico, versión canónica y build real de despliegue.
