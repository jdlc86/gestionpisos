#!/usr/bin/env bash
set -euo pipefail

test -s docs/DOCUMENTATION_INDEX.md
test -s docs/DOCUMENTATION_AUDIT_2026-09-18.md
test -s docs/AUTH_CONTRACT.md
test -s docs/EXTERNAL_ONBOARDING_CONTRACT.md
test -s docs/PLATFORM_OPERATOR_CONSOLE.md
test -s docs/WORKFLOW_STATUS.md

grep -Fq 'docs/DOCUMENTATION_INDEX.md' README.md
grep -Fq 'DOCUMENTATION_AUDIT_2026-09-18.md' README.md
! grep -Fq 'Estado: bootstrap inicial del proyecto' README.md

grep -Fq 'Toda invitación pertenece a una identidad concreta y a un email canónico concreto' AGENTS.md
grep -Fq '## Invariante de identidad e invitaciones' docs/SECURITY_CONTRACT.md
grep -Fq '## Reglas de invitación y cambio de email' docs/PERMISSIONS_CONTRACT.md
grep -Fq '## Identidades y onboarding' docs/DATA_CONTRACT.md
grep -Fq '## Invariante global de email de invitación' docs/AUTH_CONTRACT.md

grep -Fq 'Validación E2E real — 18/09/2026' docs/WORKFLOW_STATUS.md
grep -Fq 'Criterio del primer flujo real — cumplido para Foto/manual' docs/WORKFLOW_STATUS.md
! grep -Fq 'Hasta entonces, las definiciones visibles en **Mis Flujos** siguen siendo **borradores de autoría**' docs/WORKFLOW_STATUS.md

grep -Fq 'Verificación posterior para cambios R3/R4' docs/RELEASE_CONTRACT.md
grep -Fq 'ADMIN/EMPLOYEE no puede reenviar ni activar' docs/TESTING_STRATEGY.md

echo 'Documentation consistency smoke checks passed'
