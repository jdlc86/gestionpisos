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
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/local-property-staff-v3-alignment.sql

    # Reproduce historical Supabase table grants used by the cleaning swap UI.
    # Production confirms authenticated has SELECT/INSERT/UPDATE on swaps and SELECT on debts.
    psql -v ON_ERROR_STOP=1 -U postgres -c "grant select,insert,update on public.cleaning_swap_requests_v2 to authenticated; grant select on public.cleaning_debts_v2 to authenticated"
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260913192729_beta0_enable_occupancies_v2_rls.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260913192821_beta0_occupancies_v2_read_policies.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260913205141_close_owners_and_occupancy_blockers.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260913225216_beta0_notifications_tables.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260913225223_beta0_notifications_rls.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260913225231_beta0_notifications_mark_read.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914123439_beta0_notification_read_invoker.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914064224_beta0_cleaning_swap_participant_read.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914064231_beta0_cleaning_swap_write_policies.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914064239_beta0_cleaning_swap_integrity.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914064248_beta0_cleaning_swap_validation_trigger.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914064258_beta0_cleaning_swap_decision_trigger.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914064353_beta0_photo_verification_tables.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914064402_beta0_photo_verification_rls.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914074246_beta0_photo_verification_write_policies.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914135759_beta0_photo_alignment_meta.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914135829_beta0_photo_alignment_meta_check_add.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260914225214_photo_verification_manual_review.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915075548_cleaning_audit_core.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915080008_cleaning_audit_lifecycle.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915080455_cleaning_audit_selection.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915080948_photo_run_purpose_cleaning_link.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915082914_cleaning_photo_requests.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915094134_tenant_identity_model.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915100612_tenant_lifecycle_privacy.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260915155636_cleaning_tasks_tenant_identity.sql
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
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919190000_workflow_scheduled_once.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919190050_workflow_scheduled_exact_time.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919193000_workflow_recurring.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919203000_web_push_notifications.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919210000_task_card_removal.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260919213000_task_personal_hiding.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260920010000_workflow_occupancy_tenant_assignee.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260920014500_workflow_tenant_access_revocation.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260920033000_tenant_offboarding_access_enforcement.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260920080723_wf01_generic_assignment_rules.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260920103000_wf02_event_trigger_core.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260920113000_wf03_cleaning_domain_link.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260920114000_wf03_cleaning_decision_state.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260920115000_wf03_cleaning_photo_progress.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260920124500_wf03_cleaning_audit_workflow_sync.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260920134000_wf03_cleaning_final_notification_dedupe.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260920141000_wf03_cleaning_swap_workflow_sync.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/supabase/migrations/20260920143000_wf03_cleaning_authoring_contract.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/database-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/photo-verification-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-definition-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-authoring-separation-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-draft-discard-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-publish-execute-lifecycle-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-document-step-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-notifications-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-scheduled-once-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-recurring-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/web-push-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/task-card-removal-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/task-personal-hiding-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-occupancy-tenant-assignee-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/tenant-offboarding-access-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-assignment-rules-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-event-trigger-regression.sql
    psql -v ON_ERROR_STOP=1 -U postgres -f /work/tests/workflow-cleaning-adapter-regression.sql

    trap - EXIT
    cleanup
  '
