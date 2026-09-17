#!/usr/bin/env bash
set -euo pipefail

test -s docs/VISUAL_SYSTEM.md
test -s docs/app.css

grep -Fq -- '--ui-hero:#111214' docs/app.css
grep -Fq -- '--ui-surface:#ffffff' docs/app.css
grep -Fq 'class="ui-nav-icon"' docs/index.html
grep -Fq 'class="ui-nav-icon"' docs/configuration-resources.html
grep -Fq '>🔐</span>Gestión de Permisos' docs/index.html
grep -Fq '>🔐</span>Gestión de Permisos' docs/configuration-resources.html
grep -Fq '>⚙️</span>Configuración y Recursos' docs/index.html

if grep -Fq '<svg viewBox="0 0 24 24">' docs/index.html; then
  echo 'El dashboard principal no debe usar una segunda familia SVG para iconos de módulos.'
  exit 1
fi

if grep -Fq 'module-icon--' docs/index.html docs/app.css; then
  echo 'No deben quedar variantes antiguas module-icon--* en el sistema principal.'
  exit 1
fi

if grep -Fq '@media(prefers-color-scheme:dark)' docs/app.css docs/operations.css docs/portfolio.css; then
  echo 'El sistema visual usa data-theme; no se permiten capas paralelas prefers-color-scheme en estos CSS.'
  exit 1
fi

grep -Fq 'background:var(--ui-hero)' docs/operations.css
grep -Fq 'background:var(--ui-hero)' docs/portfolio.css
grep -Fq 'background:#111214' docs/permissions.css
grep -Fq 'var(--ui-border)' docs/permissions.css

echo 'Visual system smoke checks passed'
