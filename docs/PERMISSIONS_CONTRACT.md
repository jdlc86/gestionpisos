# Contrato de permisos

Esta matriz es el mínimo de seguridad. Las implementaciones pueden restringir más, nunca ampliar silenciosamente.

| Acción | ROOT | ADMIN autorizado | ADMIN sin permiso exclusivo | Responsable piso | Otro empleado | Propietario | Inquilino |
|---|---|---|---|---|---|---|---|
| Modificar ROOT | NO | NO | NO | NO | NO | NO | NO |
| Crear/dar de baja piso | Sí | Sí | No | No | No | No | No |
| Transferir permiso exclusivo admin | Sí | Según política | Solicitar | No | No | No | No |
| Gestionar operadores de emergencia | Sí, con MFA `aal2` | No | No | No | No | No | No |
| Ver piso | Sí | Sí | Sí | Sí | Según asignación/lectura | Solo propio | Solo residencia vigente |
| Escritura operativa piso | Sí | Sí | Sí según ámbito admin | Sí | No por defecto | No | Solo flujos propios |
| Solicitar escritura sobre piso | — | Sí | Sí | — | Sí | No | No |
| Conceder delegación de escritura | Sí | Sí | Según ámbito | Sí | No | No | No |
| Aprobar/rechazar acceso QR | Sí | Sí | Según permiso | No | No | No | No |
| Bloquear usuario | Sí | Sí según ámbito | Según permiso | No | No | No | No |
| Cambiar rol empleado | Sí | Sí autorizado | Según permiso | No | No | No | No |
| Crear patrones de fotoverificación | Sí | Sí | Según permiso | Según configuración | No por defecto | No | No |
| Revisar fotoverificación | Sí | Sí | Según permiso | Sí si asignado | Sí si delegado | Consulta propia autorizada | Ver resultado propio |
| Broadcast institucional | Sí | Sí autorizado | Según permiso | No por defecto | No por defecto | No | No |

## Reglas adicionales

- Un piso tiene un responsable operativo principal de escritura.
- Otros empleados son lectura por defecto y solicitan delegación.
- Delegaciones pueden expirar automáticamente.
- ROOT/ADMIN conservan capacidad excepcional para evitar bloqueos operativos, siempre auditada.
- El acceso de propietario se limita a recursos de sus pisos.
- El acceso de inquilino está limitado a su ocupación vigente y flujos propios.
- El ADMIN no puede autoelevarse por encima de su autorización ni alterar ROOT.
- Solo ROOT con `aal2` puede designar, activar/desactivar o cambiar la capacidad `can_recover_root` de operadores de emergencia.
- La gestión de operadores se realiza mediante backend privilegiado; el cliente no tiene acceso directo a `platform_operators`.
- Los operadores de emergencia no adquieren por ello ningún rol operativo ni permisos sobre viviendas, personas o administración ordinaria de GestionPisos.
