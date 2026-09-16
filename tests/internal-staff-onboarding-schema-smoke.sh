#!/usr/bin/env bash
set -euo pipefail

MIGRATION='supabase/migrations/20260916190000_internal_staff_onboarding.sql'
test -s "$MIGRATION"

grep -Fq 'create table if not exists public.internal_staff_onboarding (' "$MIGRATION"
grep -Fq 'create table if not exists public.internal_staff_onboarding_access_snapshot (' "$MIGRATION"
grep -Fq 'alter table public.internal_staff_onboarding enable row level security' "$MIGRATION"
grep -Fq 'alter table public.internal_staff_onboarding_access_snapshot enable row level security' "$MIGRATION"
grep -Fq 'revoke all on table public.internal_staff_onboarding from public, anon, authenticated' "$MIGRATION"
grep -Fq 'revoke all on table public.internal_staff_onboarding_access_snapshot from public, anon, authenticated' "$MIGRATION"

grep -Fq 'create or replace function public.provision_internal_staff_pending' "$MIGRATION"
grep -Fq 'create or replace function public.claim_internal_staff_invitation_attempt' "$MIGRATION"
grep -Fq 'create or replace function public.record_internal_staff_invitation_result' "$MIGRATION"
grep -Fq 'create or replace function public.get_my_internal_staff_onboarding()' "$MIGRATION"
grep -Fq 'create or replace function public.complete_internal_staff_onboarding()' "$MIGRATION"
grep -Fq 'grant execute on function public.get_my_internal_staff_onboarding() to authenticated, service_role' "$MIGRATION"
grep -Fq 'grant execute on function public.complete_internal_staff_onboarding() to authenticated, service_role' "$MIGRATION"
grep -Fq 'grant execute on function public.provision_internal_staff_pending' "$MIGRATION"

grep -Fq "status='pending'" "$MIGRATION"
grep -Fq 'last_sign_in_at is null' "$MIGRATION"
grep -Fq "au.created_at >= timestamptz '2026-09-16 16:50:00+00'" "$MIGRATION"
grep -Fq 'internal_staff_onboarding_access_snapshot' "$MIGRATION"
grep -Fq 'set revoked_at=now()' "$MIGRATION"
grep -Fq "restore_result='restored'" "$MIGRATION"
grep -Fq "restore_result='skipped_responsible_conflict'" "$MIGRATION"
grep -Fq "'onboarding_status',u.onboarding_status" "$MIGRATION"
grep -Fq "o.status='pending'" "$MIGRATION"
grep -Fq "onboarding_revoked" "$MIGRATION"

# Backfill is intentionally evidence-scoped; generated/auth UUIDs must not be hardcoded.
! grep -Fq '7cbb88da-1ae1-47d8-a86b-f92e83cfd1b8' "$MIGRATION"
! grep -Fq 'babc09fd-69f7-4976-810c-c3aaaf976238' "$MIGRATION"

echo 'Internal staff onboarding schema smoke checks passed'
