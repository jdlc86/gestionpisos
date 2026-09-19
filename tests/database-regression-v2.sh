#!/usr/bin/env bash
set -euo pipefail

repo_path="$PWD"
if command -v cygpath >/dev/null 2>&1; then
  repo_path="$(cygpath -w "$PWD")"
  export MSYS_NO_PATHCONV=1
fi

docker run --rm   -e POSTGRES_PASSWORD=local-regression-only   -v "$repo_path:/work:ro"   postgres:17-alpine   sh -ceu '
    docker-entrypoint.sh postgres -c listen_addresses="" &
    postgres_pid=$!

    cleanup() {
      kill "$postgres_pid" 2>/dev/null || true
      wait "$postgres_pid" 2>/dev/null || true
    }
    trap cleanup EXIT

    ready=0
    for attempt in $(seq 1 30); do
      if pg_isready -U postgres >/dev/null 2>&1; then
        sleep 1
        if kill -0 "$postgres_pid" 2>/dev/null && pg_isready -U postgres >/dev/null 2>&1; then
          ready=1
          break
        fi
      fi
      sleep 1
    done

    if [ "$ready" -ne 1 ]; then
      echo "PostgreSQL did not become ready" >&2
      exit 1
    fi

    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/local-auth-bootstrap.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/fixtures/20260913_remote_baseline.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/local-regression-fixture.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260913205141_close_owners_and_occupancy_blockers.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914064353_beta0_photo_verification_tables.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914064402_beta0_photo_verification_rls.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914074246_beta0_photo_verification_write_policies.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914135759_beta0_photo_alignment_meta.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914135829_beta0_photo_alignment_meta_check_add.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914225214_photo_verification_manual_review.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915080948_photo_run_purpose_cleaning_link.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915082914_cleaning_photo_requests.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915094134_tenant_identity_model.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915161452_tenant_task_workflow_core.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915161841_tenant_task_initial_workflows.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915162747_tenant_task_claims_deposit_workflows.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915163233_tenant_task_rls_and_creator.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915165545_tenant_task_action_actor_authorization.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260917225637_workflow_definition_persistence.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260917230059_workflow_rpc_privilege_hardening.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260917234351_workflow_partial_drafts.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260918003146_workflow_draft_noop_save.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260918004914_workflow_trigger_controls.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260918095001_workflow_publication_applications.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260918103715_workflow_manual_executions.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260918110819_workflow_task_materialization.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260918110824_factory_reset_workflow_data.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260918114500_workflow_atomic_task_actions.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260918133000_workflow_photo_evidence.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260918193000_workflow_accept_reject_decision.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260918233000_workflow_human_review.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260918234500_workflow_review_actor_visibility_hardening.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919001000_photo_review_read_authorization_hardening.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260918234456_workflow_authoring_operational_separation.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919103000_workflow_checklist_step.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919141500_workflow_draft_discard.sql

    # Reproduce Supabase public-schema function default privileges for late RPCs.
    psql -v ON_ERROR_STOP=1 -U postgres -c "alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated, service_role"

    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919143208_workflow_publish_execute_lifecycle.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919170500_workflow_lifecycle_anon_execute_hardening.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919163000_workflow_document_step.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919164500_workflow_document_indexes.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919174500_workflow_notifications.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/database-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/photo-verification-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-definition-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-authoring-separation-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-draft-discard-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-publish-execute-lifecycle-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-document-step-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-notifications-regression.sql

    trap - EXIT
    cleanup
  '
