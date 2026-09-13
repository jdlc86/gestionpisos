# Contrato de release

Toda publicación requiere revisión, checks verdes, cambios reproducibles, pruebas relevantes superadas, riesgos conocidos documentados y un punto de rollback identificado.

La secuencia objetivo es: contratos, unitarias, integración, seguridad, E2E, smoke y release.

Mientras no haya usuarios reales, el entorno actual puede utilizarse para validación controlada. Antes del primer usuario externo debe declararse un punto estable y revisarse la separación de entornos.
