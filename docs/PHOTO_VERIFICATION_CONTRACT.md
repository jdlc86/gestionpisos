# Contrato de fotoverificación

## Patrón real
Los patrones se capturan durante visitas reales al piso. ADMIN/empleado autorizado toma la fotografía de referencia y el sistema genera/almacena contornos o guía visual.

Los patrones:
- pertenecen a piso + zona/equipo/tipo;
- son versionados;
- pueden actualizarse sin alterar verificaciones históricas;
- admiten previsualización antes de publicarse.

## Cámara del inquilino
- Fullscreen.
- Guía/silueta superpuesta.
- Feedback visual en tiempo real según calidad de encuadre.
- El estado visual cambia cuando el encuadre entra en tolerancia.
- Encuadre correcto no equivale a estado correcto.

## Dos etapas
1. Validación de encuadre.
2. Evaluación del estado mediante IA o revisión humana.

## Política IA
Precedencia: empresa → piso → usuario/tipo de verificación.

Modos previstos:
- revisión humana;
- IA como recomendación;
- IA autoaprueba por encima de umbral y deriva el resto.

## Solicitudes aleatorias
ADMIN configura zonas/equipos elegibles, frecuencia, franjas, plazo y destinatarios. El sistema mantiene trazabilidad desde generación hasta resolución.
