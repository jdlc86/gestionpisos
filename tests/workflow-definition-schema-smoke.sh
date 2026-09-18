#!/usr/bin/env bash
set -euo pipefail

migration='supabase/migrations/20260918005500_workflow_definition_persistence.sql'
hardening='supabase/migrations/20260918010500_workflow_rpc_privilege_hardening.sql'
partial='supabase/migrations/20260918013500_workflow_partial_drafts.sql'
noop='supabase/migrations/20260918023000_workflow_draft_noop_save.sql'

test -s "$migration"
test -s "$hardening"
test -s "$partial"
test -s "$noop"
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

echo 'Workflow definition schema smoke checks passed'
