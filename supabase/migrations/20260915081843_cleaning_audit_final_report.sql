-- Build exactly one tenant-facing notification per completed cleaning audit.
-- No per-photo notifications are created.

create unique index if not exists notifications_cleaning_audit_report_uidx
on public.notifications_v2 ((split_part(event_type, ':', 2)))
where event_type like 'cleaning_audit_report:%';

create or replace function private.queue_ready_cleaning_audit_reports_v2(
  p_now timestamptz default now()
)
returns table(audit_id uuid, notification_id uuid)
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  return query
  with ready as (
    select
      a.id,
      a.organization_id,
      a.property_id,
      t.assigned_user_id as recipient_user_id,
      count(i.id) filter (where i.result='approved')::int as approved_count,
      count(i.id) filter (where i.result='rejected')::int as rejected_count,
      count(i.id) filter (where i.result='review_expired')::int as expired_count
    from public.cleaning_audits_v2 a
    join public.cleaning_tasks_v2 t on t.id=a.cleaning_task_id
    left join public.cleaning_audit_items_v2 i on i.audit_id=a.id
    where a.report_status='ready'
      and a.status in ('closed','expired')
      and t.assigned_user_id is not null
    group by a.id,a.organization_id,a.property_id,t.assigned_user_id
    for update of a skip locked
  ),
  ins as (
    insert into public.notifications_v2(
      organization_id,recipient_user_id,event_type,title,body,
      channel_in_app,channel_email,status
    )
    select
      r.organization_id,
      r.recipient_user_id,
      'cleaning_audit_report:'||r.id::text,
      'Informe de limpieza',
      case
        when r.rejected_count > 0 then
          'Revisión finalizada. '||r.rejected_count||' foto(s) requieren atención.'
        when r.approved_count > 0 and r.expired_count = 0 then
          'Revisión finalizada. La limpieza revisada ha sido aprobada.'
        when r.expired_count > 0 then
          'Revisión finalizada. No fue necesario revisar todas las fotos dentro del plazo.'
        else
          'La limpieza ha quedado registrada correctamente.'
      end,
      true,false,'pending'
    from ready r
    on conflict do nothing
    returning id,event_type
  ),
  marked as (
    update public.cleaning_audits_v2 a
       set report_status='sent',report_sent_at=p_now
      from ready r
     where a.id=r.id
       and (
         exists(select 1 from ins x where x.event_type='cleaning_audit_report:'||a.id::text)
         or exists(select 1 from public.notifications_v2 n where n.event_type='cleaning_audit_report:'||a.id::text)
       )
    returning a.id
  )
  select m.id,n.id
  from marked m
  join public.notifications_v2 n on n.event_type='cleaning_audit_report:'||m.id::text;
end;
$$;

revoke all on function private.queue_ready_cleaning_audit_reports_v2(timestamptz)
from public,anon,authenticated;

comment on function private.queue_ready_cleaning_audit_reports_v2(timestamptz) is
  'Queues one aggregate tenant notification per closed/expired cleaning audit; never one notification per photo.';

select cron.unschedule(jobid)
from cron.job
where jobname='gestionpisos-cleaning-audit-report';

select cron.schedule(
  'gestionpisos-cleaning-audit-report',
  '*/5 * * * *',
  'select private.queue_ready_cleaning_audit_reports_v2(now());'
);
