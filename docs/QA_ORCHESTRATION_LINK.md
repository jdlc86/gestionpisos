# Enlace con la plataforma de orquestación QA

## Propósito

GestionPisos / Allaiso dispone de un repositorio separado destinado a definir la futura infraestructura de QA masivo y orquestación de pruebas:

- Repositorio canónico: https://github.com/jdlc86/Allaiso-QA-Orchestrator
- Nombre lógico: **Allaiso-QA-Orchestrator**

Este repositorio externo existe para concentrar arquitectura, contratos, esquemas y evolución de una plataforma capaz de coordinar pruebas E2E, navegadores, agentes locales, evidencias y ejecuciones paralelas sin acoplar esa infraestructura al código de producto.

## Estado actual

**Estado: PUBLIC_SMOKE_VERIFIED / E2E AUTENTICADO NO ACTIVO.**

A 22/09/2026:

- el repositorio existe y mantiene la infraestructura QA como fuente de verdad;
- el runner Windows `allaiso-qa-JDIA` está conectado y el navegador gestionado por OpenClaw ha sido validado;
- el handshake del nodo pasó en el run `35787573517` y el smoke público de GestionPisos pasó en el run `35787573540` del repositorio de orquestación;
- el smoke público verifica navegación real, lectura semántica y captura de evidencia sin autenticación ni mutaciones;
- las sesiones autenticadas, credenciales y escrituras sobre el AUT continúan desactivadas;
- ninguna prueba de la batería final puede marcarse como PASS únicamente por el smoke público; los Gates siguen rigiéndose por `docs/WORKFLOW_FINAL_E2E_BATTERY.md` hasta activar explícitamente la ejecución autenticada correspondiente.

## Reparto de autoridad

- **GestionPisos** sigue siendo la fuente de verdad del producto, seguridad, permisos, datos, workflows y criterios de aceptación.
- **Allaiso-QA-Orchestrator** será la fuente de verdad de la infraestructura de orquestación QA cuando esa plataforma se implemente.
- La plataforma de QA no puede cambiar reglas de negocio de GestionPisos ni convertir un fallo en PASS reparando silenciosamente la aplicación.
- La automatización futura debe conservar evidencia suficiente para que una sesión distinta pueda reconstruir qué se ejecutó y qué ocurrió.

## Objetivo futuro

La plataforma se orientará a permitir una cantidad muy elevada de pruebas repetibles sobre Allaiso y otras aplicaciones, incluyendo ejecución E2E real sobre interfaz, paralelización, variantes combinatorias, conservación de evidencias y separación entre ejecución, verificación y corrección.

Este documento mantiene el vínculo documental oficial entre ambos repositorios. La ruta pública de solo lectura ya está validada; la activación de autenticación, escrituras, paralelismo y suites masivas se versionará por etapas en el repositorio de orquestación antes de considerarse disponible para GestionPisos.

## Regla de continuidad

Toda sesión futura que vaya a diseñar, implantar o usar automatización E2E masiva para GestionPisos debe:

1. leer este documento;
2. inspeccionar el estado real del repositorio `jdlc86/Allaiso-QA-Orchestrator`;
3. distinguir siempre la capacidad ya verificada (`PUBLIC_SMOKE_VERIFIED`) de las capacidades aún no activadas, especialmente autenticación y escrituras sobre el AUT;
4. mantener la batería E2E y los contratos de GestionPisos como criterio de aceptación del producto.

