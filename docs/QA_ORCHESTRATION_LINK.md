# Enlace con la plataforma de orquestación QA

## Propósito

GestionPisos / Allaiso dispone de un repositorio separado destinado a definir la futura infraestructura de QA masivo y orquestación de pruebas:

- Repositorio canónico: https://github.com/jdlc86/Allaiso-QA-Orchestrator
- Nombre lógico: **Allaiso-QA-Orchestrator**

Este repositorio externo existe para concentrar arquitectura, contratos, esquemas y evolución de una plataforma capaz de coordinar pruebas E2E, navegadores, agentes locales, evidencias y ejecuciones paralelas sin acoplar esa infraestructura al código de producto.

## Estado actual

**Estado: REGISTRADO / NO OPERATIVO EN GESTIONPISOS.**

A 22/09/2026:

- el repositorio existe;
- contiene una base arquitectónica y documental;
- GestionPisos todavía no debe asumir que exista un runner conectado, un navegador autónomo disponible ni una integración validada;
- ninguna prueba de la batería final puede marcarse como PASS únicamente porque exista el repositorio del orquestador;
- los Gates actuales siguen ejecutándose y validándose conforme a `docs/WORKFLOW_FINAL_E2E_BATTERY.md` hasta que una decisión explícita documente la activación de la plataforma.

## Reparto de autoridad

- **GestionPisos** sigue siendo la fuente de verdad del producto, seguridad, permisos, datos, workflows y criterios de aceptación.
- **Allaiso-QA-Orchestrator** será la fuente de verdad de la infraestructura de orquestación QA cuando esa plataforma se implemente.
- La plataforma de QA no puede cambiar reglas de negocio de GestionPisos ni convertir un fallo en PASS reparando silenciosamente la aplicación.
- La automatización futura debe conservar evidencia suficiente para que una sesión distinta pueda reconstruir qué se ejecutó y qué ocurrió.

## Objetivo futuro

La plataforma se orientará a permitir una cantidad muy elevada de pruebas repetibles sobre Allaiso y otras aplicaciones, incluyendo ejecución E2E real sobre interfaz, paralelización, variantes combinatorias, conservación de evidencias y separación entre ejecución, verificación y corrección.

Este documento **no define todavía cómo se instala, conecta o ejecuta** la plataforma. Es únicamente el vínculo documental oficial entre ambos repositorios y el punto que deben descubrir futuras sesiones.

## Regla de continuidad

Toda sesión futura que vaya a diseñar, implantar o usar automatización E2E masiva para GestionPisos debe:

1. leer este documento;
2. inspeccionar el estado real del repositorio `jdlc86/Allaiso-QA-Orchestrator`;
3. no asumir que la plataforma está operativa salvo que exista una actualización explícita de estado en ambos repositorios;
4. mantener la batería E2E y los contratos de GestionPisos como criterio de aceptación del producto.

