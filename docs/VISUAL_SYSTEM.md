# Sistema visual de GestionPisos

La referencia visual de la aplicación es la pantalla **Configuración y Recursos**.

## Reglas

- El bloque principal/hero conserva fondo negro o casi negro tanto en tema claro como oscuro.
- Las superficies de contenido usan dos niveles: `--ui-surface` y `--ui-subtle`, con borde fino y sin sombras decorativas pesadas.
- Radio principal: 8–12 px. No se apilan capas de overrides para conseguir el aspecto final.
- Los iconos de módulos son SVG lineales dentro de una caja compacta con color semántico suave. No se usan emojis como iconografía principal del dashboard.
- Los botones primarios son negros/blancos según tema; los secundarios son grises; las acciones destructivas usan rojo semántico.
- Los modales críticos usan fondo negro, contraste alto y backdrop oscuro.
- El tema oscuro se controla con `html[data-theme="dark"]`; no debe coexistir una segunda capa visual basada en `prefers-color-scheme` dentro de los CSS de módulos.
- Los CSS de módulo consumen los tokens de `app.css` y solo definen layout o componentes propios. No deben duplicar una segunda paleta global.

## Tokens compartidos

Los tokens canónicos viven en `docs/app.css`: `--ui-bg`, `--ui-surface`, `--ui-subtle`, `--ui-border`, `--ui-text`, `--ui-muted`, `--ui-hero`, `--ui-primary`, `--ui-danger`, `--ui-success`, `--ui-warning` y `--ui-info`.

Cuando se añada una nueva pantalla, se debe partir de estos tokens y de los componentes base (`topbar`, `hero`, `card`, `status`, `primary`, `secondary`, `danger-soft`, `global-icon`) antes de crear estilos específicos.
