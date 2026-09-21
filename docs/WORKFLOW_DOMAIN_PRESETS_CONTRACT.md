# Contrato WF-08 · Presets de dominio en el Creador

## Objetivo

WF-08 reduce fricción al elegir un tipo de flujo sin crear reglas de ejecución nuevas.

Un preset es únicamente una **sugerencia inicial de autoría en frontend**. El motor, los RPC, las validaciones server-side y los adaptadores de dominio existentes siguen siendo la autoridad.

## Reglas obligatorias

1. El preset se aplica al seleccionar un tipo compatible durante una creación/edición interactiva.
2. Solo rellena campos todavía vacíos. No sobrescribe valores que el usuario ya haya configurado.
3. Cargar una definición o borrador existente mediante `applyDraft()` no reaplica presets.
4. Cambiar de tipo no borra silenciosamente decisiones anteriores; las incompatibilidades siguen siendo limpiadas por los contratos UI/backend ya existentes.
5. No se preseleccionan entidades reales: piso, habitación, ocupación, persona fija ni recurso fotográfico.
6. No se inventa una fecha/hora programada. Si un preset propone recurrencia, el usuario debe elegir el primer instante.
7. `custom`, pagos, reclamaciones y fianzas no reciben preset WF-08.
8. Publicación y ejecución siguen pasando por las mismas validaciones backend. Un preset nunca convierte una configuración inválida en publicable por ocultación de UI.

## Presets iniciales

| Tipo | Ámbito sugerido | Activación sugerida | Asignación sugerida | Pasos/cierre sugeridos |
| --- | --- | --- | --- | --- |
| Limpieza | Piso | Recurrente · semanal | Ocupantes activos en rotación | El adaptador existente conserva Aceptar, sin pasos genéricos y `domain_adapter` |
| Inspección | Piso | Manual | Responsable operativo | Foto + revisión humana |
| Mantenimiento | Piso | Evento `incident.created` | Responsable operativo | Contrato WF-05: Aceptar + `domain_adapter` |
| Check-in | Piso | Evento `occupancy.created` | Responsable operativo | Contrato WF-04: Aceptar + `domain_adapter` |
| Check-out | Piso | Evento `occupancy.offboarded` | Responsable operativo | Contrato WF-04: Aceptar + `domain_adapter` |

La inspección sugerida es una inspección manual genérica. El usuario puede cambiarla a la variante posterior a incidencia (`incident.resolved`), que continúa sometida al contrato WF-05 y exige evidencia.

## Fuera de alcance

- nuevas tablas, migraciones o Edge Functions;
- un segundo motor de plantillas;
- presets para WF-06/WF-07;
- selección automática de recursos o destinos;
- ejecución automática al seleccionar un preset;
- retirada de accesos legacy (WF-09).

## Verificación

WF-08 debe añadir smoke/regresión de frontend que pruebe al menos:

- existencia de los cinco presets;
- aplicación solo a campos vacíos;
- Inspección activa Foto + `human_review`;
- Limpieza propone semanal pero no inventa `scheduledAt`;
- Mantenimiento/Check-in/Check-out usan los eventos ya soportados;
- `custom` no recibe preset;
- la carga de un flujo existente no llama al preset.
