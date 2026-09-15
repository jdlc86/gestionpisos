# Contrato funcional — Limpieza, seguimiento y auditoría

## Objetivo de producto

El flujo de limpieza no existe solo para fiscalizar una tarea. Su objetivo es mantener seguimiento periódico del estado de la vivienda con baja carga operativa:
- el inquilino percibe que existe seguimiento;
- el sistema obtiene evidencia visual recurrente;
- se pueden detectar problemas de forma proactiva;
- el propietario mantiene contacto con el estado de su vivienda sin revisar todas las fotos.

## Tareas de limpieza

Cada piso puede tener un plan recurrente de limpieza. Las tareas se asignan a inquilinos con ocupación activa y pueden incluir evidencia fotográfica mediante patrones del piso.

Estados operativos existentes:
`pending -> accepted -> in_progress -> submitted`

La resolución de una limpieza y la resolución de cada evidencia se modelarán separadamente para no confundir tarea, auditoría y foto.

## Auditoría aleatoria

Al enviarse una limpieza, el sistema puede seleccionarla aleatoriamente para auditoría humana según una política configurable de la organización.

Reglas:
- auditada y no auditada son estados distintos de aprobada/rechazada;
- una limpieza no seleccionada no debe registrarse como aprobada por una persona;
- la selección debe quedar trazable;
- inicialmente la probabilidad será configurable y no adaptativa;
- la política futura puede aumentar o reducir muestreo, pero no debe introducirse sin evidencia de campo.

## Revisión por fotografía

Una limpieza auditada puede contener varias evidencias. El trabajador puede aprobar unas y rechazar otras.

La decisión es por foto, no obligatoriamente por run completo.

El rechazo exige motivo. Cada decisión conserva revisor y fecha.

El trabajador no tiene que enviar manualmente el informe final.

## Ventana de revisión y cierre automático

La ventana objetivo inicial es 24 horas desde el envío de la limpieza.

Al expirar:
- aprobar/rechazar queda deshabilitado;
- las fotos sin decisión quedan como `review_expired` (o equivalente explícito);
- `review_expired` no significa aprobada ni rechazada;
- el expediente se cierra automáticamente;
- se genera un único informe de la limpieza.

La duración debe ser configurable antes de considerarla política estable.

## Comunicación al inquilino

No se notifica cada decisión individual del trabajador.

El inquilino recibe un único resultado cuando el expediente se cierra, incluyendo las evidencias conformes, rechazadas con motivo y las que agotaron el plazo de revisión.

## IA y muestreo

El muestreo IA es independiente del muestreo humano.

La IA puede analizar una o varias fotografías seleccionadas para:
- limpieza;
- orden;
- posibles anomalías del inmueble;
- señales que justifiquen una comprobación posterior.

La IA produce observaciones/recomendaciones, no altera la evidencia original ni crea por sí sola una verdad histórica.

Las auditorías humanas servirán además como conjunto de validación para medir falsos positivos y falsos negativos de la IA.

## Seguimiento proactivo

Una posible anomalía detectada en una limpieza puede generar una solicitud posterior de comprobación.

Ejemplo:
`limpieza -> posible humedad -> comprobación dirigida en siguiente flujo -> persistencia/empeoramiento -> propuesta de incidencia`.

No elevar automáticamente una observación aislada a daño confirmado.

## Score del inquilino

El score, si se implementa, será secundario al seguimiento del inmueble.

No debe ser una valoración opaca generada directamente por IA. Debe calcularse mediante reglas explicables a partir de hechos trazables (cumplimiento, resultados de auditorías, recurrencia, etc.).

## Cambios entre compañeros y deuda

Se conserva el contrato existente:
- un inquilino puede solicitar a otro ocupante activo del mismo piso que asuma una tarea;
- requiere aceptación explícita;
- no cambia asignación hasta aceptación;
- queda auditado;
- la deuda de limpieza no representa dinero y conserva trazabilidad.

## Seguridad

- RLS obligatoria.
- Un inquilino solo accede al ámbito permitido.
- ADMIN/ROOT supervisan por organización.
- Las decisiones humanas quedan auditadas.
- No exponer service role ni claves de proveedores al frontend.
- No debilitar las políticas actuales de fotoverificación para implementar auditoría.

## Criterios antes de implementar UI definitiva

1. Separar semánticamente tarea de limpieza, auditoría y evidencia.
2. Soportar decisión por foto.
3. Definir cierre idempotente por vencimiento.
4. Evitar doble informe/notificación.
5. Mantener `review_expired` distinto de aprobación/rechazo.
6. Conservar compatibilidad con verificaciones históricas existentes.
7. Probar aislamiento entre organizaciones y pisos.
8. Solo después conectar la experiencia final del inquilino y del trabajador.
