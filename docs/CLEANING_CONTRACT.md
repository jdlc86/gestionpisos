# Contrato funcional — Limpieza, cambios y deudas

## Principio

Cada piso puede tener un plan de limpieza. Las tareas se asignan a inquilinos con ocupación activa y pueden incluir verificación manual, IA o híbrida.

## Estados de tarea

pending -> accepted -> in_progress -> submitted -> approved

Estados alternativos:
- rejected
- swapped
- missed
- cancelled

## Cambios entre compañeros

Un inquilino puede solicitar a otro inquilino del mismo piso que asuma una tarea concreta.

La solicitud:
- identifica tarea, solicitante y destinatario;
- solo puede dirigirse a un ocupante activo del mismo piso;
- requiere aceptación explícita;
- no cambia la asignación hasta ser aceptada;
- queda auditada.

## Deuda de limpieza

Cuando un compañero acepta realizar una tarea ajena, el sistema registra una deuda entre usuarios del mismo piso.

La deuda:
- tiene origen trazable en una tarea;
- no representa dinero;
- puede liquidarse mediante otra tarea compensatoria o por decisión administrativa;
- conserva histórico aunque se liquide.

## Verificación

Cada tarea define un modo:
- manual
- ai
- hybrid

La evidencia fotográfica será un módulo separado y versionado. El resultado de IA no debe modificar histórico ni sustituir la evidencia original.

## Seguridad

- Un inquilino solo ve tareas/deudas del ámbito permitido.
- No puede solicitar cambios a usuarios de otro piso.
- No puede crear o liquidar deudas arbitrariamente.
- ADMIN/ROOT supervisan por organización.
- La aprobación/rechazo de evidencias queda auditada.
- RLS obligatoria.

## Criterio Beta

No cerrar este módulo hasta probar:
1. tarea asignada a tenant A;
2. tenant A solicita cambio a tenant B del mismo piso;
3. tenant B acepta;
4. la tarea cambia de responsable;
5. se crea una deuda trazable;
6. usuario de otro piso no puede aceptar;
7. deuda no puede alterarse directamente por cliente;
8. aprobación/rechazo queda auditado.
