#!/usr/bin/env bash
set -euo pipefail

migration='supabase/migrations/20260918005500_workflow_definition_persistence.sql'
hardening='supabase/migrations/20260918010500_workflow_rpc_privilege_hardening.sql'
partial='supabase/migrations/20260918013500_workflow_partial_drafts.sql'
noop='supabase/migrations/20260918023000_workflow_draft_noop_save.sql'
triggers='supabase/migrations/20260918025500_workflow_trigger_controls.sql'
applications='supabase/migrations/20260918095001_workflow_publication_applications.sql'

test -s "$migration"
test -s "$hardening"
test -s "$partial"
test -s "$noop"
test -s "$triggers"
test -s "$applications"
test -s tests/workflow-definition-regression.sql

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

echo 'Workflow definition schema smoke checks passed'
