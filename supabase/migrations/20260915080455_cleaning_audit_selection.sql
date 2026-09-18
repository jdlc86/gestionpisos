-- Configurable organization policy for human cleaning-audit sampling.
-- Human audit sampling remains independent from future AI sampling.

create table if not exists public.cleaning_audit_policies_v2 (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  enabled boolean not null default true,
  human_review_probability numeric(5,4) not null default 0.2000
    check (human_review_probability >= 0 and human_review_probability <= 1),
  review_window_minutes integer not null default 1440
    check (review_window_minutes between 60 and 10080),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

alter table public.cleaning_audit_policies_v2 enable row level security;
revoke all on table public.cleaning_audit_policies_v2 from anon, authenticated;

comment on column public.cleaning_audit_policies_v2.human_review_probability is
  'Independent probability that a submitted cleaning is selected for HUMAN audit. Does not control AI sampling.';
comment on column public.cleaning_audit_policies_v2.review_window_minutes is
  'Human review window. Default 1440 minutes (24 h), configurable without schema changes.';

create or replace function private.select_cleaning_audit_v2(
  p_cleaning_task_id uuid,
  p_photo_run_id uuid,
  p_random_value double precision default random(),
  p_now timestamptz default now()
)
returns public.cleaning_audits_v2
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_task public.cleaning_tasks_v2;
  v_run public.photo_verification_runs_v2;
  v_policy public.cleaning_audit_policies_v2;
  v_selected boolean;
  v_audit public.cleaning_audits_v2;
begin
  if p_random_value < 0 or p_random_value >= 1 then
    raise exception 'random_value_out_of_range' using errcode='22023';
  end if;

  -- Idempotency: once a task has an audit envelope, never draw again.
  select * into v_audit from public.cleaning_audits_v2
   where cleaning_task_id=p_cleaning_task_id;
  if found then return v_audit; end if;

  select * into v_task from public.cleaning_tasks_v2
   where id=p_cleaning_task_id for update;
  if not found then raise exception 'cleaning_task_not_found' using errcode='P0002'; end if;

  select * into v_run from public.photo_verification_runs_v2
   where id=p_photo_run_id;
  if not found then raise exception 'photo_run_not_found' using errcode='P0002'; end if;

  if v_run.organization_id <> v_task.organization_id or v_run.property_id <> v_task.property_id then
    raise exception 'cleaning_photo_scope_mismatch' using errcode='23514';
  end if;
  if v_run.status not in ('submitted','manual_review','ai_review','approved','rejected') then
    raise exception 'photo_run_not_submitted' using errcode='55000';
  end if;

  select * into v_policy from public.cleaning_audit_policies_v2
   where organization_id=v_task.organization_id;

  if not found then
    -- Safe default policy without materializing a row.
    v_policy.organization_id := v_task.organization_id;
    v_policy.enabled := true;
    v_policy.human_review_probability := 0.2000;
    v_policy.review_window_minutes := 1440;
  end if;

  v_selected := v_policy.enabled and p_random_value < v_policy.human_review_probability;

  insert into public.cleaning_audits_v2(
    organization_id,property_id,cleaning_task_id,photo_run_id,
    selected_for_review,selection_probability,selected_at,review_deadline,status
  ) values (
    v_task.organization_id,v_task.property_id,v_task.id,v_run.id,
    v_selected,v_policy.human_review_probability,
    case when v_selected then p_now else null end,
    case when v_selected then p_now + make_interval(mins=>v_policy.review_window_minutes) else null end,
    case when v_selected then 'open' else 'not_selected' end
  )
  on conflict (cleaning_task_id) do nothing
  returning * into v_audit;

  if v_audit.id is null then
    select * into v_audit from public.cleaning_audits_v2 where cleaning_task_id=p_cleaning_task_id;
    return v_audit;
  end if;

  if v_selected then
    insert into public.cleaning_audit_items_v2(audit_id,photo_item_id)
    select v_audit.id,i.id
    from public.photo_verification_items_v2 i
    where i.run_id=v_run.id
    on conflict (audit_id,photo_item_id) do nothing;

    if not exists(select 1 from public.cleaning_audit_items_v2 where audit_id=v_audit.id) then
      raise exception 'photo_run_has_no_items' using errcode='55000';
    end if;
  else
    update public.cleaning_audits_v2
       set report_status='ready', closed_at=p_now
     where id=v_audit.id
     returning * into v_audit;
  end if;

  return v_audit;
end;
$$;

revoke all on function private.select_cleaning_audit_v2(uuid,uuid,double precision,timestamptz)
  from public, anon, authenticated;

comment on function private.select_cleaning_audit_v2(uuid,uuid,double precision,timestamptz) is
  'Idempotently draws HUMAN cleaning audit selection using organization policy. p_random_value is injectable for deterministic tests.';
