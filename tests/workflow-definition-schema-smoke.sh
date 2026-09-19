#!/usr/bin/env bash
set -euo pipefail

migration='supabase/migrations/20260917225637_workflow_definition_persistence.sql'
hardening='supabase/migrations/20260917230059_workflow_rpc_privilege_hardening.sql'
partial='supabase/migrations/20260917234351_workflow_partial_drafts.sql'
noop='supabase/migrations/20260918003146_workflow_draft_noop_save.sql'
triggers='supabase/migrations/20260918004914_workflow_trigger_controls.sql'
applications='supabase/migrations/20260918095001_workflow_publication_applications.sql'
executions='supabase/migrations/20260918103715_workflow_manual_executions.sql'
materialization='supabase/migrations/20260918110819_workflow_task_materialization.sql'
workflow_reset='supabase/migrations/20260918110824_factory_reset_workflow_data.sql'
actions='supabase/migrations/20260918114500_workflow_atomic_task_actions.sql'
photo_evidence='supabase/migrations/20260918133000_workflow_photo_evidence.sql'
decisions='supabase/migrations/20260918193000_workflow_accept_reject_decision.sql'
human_review='supabase/migrations/20260918233000_workflow_human_review.sql'
review_access='supabase/migrations/20260918234500_workflow_review_actor_visibility_hardening.sql'
photo_review_hardening='supabase/migrations/20260919001000_photo_review_read_authorization_hardening.sql'
authoring_separation='supabase/migrations/20260918234456_workflow_authoring_operational_separation.sql'
draft_discard='supabase/migrations/20260919141500_workflow_draft_discard.sql'
lifecycle='supabase/migrations/20260919143208_workflow_publish_execute_lifecycle.sql'
lifecycle_anon_hardening='supabase/migrations/20260919170500_workflow_lifecycle_anon_execute_hardening.sql'
document_step='supabase/migrations/20260919163000_workflow_document_step.sql'
document_indexes='supabase/migrations/20260919164500_workflow_document_indexes.sql'
workflow_notifications='supabase/migrations/20260919174500_workflow_notifications.sql'
scheduled_once='supabase/migrations/20260919190000_workflow_scheduled_once.sql'
scheduled_exact='supabase/migrations/20260919190050_workflow_scheduled_exact_time.sql'
recurring='supabase/migrations/20260919193000_workflow_recurring.sql'
web_push='supabase/migrations/20260919203000_web_push_notifications.sql'
task_card_removal='supabase/migrations/20260919210000_task_card_removal.sql'
task_personal_hiding='supabase/migrations/20260919213000_task_personal_hiding.sql'
scheduled_cron='supabase/migrations/20260919190100_workflow_schedule_cron.sql'
checklist='supabase/migrations/20260919103000_workflow_checklist_step.sql'

test -s "$migration"
test -s "$hardening"
test -s "$partial"
test -s "$noop"
test -s "$triggers"
test -s "$applications"
test -s "$executions"
test -s "$materialization"
test -s "$workflow_reset"
test -s "$actions"
test -s "$photo_evidence"
test -s "$decisions"
test -s "$human_review"
test -s "$review_access"
test -s "$photo_review_hardening"
test -s "$authoring_separation"
test -s "$draft_discard"
test -s "$lifecycle"
test -s "$lifecycle_anon_hardening"
test -s "$document_step"
test -s "$document_indexes"
test -s "$workflow_notifications"
test -s "$scheduled_once"
test -s "$scheduled_exact"
test -s "$recurring"
test -s "$web_push"
test -s "$task_card_removal"
test -s "$task_personal_hiding"
test -s "$scheduled_cron"
test -s tests/workflow-notifications-regression.sql
test -s tests/workflow-scheduled-once-regression.sql
test -s tests/workflow-recurring-regression.sql
test -s tests/web-push-regression.sql
test -s tests/task-card-removal-regression.sql
test -s tests/task-personal-hiding-regression.sql
test -s tests/local-property-staff-v3-alignment.sql
test -s tests/workflow-draft-discard-regression.sql
test -s tests/workflow-publish-execute-lifecycle-regression.sql
test -s tests/workflow-document-step-regression.sql
test -s "$checklist"
test -s tests/workflow-definition-regression.sql
test -s tests/workflow-authoring-separation-regression.sql

grep -Fq 'create table if not exists public.workflow_definitions_v2' "$migration"
grep -Fq 'create table if not exists public.workflow_definition_versions_v2' "$migration"
grep -Fq 'alter table public.workflow_definitions_v2 enable row level security' "$migration"
grep -Fq 'alter table public.workflow_definition_versions_v2 enable row level security' "$migration"
grep -Fq 'create policy workflow_definitions_v2_read_authorized' "$migration"
grep -Fq 'create or replace function public.save_workflow_definition_draft_v1' "$migration"
grep -Fq 'workflow_author_role_required' "$migration"
grep -Fq 'workflow_draft_conflict' "$migration"
grep -Fq "revoke insert, update, delete" "$migration"
grep -Fq "grant execute on function public.save_workflow_definition_draft_v1" "$migration"
grep -Fq "workflow_draft_created" "$migration"
grep -Fq "workflow_draft_updated" "$migration"

grep -Fq 'revoke execute on function public.save_workflow_definition_draft_v1(jsonb, uuid, bigint) from anon' "$hardening"
grep -Fq 'revoke execute on function public.workflow_can_read_definitions_v1(uuid) from anon' "$hardening"
grep -Fq 'grant execute on function public.save_workflow_definition_draft_v1(jsonb, uuid, bigint) to authenticated' "$hardening"
grep -Fq 'grant execute on function public.workflow_can_read_definitions_v1(uuid) to authenticated' "$hardening"

grep -Fq 'alter column flow_type drop not null' "$partial"
grep -Fq 'add column if not exists authoring_complete boolean not null default false' "$partial"
grep -Fq 'create or replace function public.workflow_authoring_complete_v1' "$partial"
grep -Fq "'authoringVersion'" "$partial"
grep -Fq 'v_authoring_complete := public.workflow_authoring_complete_v1(v_sanitized)' "$partial"
grep -Fq 'authoring_complete = v_authoring_complete' "$partial"
grep -Fq 'revoke execute on function public.save_workflow_definition_draft_v1(jsonb, uuid, bigint) from anon' "$partial"

grep -Fq 'v_existing_spec = v_sanitized' "$noop"
grep -Fq 'v_existing_complete = v_authoring_complete' "$noop"
grep -Fq 'return query select v_id, v_current_revision, v_updated_at' "$noop"
grep -Fq 'no altera updated_at' "$noop"

grep -Fq "'scheduledAt'" "$triggers"
grep -Fq "'customEvery'" "$triggers"
grep -Fq "'customUnit'" "$triggers"
grep -Fq 'workflow_scheduled_at_invalid' "$triggers"
grep -Fq 'workflow_custom_recurrence_invalid' "$triggers"
grep -Fq "v_trigger_type is distinct from 'recurring'" "$triggers"
grep -Fq "v_trigger_type is distinct from 'scheduled_once'" "$triggers"
grep -Fq "not (draft_spec ? 'scheduledAt')" "$triggers"
grep -Fq 'set authoring_complete = public.workflow_authoring_complete_v1(draft_spec)' "$triggers"

grep -Fq 'create table public.workflow_applications_v2' "$applications"
grep -Fq 'alter table public.workflow_applications_v2 enable row level security' "$applications"
grep -Fq 'create policy workflow_applications_v2_read_authorized' "$applications"
grep -Fq 'create or replace function public.publish_workflow_definition_v1' "$applications"
grep -Fq 'create or replace function public.create_workflow_application_v1' "$applications"
grep -Fq 'create or replace function public.archive_workflow_application_v1' "$applications"
grep -Fq "coalesce(auth.jwt()->>'aal','aal1') <> 'aal2'" "$applications"
grep -Fq 'workflow_application_not_authorized' "$applications"
grep -Fq 'workflow_property_not_available' "$applications"
grep -Fq 'workflow_room_not_available' "$applications"
grep -Fq 'workflow_occupancy_not_available' "$applications"
grep -Fq 'workflow_application_created' "$applications"
grep -Fq 'workflow_application_archived' "$applications"
grep -Fq 'revoke execute on function public.publish_workflow_definition_v1(uuid,bigint) from anon' "$applications"
grep -Fq 'revoke execute on function public.create_workflow_application_v1(uuid,uuid,uuid,uuid) from anon' "$applications"

grep -Fq 'create table public.workflow_executions_v2' "$executions"
grep -Fq 'create table public.workflow_execution_events_v2' "$executions"
grep -Fq 'alter table public.workflow_executions_v2 enable row level security' "$executions"
grep -Fq 'alter table public.workflow_execution_events_v2 enable row level security' "$executions"
grep -Fq 'workflow_executions_v2_application_idempotency_uq' "$executions"
grep -Fq 'create or replace function public.execute_workflow_application_now_v1' "$executions"
grep -Fq "trigger_kind in ('manual_now')" "$executions"
grep -Fq "v_assignment_type='manual'" "$executions"
grep -Fq "v_assignment_type='property_responsible'" "$executions"
grep -Fq 'workflow_assignment_not_supported' "$executions"
grep -Fq 'workflow_manual_assignee_not_eligible' "$executions"
grep -Fq 'workflow_execution_created' "$executions"
grep -Fq 'revoke execute on function public.execute_workflow_application_now_v1(uuid,text,uuid) from anon' "$executions"
grep -Fq 'grant execute on function public.execute_workflow_application_now_v1(uuid,text,uuid) to authenticated' "$executions"

grep -Fq 'alter column tenant_id drop not null' "$materialization"
grep -Fq 'tenant_tasks_v2_subject_or_workflow_check' "$materialization"
grep -Fq "source_kind='workflow_execution'" "$materialization"
grep -Fq 'tenant_tasks_v2_workflow_execution_uq' "$materialization"
grep -Fq "task_type='workflow'" "$materialization"
grep -Fq 'revoke all on public.tenant_tasks_v2 from anon' "$materialization"
grep -Fq 'revoke insert,update,delete,truncate,references,trigger' "$materialization"
grep -Fq 'create policy tenant_tasks_v2_admin_read' "$materialization"
grep -Fq 'workflow_can_read_definitions_v1(organization_id)' "$materialization"
grep -Fq 'create policy tenant_tasks_v2_assignee_read' "$materialization"
grep -Fq 'create policy tenant_tasks_v2_tenant_read' "$materialization"
grep -Fq 'workflow_materialize_execution_task_internal_v1' "$materialization"
grep -Fq 'create or replace function public.materialize_workflow_execution_task_v1' "$materialization"
grep -Fq 'workflow_task_materialization_not_authorized' "$materialization"
grep -Fq 'workflow_task_materialized' "$materialization"
grep -Fq 'task_materialized' "$materialization"
grep -Fq 'perform public.workflow_materialize_execution_task_internal_v1(v_execution_id,v_actor)' "$materialization"
grep -Fq 'revoke execute on function public.materialize_workflow_execution_task_v1(uuid) from anon' "$materialization"
grep -Fq 'public.workflow_execution_events_v2' "$workflow_reset"
grep -Fq 'public.workflow_executions_v2' "$workflow_reset"
grep -Fq 'public.workflow_applications_v2' "$workflow_reset"
grep -Fq 'public.workflow_definition_versions_v2' "$workflow_reset"
grep -Fq 'public.workflow_definitions_v2' "$workflow_reset"

grep -Fq 'workflow_execution_events_v2_action_request_uq' "$actions"
grep -Fq 'create or replace function public.workflow_seed_task_actions_internal_v1' "$actions"
grep -Fq "v_has_accept:=coalesce((v_execution.spec_snapshot->'steps'->>'accept')::boolean,false)" "$actions"
grep -Fq "v_target_status:='completed'" "$actions"
grep -Fq "v_target_status:='waiting_review'" "$actions"
grep -Fq "v_target_status:='active'" "$actions"
grep -Fq "'Aceptar y completar'" "$actions"
grep -Fq "'Aceptar y enviar a revisión'" "$actions"
grep -Fq "actor='assignee'" "$actions"
grep -Fq 'create trigger workflow_task_seed_actions_v1' "$actions"
grep -Fq 'workflow_task_requires_atomic_action' "$actions"
grep -Fq 'security definer' "$actions"
grep -Fq "ur.role='root'" "$actions"
grep -Fq "ur.role='admin' and ur.organization_id=v_task.organization_id" "$actions"
grep -Fq 'create or replace function public.apply_workflow_task_action_v1' "$actions"
grep -Fq 'workflow_task_execution_state_mismatch' "$actions"
grep -Fq 'workflow_action_actor_forbidden' "$actions"
grep -Fq 'workflow_action_request_key_conflict' "$actions"
grep -Fq 'workflow_action_transition_contract_mismatch' "$actions"
grep -Fq "'task_action_applied'" "$actions"
grep -Fq "'workflow_task_action_applied'" "$actions"
grep -Fq 'revoke execute on function public.apply_workflow_task_action_v1(uuid,text,text,text) from anon' "$actions"
grep -Fq 'grant execute on function public.apply_workflow_task_action_v1(uuid,text,text,text) to authenticated' "$actions"

grep -Fq 'create table public.workflow_application_photo_resources_v2' "$photo_evidence"
grep -Fq 'create table public.workflow_execution_photo_resources_v2' "$photo_evidence"
grep -Fq 'alter table public.workflow_application_photo_resources_v2 enable row level security' "$photo_evidence"
grep -Fq 'alter table public.workflow_execution_photo_resources_v2 enable row level security' "$photo_evidence"
grep -Fq 'create or replace function public.create_workflow_application_v2' "$photo_evidence"
grep -Fq 'workflow_create_application_core_v1' "$photo_evidence"
grep -Fq 'workflow_photo_application_requires_v2' "$photo_evidence"
grep -Fq 'revoke all on function public.workflow_create_application_core_v1(uuid,uuid,uuid,uuid)' "$photo_evidence"
grep -Fq 'workflow_photo_resources_required' "$photo_evidence"
grep -Fq 'workflow_photo_pattern_not_available' "$photo_evidence"
grep -Fq 'workflow_snapshot_photo_resources_internal_v1' "$photo_evidence"
grep -Fq 'pattern_snapshot' "$photo_evidence"
grep -Fq 'workflow_execution_photo_snapshot_missing' "$photo_evidence"
grep -Fq 'start_workflow_photo_verification_v1' "$photo_evidence"
grep -Fq 'submit_workflow_photo_verification_v1' "$photo_evidence"
grep -Fq "check (source_type in ('cleaning_task','inspection','random_request','manual','workflow_execution'))" "$photo_evidence"
grep -Fq "and source_type<>'workflow_execution'" "$photo_evidence"
grep -Fq 'workflow_photo_actor_forbidden' "$photo_evidence"
grep -Fq 'workflow_photo_object_missing' "$photo_evidence"
grep -Fq "'photo_evidence_submitted'" "$photo_evidence"
grep -Fq 'private.photo_pattern_usage_v2' "$photo_evidence"
grep -Fq "'workflow_application'" "$photo_evidence"
grep -Fq "'workflow_execution'" "$photo_evidence"
grep -Fq 'public.workflow_execution_photo_resources_v2' "$photo_evidence"
grep -Fq 'public.workflow_application_photo_resources_v2' "$photo_evidence"
grep -Fq 'create or replace function public.factory_reset_test_data_service' "$photo_evidence"
grep -Fq 'revoke execute on function public.start_workflow_photo_verification_v1(uuid) from anon' "$photo_evidence"
grep -Fq 'revoke execute on function public.submit_workflow_photo_verification_v1(uuid,uuid,text) from anon' "$photo_evidence"
grep -Fq "check (status in ('pending','active','waiting_review','completed','cancelled','failed','rejected'))" "$decisions"
grep -Fq "v_task.id,'reject','Rechazar','pending','rejected',true,20,true,'assignee'" "$decisions"
grep -Fq "p_action_key not in ('accept','reject')" "$decisions"
grep -Fq "if p_action_key='reject' then" "$decisions"
grep -Fq "status='cancelled'" "$decisions"
grep -Fq "Rechazar exige motivo" "$decisions"
grep -Fq "v_task.id,'review_approve','Aprobar revisión','waiting_review','completed',false,90,true,'agency'" "$human_review"
grep -Fq "v_task.id,'review_reject','Rechazar revisión','waiting_review','rejected',true,100,true,'agency'" "$human_review"
grep -Fq "workflow_photo_review_requires_photo_review_flow" "$human_review"
grep -Fq "create or replace function public.apply_workflow_photo_review_v1" "$human_review"
grep -Fq "workflow_review_actor_forbidden" "$human_review"
grep -Fq "workflow_review_applied" "$human_review"
grep -Fq "grant execute on function public.apply_workflow_photo_review_v1(uuid,uuid,text,text)" "$human_review"
grep -Fq "create policy tenant_task_actions_v2_workflow_actor_gate" "$review_access"
grep -Fq "as restrictive" "$review_access"
grep -Fq "tenant_task_actions_v2.actor='assignee'" "$review_access"
grep -Fq "tenant_task_actions_v2.actor='agency'" "$review_access"
grep -Fq "public.workflow_can_manage_v1(t.organization_id)" "$review_access"
grep -Fq "t.task_type<>'workflow'" "$review_access"
grep -Fq "create or replace function public.photo_verification_can_review_v1" "$photo_review_hardening"
grep -Fq "coalesce(auth.jwt()->>'aal','aal1')='aal2'" "$photo_review_hardening"
grep -Fq "ur.revoked_at is null" "$photo_review_hardening"
grep -Fq "grant select on public.photo_verification_runs_v2 to authenticated" "$photo_review_hardening"
grep -Fq "grant select on public.photo_verification_items_v2 to authenticated" "$photo_review_hardening"
grep -Fq "grant select on storage.objects to authenticated" "$photo_review_hardening"
grep -Fq "drop policy if exists photo_runs_actor_read" "$photo_review_hardening"
grep -Fq "drop policy if exists photo_items_actor_read" "$photo_review_hardening"
grep -Fq "drop policy if exists photo_verification_storage_read" "$photo_review_hardening"
grep -Fq "public.photo_verification_can_review_v1(split_part(name,'/',1))" "$photo_review_hardening"
grep -Fq "v_run_applied_new boolean:=false" "$photo_review_hardening"
grep -Fq "'applied_new',v_run_applied_new" "$photo_review_hardening"
grep -Fq 'create table if not exists public.workflow_definition_revision_drafts_v2' "$authoring_separation"
grep -Fq 'alter table public.workflow_definition_revision_drafts_v2 enable row level security' "$authoring_separation"
grep -Fq 'create or replace function public.start_workflow_definition_revision_v1' "$authoring_separation"
grep -Fq 'create or replace function public.save_workflow_definition_revision_draft_v1' "$authoring_separation"
grep -Fq 'create or replace function public.publish_workflow_definition_revision_v1' "$authoring_separation"
grep -Fq 'workflow_revision_base_version_conflict' "$authoring_separation"
grep -Fq 'published_version_id uuid' "$authoring_separation"
grep -Fq 'published_at timestamptz' "$authoring_separation"
grep -Fq 'if v_draft.published_at is not null then' "$authoring_separation"
grep -Fq 'workflow_revision_publication_receipt_invalid' "$authoring_separation"
grep -Fq 'set published_version_id=v_version_id' "$authoring_separation"
grep -Fq "v_definition.status<>'published'" "$authoring_separation"
grep -Fq "delete from public.workflow_definition_revision_drafts_v2" "$authoring_separation"
grep -Fq "'workflow_definition_revision_published'" "$authoring_separation"
grep -Fq 'grant execute on function public.start_workflow_definition_revision_v1(uuid) to authenticated' "$authoring_separation"
grep -Fq 'grant execute on function public.publish_workflow_definition_revision_v1(uuid,bigint)' "$authoring_separation"
grep -Fq "revoke all on function public.apply_workflow_photo_review_v1(uuid,uuid,text,text)" "$human_review"
grep -Fq "tenant_task_actions_v2_workflow_manager_read" "$human_review"
grep -Fq "public.workflow_can_manage_v1(t.organization_id)" "$human_review"
grep -Fq "t.task_type='workflow'" "$human_review"
! grep -Fq "drop policy if exists tenant_task_actions_v2_read_scope" "$human_review"

echo 'Workflow definition schema smoke checks passed'

grep -Fq 'create or replace function public.save_workflow_definition_draft_v2' "$checklist"
grep -Fq "'checklistItems',v_normalized_checklist" "$checklist"
grep -Fq 'add column if not exists checklist_state jsonb' "$checklist"
grep -Fq 'create trigger workflow_execution_initialize_checklist_v1' "$checklist"
grep -Fq 'create or replace function public.set_workflow_checklist_item_v1' "$checklist"
grep -Fq 'workflow_checklist_actor_forbidden' "$checklist"
grep -Fq 'workflow_checklist_accept_required' "$checklist"
grep -Fq "event_type='checklist_item_changed'" "$checklist"
grep -Fq 'jsonb_array_length(v_execution.checklist_state)=0' "$checklist"
grep -Fq 'grant execute on function public.set_workflow_checklist_item_v1' "$checklist"

grep -Fq 'create or replace function public.discard_workflow_definition_draft_v1' "$draft_discard"
grep -Fq 'create or replace function public.discard_workflow_definition_revision_draft_v1' "$draft_discard"
grep -Fq "workflow_draft_discard_requires_unpublished" "$draft_discard"
grep -Fq "workflow_draft_has_dependencies" "$draft_discard"
grep -Fq "workflow_definition_revision_draft_discarded" "$draft_discard"
grep -Fq 'grant execute on function public.discard_workflow_definition_draft_v1' "$draft_discard"
grep -Fq 'grant execute on function public.discard_workflow_definition_revision_draft_v1' "$draft_discard"


# Publicar / Ejecutar: la primera ejecucion es la frontera historica.
grep -Fq 'add column if not exists creation_request_key text' "$lifecycle"
grep -Fq 'workflow_definitions_v2_creation_request_uq' "$lifecycle"
grep -Fq 'create or replace function public.publish_workflow_ready_v1' "$lifecycle"
grep -Fq 'create or replace function public.update_unexecuted_workflow_v1' "$lifecycle"
grep -Fq 'create or replace function public.publish_workflow_revision_ready_v1' "$lifecycle"
grep -Fq 'create or replace function public.delete_unexecuted_workflow_v1' "$lifecycle"
grep -Fq 'create or replace function public.archive_workflow_definition_v1' "$lifecycle"
grep -Fq "coalesce(auth.jwt()->>'aal','aal1') <> 'aal2'" "$lifecycle"
grep -Fq "raise exception 'workflow_definition_has_history'" "$lifecycle"
grep -Fq "raise exception 'workflow_revision_requires_history'" "$lifecycle"
grep -Fq "raise exception 'workflow_unexecuted_delete_instead'" "$lifecycle"
grep -Fq "update public.workflow_definition_versions_v2 wv" "$lifecycle"
grep -Fq "perform pg_advisory_xact_lock" "$lifecycle"
grep -Fq "grant execute on function public.publish_workflow_ready_v1" "$lifecycle"
grep -Fq "grant execute on function public.update_unexecuted_workflow_v1" "$lifecycle"
grep -Fq "grant execute on function public.publish_workflow_revision_ready_v1" "$lifecycle"
grep -Fq "grant execute on function public.delete_unexecuted_workflow_v1" "$lifecycle"
grep -Fq "grant execute on function public.archive_workflow_definition_v1" "$lifecycle"


# Documento: evidencia privada dentro del motor transversal de workflows.
grep -Fq 'create table public.workflow_execution_documents_v2' "$document_step"
grep -Fq 'alter table public.workflow_execution_documents_v2 enable row level security' "$document_step"
grep -Fq 'workflow_execution_documents_v2_read' "$document_step"
grep -Fq "'workflow-documents-v2'" "$document_step"
grep -Fq 'workflow_documents_storage_insert' "$document_step"
grep -Fq 'workflow_documents_storage_select' "$document_step"
grep -Fq 'create or replace function public.prepare_workflow_document_upload_v1' "$document_step"
grep -Fq 'create or replace function public.submit_workflow_document_v1' "$document_step"
grep -Fq "raise exception 'workflow_document_actor_forbidden'" "$document_step"
grep -Fq "raise exception 'workflow_document_accept_required'" "$document_step"
grep -Fq "o.owner_id=v_actor::text" "$document_step"
grep -Fq "event_type='document_evidence_submitted'" "$document_step"
grep -Fq 'grant execute on function public.prepare_workflow_document_upload_v1' "$document_step"
grep -Fq 'grant execute on function public.submit_workflow_document_v1' "$document_step"
grep -Fq 'revoke all on public.workflow_execution_documents_v2 from anon' "$document_step"
grep -Fq 'comment on table public.workflow_execution_documents_v2' "$document_step"

# Foto/Checklist consultan evidencia documental real, no solo el flag del spec.
grep -Fq 'from public.workflow_execution_documents_v2 d' "$document_step"
grep -Fq 'where d.execution_id=v_execution.id' "$document_step"
grep -Fq "and d.status='submitted'" "$document_step"


# Hardening Documento: cubrir FK nuevas señaladas por advisors.
grep -Fq 'workflow_execution_documents_v2_organization_idx' "$document_indexes"
grep -Fq 'on public.workflow_execution_documents_v2(organization_id)' "$document_indexes"
grep -Fq 'workflow_execution_documents_v2_uploaded_by_idx' "$document_indexes"
grep -Fq 'on public.workflow_execution_documents_v2(uploaded_by)' "$document_indexes"


# Lifecycle: Supabase concede EXECUTE a anon por default privileges; el hardening debe cerrarlo explícitamente.
grep -Fq 'revoke all on function public.publish_workflow_ready_v1' "$lifecycle_anon_hardening"
grep -Fq 'revoke all on function public.update_unexecuted_workflow_v1' "$lifecycle_anon_hardening"
grep -Fq 'revoke all on function public.publish_workflow_revision_ready_v1' "$lifecycle_anon_hardening"
grep -Fq 'revoke all on function public.delete_unexecuted_workflow_v1' "$lifecycle_anon_hardening"
grep -Fq 'revoke all on function public.archive_workflow_definition_v1' "$lifecycle_anon_hardening"
test "$(grep -Fc 'from public,anon;' "$lifecycle_anon_hardening")" -ge 5
grep -Fq 'grant execute on function public.publish_workflow_ready_v1' "$lifecycle_anon_hardening"
grep -Fq 'to authenticated;' "$lifecycle_anon_hardening"


# Notificaciones workflow: reutilizar notifications_v2 con correlación idempotente.
grep -Fq 'add column if not exists source_kind text' "$workflow_notifications"
grep -Fq 'add column if not exists source_id uuid' "$workflow_notifications"
grep -Fq 'add column if not exists event_key text' "$workflow_notifications"
grep -Fq 'notifications_source_correlation_check' "$workflow_notifications"
grep -Fq 'notifications_v2_source_event_recipient_uq' "$workflow_notifications"
grep -Fq 'create or replace function private.workflow_execution_notifications_v1' "$workflow_notifications"
grep -Fq "v_notify_create:=coalesce" "$workflow_notifications"
grep -Fq "v_notify_close:=coalesce" "$workflow_notifications"
grep -Fq "'workflow_task_created'" "$workflow_notifications"
grep -Fq "'workflow_completed'" "$workflow_notifications"
grep -Fq "'workflow_rejected'" "$workflow_notifications"
grep -Fq "new.status in ('completed','rejected')" "$workflow_notifications"
grep -Fq "channel_email" "$workflow_notifications"
grep -Fq "false," "$workflow_notifications"
grep -Fq 'revoke all on function private.workflow_execution_notifications_v1()' "$workflow_notifications"
grep -Fq 'create trigger workflow_execution_notifications_v1' "$workflow_notifications"

# Web Push: sin polling, secretos fuera del cliente y entrega idempotente.
grep -Fq 'create table if not exists public.web_push_subscriptions_v1' "$web_push"
grep -Fq "create extension if not exists pg_net" "$web_push"
! grep -Fq "pg_net with schema" "$web_push"
grep -Fq 'create table if not exists public.web_push_deliveries_v1' "$web_push"
grep -Fq 'register_web_push_subscription_v1' "$web_push"
grep -Fq 'unregister_web_push_subscription_v1' "$web_push"
grep -Fq 'web_push_server_config_v1' "$web_push"
grep -Fq 'web_push_claim_delivery_v1' "$web_push"
grep -Fq 'web_push_finish_delivery_v1' "$web_push"
grep -Fq 'private.web_push_recipient_active_v1' "$web_push"
grep -Fq 'notification_web_push_dispatch_v1' "$web_push"
grep -Fq 'gestionpisos_web_push_dispatch_secret_v1' "$web_push"
grep -Fq "revoke all on function public.web_push_server_config_v1()" "$web_push"
grep -Fq 'grant execute on function public.web_push_server_config_v1()' "$web_push"
grep -Fq 'to service_role;' "$web_push"
test -s supabase/functions/web-push/index.ts
grep -Fq 'npm:@supabase/supabase-js@2.116.0' supabase/functions/web-push/index.ts
grep -Fq 'npm:web-push@3.6.7' supabase/functions/web-push/index.ts
grep -Fq 'web_push_claim_delivery_v1' supabase/functions/web-push/index.ts
grep -Fq 'X-Allaiso-Push-Secret' supabase/functions/web-push/index.ts
test -s .github/workflows/web-push-function.yml
grep -Fq -- '--no-verify-jwt' .github/workflows/web-push-function.yml
grep -Fq 'supabase functions deploy web-push' .github/workflows/web-push-function.yml

# Tareas: eliminar retira la tarjeta pero conserva trazabilidad.
grep -Fq 'add column if not exists removed_at timestamptz' "$task_card_removal"
grep -Fq 'add column if not exists removed_by uuid' "$task_card_removal"
grep -Fq 'create or replace function public.delete_task_card_v1' "$task_card_removal"
grep -Fq 'task_delete_requires_terminal' "$task_card_removal"
grep -Fq 'task_delete_execution_not_terminal' "$task_card_removal"
grep -Fq 'task_delete_execution_missing' "$task_card_removal"
grep -Fq "coalesce(auth.jwt()->>'aal','aal1') <> 'aal2'" "$task_card_removal"
grep -Fq "'task_card_removed'" "$task_card_removal"
grep -Fq "'tenant_task'" "$task_card_removal"
grep -Fq 'revoke all on function public.delete_task_card_v1(uuid)' "$task_card_removal"
grep -Fq 'grant execute on function public.delete_task_card_v1(uuid)' "$task_card_removal"

# Ocultamiento personal de Tareas: preferencia privada, sin borrar la tarea global.
grep -Fq 'create table if not exists public.tenant_task_personal_hidden_v1' "$task_personal_hiding"
grep -Fq 'alter table public.tenant_task_personal_hidden_v1 enable row level security' "$task_personal_hiding"
grep -Fq 'revoke all on table public.tenant_task_personal_hidden_v1 from public,anon,authenticated' "$task_personal_hiding"
grep -Fq 'create or replace function public.hide_my_task_card_v1' "$task_personal_hiding"
grep -Fq 'create or replace function public.unhide_my_task_card_v1' "$task_personal_hiding"
grep -Fq 'create or replace function public.list_my_hidden_task_cards_v1' "$task_personal_hiding"
grep -Fq 'task_hide_requires_terminal' "$task_personal_hiding"
grep -Fq 'task_hide_forbidden' "$task_personal_hiding"
grep -Fq "ur.role in ('employee','tenant','owner')" "$task_personal_hiding"
grep -Fq 'grant execute on function public.hide_my_task_card_v1(uuid)' "$task_personal_hiding"
grep -Fq 'grant execute on function public.unhide_my_task_card_v1(uuid)' "$task_personal_hiding"
grep -Fq 'grant execute on function public.list_my_hidden_task_cards_v1()' "$task_personal_hiding"

# Fecha concreta: scheduler transversal, instante exacto e idempotencia.
grep -Fq 'create table public.workflow_application_schedules_v2' "$scheduled_once"
grep -Fq "check (schedule_kind in ('scheduled_once'))" "$scheduled_once"
grep -Fq 'create or replace function private.workflow_execute_application_internal_v1' "$scheduled_once"
grep -Fq 'create or replace function private.process_due_workflow_schedules_v1' "$scheduled_once"
grep -Fq 'for update of s skip locked' "$scheduled_once"
grep -Fq "'scheduled-once:'" "$scheduled_once"
grep -Fq 'create or replace function public.publish_workflow_ready_v2' "$scheduled_once"
grep -Fq 'create or replace function public.update_unexecuted_workflow_v2' "$scheduled_once"
grep -Fq 'create or replace function public.publish_workflow_revision_ready_v2' "$scheduled_once"
grep -Fq 'revoke all on function public.publish_workflow_ready_v2' "$scheduled_once"
grep -Fq 'create or replace function private.workflow_sanitize_authoring_spec_v3' "$scheduled_exact"
grep -Fq "'scheduledTimezone'" "$scheduled_exact"
grep -Fq "'scheduledAtUtc'" "$scheduled_exact"
grep -Fq 'workflow_schedule_time_mismatch' "$scheduled_exact"
grep -Fq 'workflow_scheduled_manual_execution_forbidden' "$scheduled_exact"
grep -Fq "last_error_code=sqlstate" "$scheduled_exact"
! grep -Fq 'sqlerrm' "$scheduled_exact"
grep -Fq "'blocked:'" "$scheduled_exact"
grep -Fq 'cron.schedule' "$scheduled_cron"
grep -Fq 'gestionpisos-workflow-schedules' "$scheduled_cron"
grep -Fq 'private.process_due_workflow_schedules_v1(now())' "$scheduled_cron"


# Fecha concreta: edición sin historial usa saneador exacto y DST ambiguo se rechaza.
grep -Fq 'create or replace function public.update_unexecuted_workflow_v1' "$scheduled_exact"
grep -Fq 'v_spec:=private.workflow_sanitize_authoring_spec_v3(p_spec);' "$scheduled_exact"
grep -Fq 'workflow_schedule_local_time_ambiguous' "$scheduled_exact"
grep -Fq 'generate_series(-180,180)' "$scheduled_exact"
grep -Fq 'reprogramming did not preserve version and exact schedule' tests/workflow-scheduled-once-regression.sql
grep -Fq 'ambiguous DST wall time unexpectedly published' tests/workflow-scheduled-once-regression.sql


# Fecha concreta: ningún RPC v1 puede dejar una aplicación scheduled sin programación.
grep -Fq 'create constraint trigger workflow_scheduled_application_requires_schedule_v1' "$scheduled_exact"
grep -Fq 'deferrable initially deferred' "$scheduled_exact"
grep -Fq 'workflow_scheduled_configuration_required' "$scheduled_exact"
grep -Fq 'scheduled v1 bypass unexpectedly committed application' tests/workflow-scheduled-once-regression.sql


# Recurrente: mismo scheduler, ancla explícita, contador y avance idempotente.
grep -Fq "check (schedule_kind in ('scheduled_once','recurring'))" "$recurring"
grep -Fq "check (trigger_kind in ('manual_now','scheduled_once','recurring'))" "$recurring"
grep -Fq 'add column if not exists next_occurrence_index bigint not null default 0' "$recurring"
grep -Fq 'add column if not exists execution_count bigint not null default 0' "$recurring"
grep -Fq 'add column if not exists last_scheduled_for timestamptz' "$recurring"
grep -Fq 'create or replace function private.workflow_recurring_occurrence_v1' "$recurring"
grep -Fq "p_trigger_kind not in ('manual_now','scheduled_once','recurring')" "$recurring"
grep -Fq "v_trigger_type in ('scheduled_once','recurring')" "$recurring"
grep -Fq "v_spec_trigger='recurring' and new.trigger_kind<>'recurring'" "$recurring"
grep -Fq "s.schedule_kind in ('scheduled_once','recurring')" "$recurring"
grep -Fq "workflow_recurring_occurrences_skipped" "$recurring"
grep -Fq "workflow_recurring_local_time_ambiguous" "$recurring"
grep -Fq "workflow_recurring_manual_execution_forbidden" "$recurring"
grep -Fq "coalesce(p_spec->>'scheduledAt','')" "$recurring"
grep -Fq "coalesce(p_spec->>'scheduledAtUtc','')" "$recurring"
! grep -Fq 'sqlerrm' "$recurring"
test "$(grep -Fc 'create or replace function public.workflow_authoring_complete_v1' "$recurring")" -eq 1
test "$(grep -Fc '$workflow_complete$;' "$recurring")" -eq 1
