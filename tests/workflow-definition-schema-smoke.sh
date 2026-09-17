#!/usr/bin/env bash
set -euo pipefail

migration='supabase/migrations/20260918005500_workflow_definition_persistence.sql'
hardening='supabase/migrations/20260918010500_workflow_rpc_privilege_hardening.sql'

test -s "$migration"
test -s "$hardening"
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

echo 'Workflow definition schema smoke checks passed'
