#!/usr/bin/env bash
set -euo pipefail

test -s docs/VISUAL_SYSTEM.md
test -s docs/app.css

grep -Fq -- '--ui-hero:#111214' docs/app.css
grep -Fq -- '--ui-surface:#ffffff' docs/app.css
grep -Fq 'module-icon--portfolio' docs/index.html
grep -Fq 'module-icon--settings' docs/index.html
grep -Fq '<svg viewBox="0 0 24 24">' docs/index.html

if grep -Fq 'module-emoji' docs/index.html; then
  echo 'Dashboard principal no debe volver a emojis como iconografía de módulos.'
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
