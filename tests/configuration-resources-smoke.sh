#!/usr/bin/env bash
set -euo pipefail

test -s docs/configuration-resources.html
test -s docs/configuration-resources.css
test -s docs/configuration-resources.js
test -s docs/root-home-modules.js
test -s supabase/functions/root-configuration-resources/index.ts
test -s supabase/migrations/20260917203000_root_configuration_resources.sql

node --check docs/configuration-resources.js
node --check docs/root-home-modules.js

grep -Fq 'id="configurationResourcesCard"' docs/index.html
grep -Fq 'configuration-resources.html' docs/index.html
grep -Fq 'configurationResourcesCard" class="card"' docs/index.html
grep -Fq 'hidden' docs/index.html
grep -Fq 'app_metadata?.role' docs/root-home-modules.js

grep -Fq 'Configuración y Recursos' docs/configuration-resources.html
grep -Fq 'Gestión de Permisos' docs/configuration-resources.html
grep -Fq 'Seguridad MFA' docs/configuration-resources.html
grep -Fq 'Operadores de emergencia' docs/configuration-resources.html
grep -Fq 'factory-reset.html' docs/configuration-resources.html

grep -Fq 'root-configuration-resources' docs/configuration-resources.js
grep -Fq 'root_required' supabase/functions/root-configuration-resources/index.ts
grep -Fq 'aal2_required' supabase/functions/root-configuration-resources/index.ts
grep -Fq 'root_configuration_resources_service' supabase/functions/root-configuration-resources/index.ts
grep -Fq 'transactional_provider_configured' supabase/functions/root-configuration-resources/index.ts

grep -Fq 'security definer' supabase/migrations/20260917203000_root_configuration_resources.sql
grep -Fq 'pg_database_size(current_database())' supabase/migrations/20260917203000_root_configuration_resources.sql
grep -Fq 'storage.objects' supabase/migrations/20260917203000_root_configuration_resources.sql
grep -Fq 'revoke all on function public.root_configuration_resources_service' supabase/migrations/20260917203000_root_configuration_resources.sql
grep -Fq 'grant execute on function public.root_configuration_resources_service' supabase/migrations/20260917203000_root_configuration_resources.sql

# Negative/security checks: privileged material never reaches GitHub Pages.
! grep -R -Fq 'SUPABASE_SERVICE_ROLE_KEY' docs/configuration-resources.html docs/configuration-resources.js docs/root-home-modules.js
! grep -R -Fq 'RESEND_API_KEY' docs/configuration-resources.html docs/configuration-resources.js docs/root-home-modules.js
! grep -R -Fq 'AUTH_EMAIL_FROM' docs/configuration-resources.html docs/configuration-resources.js docs/root-home-modules.js

echo 'Configuration & Resources smoke checks passed'
