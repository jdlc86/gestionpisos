#!/usr/bin/env bash
set -euo pipefail

test -s docs/VISUAL_SYSTEM.md
test -s docs/VISUAL_AUDIT_2026-09-19.md
test -s docs/app.css

grep -Fq -- '--ui-surface:#ffffff' docs/app.css
grep -Fq -- '--ui-action:#0969da' docs/app.css
grep -Fq '.primary{border:1px solid var(--ui-action)' docs/app.css
grep -Fq '.secondary{border:1px solid var(--ui-border);background:transparent' docs/app.css
grep -Fq '.context-back{' docs/app.css
grep -Fq '.desktop-home-link{display:none!important}' docs/app.css

grep -Fq 'class="ui-nav-icon home-module-icon"' docs/index.html
grep -Fq 'class="ui-nav-icon"' docs/configuration-resources.html
grep -Fq 'class="ui-nav-icon home-module-icon"' docs/index.html
grep -Fq '>🏠</span>Cartera' docs/index.html
grep -Fq '>📊</span>Centro Operativo' docs/index.html
grep -Fq '>🚨</span>Incidencias' docs/index.html
grep -Fq '>🔄</span>Flujos de Trabajo' docs/index.html
grep -Fq '>🧹</span>Limpieza' docs/index.html
grep -Fq '>🔐</span>Gestión de Permisos' docs/index.html
grep -Fq '>⚙️</span>Configuración y Recursos' docs/index.html
grep -Fq '<svg viewBox="0 0 24 24">' docs/configuration-resources.html
! grep -Fq 'href="./mfa-setup.html?next=configuration-resources.html"' docs/configuration-resources.html

if grep -Fq 'module-icon--' docs/index.html docs/app.css; then
  echo 'No deben quedar variantes antiguas module-icon--* en el sistema principal.'
  exit 1
fi

if grep -Fq '@media(prefers-color-scheme:dark)' docs/app.css docs/operations.css docs/portfolio.css docs/photo-patterns.css docs/photo-verifications.css; then
  echo 'El sistema visual compartido usa data-theme; no se permiten paletas paralelas en los módulos auditados.'
  exit 1
fi

! grep -Fq 'theme-toggle' docs/portfolio.css
! grep -Fq 'portfolio-hero' docs/portfolio.css
! grep -Fq 'ops-hero' docs/operations.css
grep -Fq 'Toda la gestión diaria, en una sola aplicación.' docs/index.html
grep -Fq '© <span id="copyrightYear"></span> Allaiso · Todos los derechos reservados.' docs/index.html
grep -Fq 'v__APP_VERSION__ · Build __APP_BUILD__' docs/index.html
grep -Fq 'data-build-sha="__APP_COMMIT__"' docs/index.html
grep -Fq 'href="./legal.html"' docs/index.html
grep -Fq 'href="./privacy.html"' docs/index.html
grep -Fq 'new Date().getFullYear()' docs/index.html
test -s docs/app-version.json
grep -Fq '"version": "0.1.0-beta"' docs/app-version.json
grep -Fq 'Stamp release metadata' .github/workflows/pages.yml
grep -Fq 'GITHUB_RUN_NUMBER' .github/workflows/pages.yml
grep -Fq 'GITHUB_SHA' .github/workflows/pages.yml
grep -Fq 'ZoneInfo("Europe/Madrid")' .github/workflows/pages.yml
test -s docs/legal.html
test -s docs/privacy.html
grep -Fq 'background:#111214' docs/permissions.css
grep -Fq 'var(--ui-border)' docs/permissions.css

echo 'Visual system smoke checks passed'
