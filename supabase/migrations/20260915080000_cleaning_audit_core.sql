-- Additive schema for recurrent cleaning audits.
-- Existing photo verification rows keep their current semantics.

create table if not exists public.cleaning_audits_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations_v2(id),
  property_id uuid not null references public.properties_v2(id),
  cleaning_task_id uuid not null references public.cleaning_tasks_v2(id),
  photo_run_id uuid references public.photo_verification_runs_v2(id),
  selected_for_review boolean not null default false,
  selection_probability numeric(5,4),
  selected_at timestamptz,
  review_deadline timestamptz,
  status text not null default 'not_selected'
    check (status in ('not_selected','open','closed','expired')),
  closed_at timestamptz,
  report_status text not null default 'pending'
    check (report_status in ('pending','ready','sent')),
  report_sent_at timestamptz,
  created_at timestamptz not null default now(),
  constraint cleaning_audits_selection_probability_check
    check (selection_probability is null or (selection_probability >= 0 and selection_probability <= 1)),
  constraint cleaning_audits_selected_fields_check
    check (
      (selected_for_review and selected_at is not null and review_deadline is not null and status <> 'not_selected')
      or
      (not selected_for_review and selected_at is null and review_deadline is null and status = 'not_selected')
    )
);

create unique index if not exists cleaning_audits_task_uidx
  on public.cleaning_audits_v2(cleaning_task_id);
create index if not exists cleaning_audits_review_queue_idx
  on public.cleaning_audits_v2(organization_id,status,review_deadline)
  where selected_for_review;

create table if not exists public.cleaning_audit_items_v2 (
  id uuid primary key default gen_random_uuid(),
  audit_id uuid not null references public.cleaning_audits_v2(id) on delete cascade,
  photo_item_id uuid not null references public.photo_verification_items_v2(id),
  result text not null default 'pending'
    check (result in ('pending','approved','rejected','review_expired')),
  rejection_reason text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint cleaning_audit_items_photo_uidx unique(audit_id,photo_item_id),
  constraint cleaning_audit_items_result_fields_check check (
    (result = 'pending' and reviewed_by is null and reviewed_at is null and rejection_reason is null)
    or
    (result = 'approved' and reviewed_by is not null and reviewed_at is not null and rejection_reason is null)
    or
    (result = 'rejected' and reviewed_by is not null and reviewed_at is not null and nullif(btrim(rejection_reason),'') is not null)
    or
    (result = 'review_expired' and reviewed_by is null and reviewed_at is null and rejection_reason is null)
  )
);

create index if not exists cleaning_audit_items_audit_idx
  on public.cleaning_audit_items_v2(audit_id,result);

alter table public.cleaning_audits_v2 enable row level security;
alter table public.cleaning_audit_items_v2 enable row level security;

-- Deliberately no direct client policies yet. Access will be introduced through
-- narrowly scoped RPC/Edge Functions after the lifecycle is implemented and tested.
revoke all on table public.cleaning_audits_v2 from anon, authenticated;
revoke all on table public.cleaning_audit_items_v2 from anon, authenticated;

comment on table public.cleaning_audits_v2 is
  'Audit envelope for a cleaning task. Selection is distinct from approval.';
comment on column public.cleaning_audits_v2.review_deadline is
  'Deadline after which pending audit items become review_expired; duration is policy/configuration, not encoded here.';
comment on table public.cleaning_audit_items_v2 is
  'Per-photo human audit decisions for a cleaning audit.';
comment on column public.cleaning_audit_items_v2.result is
  'review_expired is neutral: it is neither approved nor rejected.';
