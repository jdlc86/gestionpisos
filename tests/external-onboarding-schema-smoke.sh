#!/usr/bin/env bash
set -euo pipefail

MIGRATION='supabase/migrations/20260916183835_external_owner_tenant_onboarding.sql'
test -s "$MIGRATION"

grep -Fq 'create table if not exists public.external_account_onboarding (' "$MIGRATION"
grep -Fq "subject_type in ('owner','tenant')" "$MIGRATION"
grep -Fq "intended_role in ('owner'::public.app_role,'tenant'::public.app_role)" "$MIGRATION"
grep -Fq 'external_account_onboarding_current_email_uidx' "$MIGRATION"
grep -Fq "where status in ('pending','active')" "$MIGRATION"
grep -Fq 'alter table public.external_account_onboarding enable row level security' "$MIGRATION"
grep -Fq 'revoke all on table public.external_account_onboarding from public, anon, authenticated' "$MIGRATION"

grep -Fq 'create or replace function public.provision_external_account_pending' "$MIGRATION"
grep -Fq 'create or replace function public.get_my_external_account_onboarding()' "$MIGRATION"
grep -Fq 'create or replace function public.complete_external_account_onboarding' "$MIGRATION"
grep -Fq 'create or replace function public.get_external_onboarding_statuses' "$MIGRATION"
grep -Fq 'service_role_required' "$MIGRATION"
grep -Fq 'auth_identity_internal_conflict' "$MIGRATION"
grep -Fq 'auth_identity_role_conflict' "$MIGRATION"
grep -Fq 'external_auth_email_mismatch' "$MIGRATION"
grep -Fq 'owner_auth_identity_conflict' "$MIGRATION"
grep -Fq 'tenant_auth_identity_conflict' "$MIGRATION"
grep -Fq 'occupancy_auth_identity_conflict' "$MIGRATION"

grep -Fq 'update public.owners set user_id=p_auth_user_id' "$MIGRATION"
grep -Fq 'update public.tenants_v2 set user_id=p_auth_user_id' "$MIGRATION"
grep -Fq 'update public.occupancies_v2 set user_id=p_auth_user_id' "$MIGRATION"
grep -Fq 'tenants_v2_self_read' "$MIGRATION"
grep -Fq 'tenant_documents_v2_tenant_self_read' "$MIGRATION"

# Completion is intentionally service-role only: the caller identity is verified in the Edge Function.
grep -Fq 'revoke all on function public.complete_external_account_onboarding(uuid) from public,anon,authenticated' "$MIGRATION"
grep -Fq 'grant execute on function public.complete_external_account_onboarding(uuid) to service_role' "$MIGRATION"

echo 'External owner/tenant onboarding schema smoke checks passed'
