-- Server-side lifecycle primitives for cleaning audits.
-- UI and notifications are intentionally not connected in this migration.

create or replace function private.close_expired_cleaning_audits_v2(
  p_now timestamptz default now()
)
returns table(audit_id uuid, expired_items integer)
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  return query
  with due as (
    select a.id
    from public.cleaning_audits_v2 a
    where a.selected_for_review
      and a.status = 'open'
      and a.review_deadline <= p_now
    for update skip locked
  ),
  expired as (
    update public.cleaning_audit_items_v2 i
       set result = 'review_expired'
      from due
     where i.audit_id = due.id
       and i.result = 'pending'
    returning i.audit_id
  ),
  counts as (
    select e.audit_id, count(*)::integer as expired_items
    from expired e group by e.audit_id
  ),
  closed as (
    update public.cleaning_audits_v2 a
       set status = 'expired',
           closed_at = coalesce(a.closed_at,p_now),
           report_status = case when a.report_status='pending' then 'ready' else a.report_status end
      from due
     where a.id = due.id
    returning a.id
  )
  select c.id, coalesce(n.expired_items,0)
  from closed c left join counts n on n.audit_id=c.id;
end;
$$;

revoke all on function private.close_expired_cleaning_audits_v2(timestamptz) from public, anon, authenticated;

create or replace function private.apply_cleaning_audit_item_review_v2(
  p_audit_id uuid,
  p_photo_item_id uuid,
  p_actor_user_id uuid,
  p_decision text,
  p_rejection_reason text default null,
  p_now timestamptz default now()
)
returns public.cleaning_audit_items_v2
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_audit public.cleaning_audits_v2;
  v_item public.cleaning_audit_items_v2;
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'invalid_decision' using errcode='22023';
  end if;
  if p_decision='rejected' and nullif(btrim(coalesce(p_rejection_reason,'')),'') is null then
    raise exception 'rejection_reason_required' using errcode='22023';
  end if;

  select * into v_audit
  from public.cleaning_audits_v2
  where id=p_audit_id
  for update;

  if not found then raise exception 'audit_not_found' using errcode='P0002'; end if;
  if not v_audit.selected_for_review or v_audit.status <> 'open' then
    raise exception 'audit_not_reviewable' using errcode='55000';
  end if;
  if v_audit.review_deadline <= p_now then
    raise exception 'review_deadline_exceeded' using errcode='55000';
  end if;

  update public.cleaning_audit_items_v2
     set result=p_decision,
         rejection_reason=case when p_decision='rejected' then btrim(p_rejection_reason) else null end,
         reviewed_by=p_actor_user_id,
         reviewed_at=p_now
   where audit_id=p_audit_id
     and photo_item_id=p_photo_item_id
     and result='pending'
  returning * into v_item;

  if not found then raise exception 'item_not_pending' using errcode='55000'; end if;

  if not exists (
    select 1 from public.cleaning_audit_items_v2
    where audit_id=p_audit_id and result='pending'
  ) then
    update public.cleaning_audits_v2
       set status='closed', closed_at=p_now, report_status='ready'
     where id=p_audit_id and status='open';
  end if;

  return v_item;
end;
$$;

revoke all on function private.apply_cleaning_audit_item_review_v2(uuid,uuid,uuid,text,text,timestamptz) from public, anon, authenticated;

comment on function private.close_expired_cleaning_audits_v2(timestamptz) is
  'Idempotently expires pending photo decisions after their audit deadline and marks one report ready.';
comment on function private.apply_cleaning_audit_item_review_v2(uuid,uuid,uuid,text,text,timestamptz) is
  'Applies one human decision before deadline; closes audit when no pending items remain.';
