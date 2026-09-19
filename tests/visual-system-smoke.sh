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

grep -Fq 'class="ui-nav-icon"' docs/index.html
grep -Fq 'class="ui-nav-icon"' docs/configuration-resources.html
grep -Fq '<svg viewBox="0 0 24 24">' docs/index.html
grep -Fq '<svg viewBox="0 0 24 24">' docs/configuration-resources.html
! grep -Fq '>🔐</span>' docs/index.html docs/configuration-resources.html
! grep -Fq '>⚙️</span>' docs/index.html
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
grep -Fq 'background:#111214' docs/permissions.css
grep -Fq 'var(--ui-border)' docs/permissions.css

echo 'Visual system smoke checks passed'
