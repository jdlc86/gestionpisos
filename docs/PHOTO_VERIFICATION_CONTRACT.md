# Contrato de fotoverificación

## Patrón real
Los patrones se capturan durante visitas reales al piso. ADMIN/empleado autorizado toma la fotografía de referencia y dibuja manualmente una o varias siluetas/guías sobre ella. La geometría se guarda en `contour_data` y se reutiliza después en la cámara de verificación.

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

### Persistencia — validada

El flujo objetivo es: sesión autenticada → run → item → JPEG en bucket privado → metadatos de alineación → finalización del run. La ruta prevista es `organization_id/run_id/item_id.jpg`.

Las migraciones remotas `20260914135829 beta0_photo_alignment_meta_check_add`, `20260914140530 beta0_photo_item_storage_path_restrictive_min` y `20260914141923 beta0_remove_public_photo_submit_rpc`, junto con el source desplegado de `submit-photo-verification`, están reconciliadas con Git. La restricción de ruta está aplicada y el ciclo real Cocina → captura → JPEG privado → item → run `submitted` fue verificado positivamente el 2026-09-15. No debilitar RLS ni crear patrones ficticios para desbloquear la UI.

### Autoría de siluetas

La generación automática de contornos queda retirada del producto. La guía de encuadre se construye únicamente a partir de las siluetas manuales guardadas por usuarios con permiso de escritura.

La evaluación futura del estado puede incorporar revisión humana o IA, pero esa decisión es independiente de la creación de la silueta y no debe reintroducir generación automática de contornos.


### Persistencia frontend — validada

La cámara autenticada ya está conectada al flujo privado:
`pattern_id real → run → item → JPEG privado → alignment_meta → Edge Function → submitted`.

El frontend no acepta organización/piso arbitrarios: deriva ambos desde el patrón visible por RLS. Sin `pattern_id` válido, la captura permanece local y no escribe en Supabase.

La prueba positiva real ya existe: patrón Cocina con silueta manual, score persistido y JPEG privado coherente con `storage_path`.


### Limpieza de legado — 2026-09-15

El flujo activo ya no usa Gemini, Sobel, OpenCV, MobileSAM ni ONNX para crear o reconstruir la guía. La cámara renderiza directamente `photo_patterns_v2.contour_data`. Un patrón de verificación sin silueta manual guardada no puede iniciar la cámara de verificación.


### Historial y revisión humana — implementación 2026-09-15

La pantalla `photo-verifications.html` permite a ROOT/ADMIN consultar runs visibles por RLS, revisar la captura privada mediante URL firmada y filtrar por estado.

Las decisiones de aprobar/rechazar no abren UPDATE directo al frontend. Se envían a `review-photo-verification`, que exige sesión válida, rol ROOT/ADMIN y AAL2. La aplicación atómica de la decisión se ejecuta mediante `apply_photo_verification_review_v2`, accesible únicamente a `service_role`, y actualiza run + items + auditoría dentro de la misma transacción.


## Separación de propósito — limpieza vs. estado/mantenimiento (2026-09-15)

La infraestructura de patrón, silueta, cámara, alineación, JPEG privado e historial es compartida, pero el propósito de una captura debe ser explícito.

### Evidencia de limpieza

Pertenece a una tarea recurrente de limpieza. Puede ser seleccionada para auditoría humana o análisis IA. La auditoría humana admite decisión por fotografía y cierre automático del expediente. Aprobar/rechazar es una decisión de limpieza, no una propiedad universal de toda fotoverificación.

### Evidencia de estado/mantenimiento

Sirve para documentar o comprobar el estado físico del inmueble: humedad, grietas, mobiliario, equipos, reparación, etc. Puede ser solicitada por el sistema o por personal autorizado y realizada, según permisos, por trabajador o inquilino.

Estas evidencias NO deben mostrar aprobar/rechazar de limpieza.

### Un solo flujo para el inquilino

Cuando coincidan una limpieza y una comprobación de mantenimiento, la UI puede presentarlas dentro de una misma sesión para reducir fricción. Internamente cada evidencia conserva su propósito y reglas.

Ejemplo:
- Cocina — limpieza
- Baño — limpieza
- Salón — limpieza
- Bajo fregadero — comprobación de posible humedad

La cuarta captura no participa en el resultado de limpieza aunque se haya tomado en la misma sesión.

### Evolución

La comparación temporal es evidencia visual. No debe afirmar automáticamente deterioro, daño o responsabilidad. Una IA futura puede proponer observaciones que requieren reglas de confirmación posteriores.

### Compatibilidad

No reinterpretar verificaciones históricas existentes como limpiezas si no existe evidencia explícita de ese propósito. La introducción de nuevos tipos debe ser aditiva y versionada.
