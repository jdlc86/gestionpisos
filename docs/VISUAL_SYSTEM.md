# Sistema visual de GestionPisos

La referencia vigente es el patrón validado en Creador de Flujos: navegación discreta, contexto mínimo y acciones operativas claramente separadas.

## Jerarquía

- Navegación global: Inicio / Cartera / Flujos / Tareas / Más en la barra inferior móvil.
- Navegación contextual: volver a la pantalla padre mediante icono de flecha, sin convertirlo en CTA.
- Acción operativa principal: azul consistente mediante --ui-action.
- Acción secundaria: borde neutro, fondo transparente; no debe competir con la acción principal.
- Peligro / rechazo: rojo semántico.
- Estado: badges, texto o avisos; nunca se presenta como si fuera una acción.

## Cabeceras y ruido visual

- Las pantallas de trabajo muestran título y únicamente el contexto necesario.
- Los antiguos heroes grandes se sustituyen por contexto compacto cuando realmente aporta información.
- No se duplica Inicio en móvil: la navegación global inferior ya cumple esa función.
- En escritorio puede existir un acceso Home discreto como fallback cuando la barra inferior no se muestra.
- El control de tema/iluminación, MFA y Salir aparecen solo en Inicio.
- Cámara y Editor de siluetas siguen siendo experiencias fullscreen y no muestran la bottom navigation.
- Inicio y los submenús de navegación usan una familia propia de iconos SVG premium, con el mismo trazo y una placa champagne muy contenida. La bottom navigation y la navegación contextual permanecen monocromas y funcionales.

## Botones

- .primary: acción positiva/principal, azul.
- .secondary: acción secundaria neutra, outline.
- .ghost: acción de baja prominencia.
- .danger-soft: destructiva o peligrosa.
- Los textos deben ser breves y preferiblemente ocupar una sola línea.
- Tamaño táctil mínimo objetivo: 42–44 px en controles operativos.

## Superficies

- --ui-surface y --ui-subtle son los niveles principales.
- Las tarjetas de navegación premium usan fondo uniforme, borde fino, radio de 14 px y una sombra de baja intensidad.
- El acento champagne (--ui-accent) identifica marca e iconografía; nunca sustituye al azul de las acciones.
- Los estados bloqueados mantienen legibilidad y muestran una etiqueta explícita como “Próximamente” o “En preparación”.
- Los módulos consumen los tokens de app.css; no deben crear una segunda paleta global.

## Hero de marca

- El hero principal de Inicio usa fondo grafito/negro, texto blanco y subtítulo gris suave.
- Ese tratamiento oscuro se reserva para marca y modales realmente especiales; las pantallas operativas mantienen superficies claras/oscuras neutras según el tema.

## Inicio y pie institucional

- El claim de Inicio comunica el valor del producto, no decisiones internas de UX.
- El pie de Inicio muestra copyright con año calculado en tiempo de ejecución, versión de producto desde `docs/app-version.json` y build real estampada por el despliegue de GitHub Pages.
- La versión solo cambia mediante una modificación explícita del archivo de versión; cada despliegue genera un build `YYYY.MM.DD.GITHUB_RUN_NUMBER` y registra el commit corto.
- Aviso legal y Política de privacidad deben apuntar a páginas reales, nunca a enlaces vacíos.

## Tema

- html[data-theme="dark"] es la única autoridad visual de tema.
- La elección se realiza desde Inicio y se persiste globalmente.
- Los módulos no deben ofrecer toggles propios ni depender de una paleta paralela basada solo en prefers-color-scheme.

## Accesibilidad

- Los controles icon-only requieren aria-label y, cuando aporte valor en escritorio, title.
- Mantener focus-visible, contraste, safe areas y objetivos táctiles suficientes.
- Un icono decorativo usa aria-hidden="true".

## Componentes compartidos

Los tokens y componentes canónicos viven en docs/app.css: topbar, context-heading, context-back, page-subtitle, hero/page-context, card, status, primary, secondary, danger-soft, global-icon y badge.
