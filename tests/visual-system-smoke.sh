#!/usr/bin/env bash
set -euo pipefail

test -s docs/VISUAL_SYSTEM.md
test -s docs/VISUAL_AUDIT_2026-09-19.md
test -s docs/app.css
test -s docs/app.js

node --check docs/app.js

grep -Fq -- '--ui-surface:#ffffff' docs/app.css
grep -Fq -- '--ui-action:#0969da' docs/app.css
grep -Fq -- '--ui-accent:#a9854f' docs/app.css
grep -Fq '.primary{border:1px solid var(--ui-action)' docs/app.css
grep -Fq '.secondary{border:1px solid var(--ui-border);background:transparent' docs/app.css
grep -Fq '.context-back{' docs/app.css
grep -Fq '.desktop-home-link{display:none!important}' docs/app.css
grep -Fq '.hero--brand{' docs/app.css
grep -Fq '.premium-icon{' docs/app.css
grep -Fq '.premium-nav-card{' docs/app.css
grep -Fq '.premium-nav-card.locked{' docs/app.css
grep -Fq '.availability-badge{' docs/app.css

grep -Fq 'class="hero hero--brand"' docs/index.html
grep -Fq 'data-premium-icon="portfolio"' docs/index.html
grep -Fq 'data-premium-icon="operations"' docs/index.html
grep -Fq 'data-premium-icon="incidents"' docs/index.html
grep -Fq 'data-premium-icon="workflows"' docs/index.html
grep -Fq 'data-premium-icon="cleaning"' docs/index.html
grep -Fq 'data-premium-icon="permissions"' docs/index.html
grep -Fq 'data-premium-icon="settings"' docs/index.html
grep -Fq 'data-premium-icon="inspections"' docs/index.html
grep -Fq 'data-premium-icon="documents"' docs/index.html
! grep -Eq '🏠|📊|🚨|🔄|🧹|🔐|⚙️|🔎|📄' docs/index.html

grep -Fq 'data-premium-icon="builder"' docs/workflows.html
grep -Fq 'data-premium-icon="definitions"' docs/workflows.html
grep -Fq 'data-premium-icon="camera"' docs/workflows.html
grep -Fq 'data-premium-icon="tasks"' docs/workflows.html
grep -Fq 'data-premium-icon="history"' docs/workflows.html
grep -Fq 'data-premium-icon="database"' docs/configuration-resources.html
grep -Fq 'data-premium-icon="storage"' docs/configuration-resources.html
grep -Fq 'data-premium-icon="users"' docs/permissions.html
grep -Fq 'data-premium-icon="home"' docs/permissions.html
grep -Fq 'data-premium-icon="open"' docs/incidents.html
grep -Fq 'data-premium-icon="cleaning"' docs/cleaning.html

grep -Fq 'AllaisoPremiumIcons' docs/app.js
grep -Fq 'premiumIcons' docs/app.js
grep -Fq 'window.AllaisoPremiumIcons?.render(records)' docs/portfolio.js
! grep -Fq 'const viewIcons = { owners: "♙"' docs/portfolio.js
! grep -Fq '🏠 ' docs/portfolio.js

if grep -Fq '@media(prefers-color-scheme:dark)' docs/app.css docs/operations.css docs/portfolio.css docs/photo-patterns.css docs/photo-verifications.css; then
  echo 'El sistema visual compartido usa data-theme; no se permiten paletas paralelas en los módulos auditados.'
  exit 1
fi

grep -Fq 'var(--ui-card-shadow)' docs/portfolio.css
grep -Fq 'var(--ui-card-shadow)' docs/operations.css
grep -Fq 'var(--ui-card-shadow)' docs/configuration-resources.css
grep -Fq 'var(--ui-card-shadow)' docs/permissions.css
grep -Fq 'var(--ui-card-shadow)' docs/workflow-builder.css
grep -Fq 'var(--ui-card-shadow)' docs/workflow-definitions.css
grep -Fq 'var(--ui-card-shadow)' docs/workflow-applications.css
grep -Fq 'var(--ui-card-shadow)' docs/workflow-tasks.css
grep -Fq 'var(--ui-card-shadow)' docs/photo-patterns.css
grep -Fq 'var(--ui-card-shadow)' docs/photo-verifications.css

grep -Fq 'Toda la gestión diaria, en una sola aplicación.' docs/index.html
grep -Fq '© <span id="copyrightYear"></span> Allaiso · Todos los derechos reservados.' docs/index.html
grep -Fq 'v__APP_VERSION__ · Build __APP_BUILD__' docs/index.html
grep -Fq 'data-build-sha="__APP_COMMIT__"' docs/index.html
grep -Fq 'href="./legal.html"' docs/index.html
grep -Fq 'href="./privacy.html"' docs/index.html
grep -Fq 'new Date().getFullYear()' docs/index.html
test -s docs/app-version.json
grep -Fq '"version": "0.1.5-beta"' docs/app-version.json
grep -Fq 'Stamp release metadata' .github/workflows/pages.yml
grep -Fq 'GITHUB_RUN_NUMBER' .github/workflows/pages.yml
grep -Fq 'GITHUB_SHA' .github/workflows/pages.yml
grep -Fq 'ZoneInfo("Europe/Madrid")' .github/workflows/pages.yml
test -s docs/legal.html
test -s docs/privacy.html

echo 'Visual system smoke checks passed'

grep -Fq '[hidden]{display:none!important}' docs/app.css
grep -Fq 'input[type="checkbox"],input[type="radio"]' docs/app.css
grep -Fq '.builder-editor-state{' docs/workflow-builder.css

grep -Fq 'linear-gradient(145deg,#2d2a26 0%,#26231f 54%,#1f1d1a 100%)' docs/app.css
grep -Fq 'border:1px solid #544c42' docs/app.css
grep -Fq 'html[data-theme="dark"] .hero--brand{' docs/app.css
grep -Fq './app.css?v=2026091909' docs/index.html

! grep -Fq '#f7f3ec' docs/app.css
! grep -Fq '.hero--brand::before' docs/app.css
grep -Fq 'color:#cdc5bb' docs/app.css

grep -Fq '.account-menu{' docs/app.css
grep -Fq 'id="homeAccountAction"' docs/index.html
grep -Fq 'Seguridad MFA' docs/index.html
grep -Fq 'Cerrar sesión' docs/index.html
