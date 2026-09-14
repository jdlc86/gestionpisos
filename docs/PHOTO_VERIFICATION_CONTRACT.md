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


## Estado de implementación — 2026-09-14

La cámara fullscreen está implementada y probada en móvil: cerrar, disparar, flash y cambio de cámara funcionan. La guía SVG aprobada puede encuadrarse con el banco real.

El alineador local rojo/amarillo/verde está probado. Se detectó un falso positivo al apuntar a un suelo texturizado; se corrigió el algoritmo para exigir estructura compatible y la prueba posterior confirmó que el suelo ya no llega a verde mientras el banco correctamente encuadrado sí. Los umbrales quedan congelados provisionalmente y no deben ajustarse sin nueva evidencia de campo.

### Persistencia — en curso

El flujo objetivo es: sesión autenticada → run → item → JPEG en bucket privado → metadatos de alineación → finalización del run. La ruta prevista es `organization_id/run_id/item_id.jpg`.

Se aplicaron remotamente las migraciones `20260914135759 beta0_photo_alignment_meta` y `20260914135829 beta0_photo_alignment_meta_check_add`. El trabajo NO está cerrado: falta reconciliar completamente esos cambios con Git, aplicar la restricción de ruta y verificar la finalización segura. No debilitar RLS ni crear patrones ficticios para desbloquear la UI.

### IA — aplazada

La comparación mediante IA se pospone hasta configurar las APIs/proveedores correspondientes. El desarrollo actual no debe depender de IA.
