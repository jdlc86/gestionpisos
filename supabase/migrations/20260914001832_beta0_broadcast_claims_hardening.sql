alter table public.broadcasts_v2
  add column if not exists channel_in_app boolean not null default true,
  add column if not exists channel_email boolean not null default false;

alter table public.broadcasts_v2
  add constraint broadcasts_property_audience_check
  check (audience <> 'property' or property_id is not null) not valid;

alter table public.broadcasts_v2
  validate constraint broadcasts_property_audience_check;

alter table public.broadcasts_v2
  add constraint broadcasts_schedule_check
  check (status <> 'scheduled' or scheduled_for is not null) not valid;

alter table public.broadcasts_v2
  validate constraint broadcasts_schedule_check;

create or replace function private.process_due_notifications()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications_v2(
    organization_id,
    recipient_user_id,
    event_type,
    title,
    body,
    channel_in_app,
    channel_email,
    status
  )
  select
    po.organization_id,
    po.tenant_user_id,
    'payment_due',
    'Recordatorio de pago',
    po.concept || ' vence el ' || po.due_date::text,
    rr.channel_in_app,
    rr.channel_email,
    'pending'
  from public.payment_obligations_v2 po
  join public.reminder_rules_v2 rr
    on rr.organization_id = po.organization_id
   and rr.event_type = 'payment_due'
   and rr.active = true
   and (rr.property_id is null or rr.property_id = po.property_id)
  where po.tenant_user_id is not null
    and po.status = 'pending'
    and po.due_date = current_date + rr.days_offset
    and not exists (
      select 1 from public.notifications_v2 n
      where n.recipient_user_id = po.tenant_user_id
        and n.event_type = 'payment_due'
        and n.body = po.concept || ' vence el ' || po.due_date::text
        and n.created_at::date = current_date
    );

  update public.payment_obligations_v2
  set status = 'overdue'
  where status = 'pending'
    and due_date < current_date;

  insert into public.notifications_v2(
    organization_id,
    recipient_user_id,
    event_type,
    title,
    body,
    channel_in_app,
    channel_email,
    status
  )
  select
    po.organization_id,
    po.tenant_user_id,
    'payment_overdue',
    'Pago pendiente',
    po.concept || ' está vencido desde el ' || po.due_date::text,
    rr.channel_in_app,
    rr.channel_email,
    'pending'
  from public.payment_obligations_v2 po
  join public.reminder_rules_v2 rr
    on rr.organization_id = po.organization_id
   and rr.event_type = 'payment_overdue'
   and rr.active = true
   and (rr.property_id is null or rr.property_id = po.property_id)
  where po.tenant_user_id is not null
    and po.status = 'overdue'
    and not exists (
      select 1 from public.notifications_v2 n
      where n.recipient_user_id = po.tenant_user_id
        and n.event_type = 'payment_overdue'
        and n.body = po.concept || ' está vencido desde el ' || po.due_date::text
        and n.created_at::date = current_date
    );

  insert into public.notifications_v2(
    organization_id,
    recipient_user_id,
    event_type,
    title,
    body,
    channel_in_app,
    channel_email,
    status
  )
  select
    c.organization_id,
    c.tenant_user_id,
    'claim',
    c.title,
    c.body,
    true,
    true,
    'pending'
  from public.claims_v2 c
  where c.status = 'scheduled'
    and c.scheduled_for <= now()
    and c.tenant_user_id is not null
    and not exists (
      select 1 from public.notifications_v2 n
      where n.recipient_user_id = c.tenant_user_id
        and n.event_type = 'claim'
        and n.title = c.title
        and n.body = c.body
        and n.created_at >= c.created_at
    );

  update public.claims_v2
  set status = 'sent',
      sent_at = now()
  where status = 'scheduled'
    and scheduled_for <= now();

  insert into public.notifications_v2(
    organization_id,
    recipient_user_id,
    event_type,
    title,
    body,
    channel_in_app,
    channel_email,
    status
  )
  select
    b.organization_id,
    ur.user_id,
    'broadcast',
    b.title,
    b.body,
    b.channel_in_app,
    b.channel_email,
    'pending'
  from public.broadcasts_v2 b
  join public.user_roles ur
    on ur.organization_id = b.organization_id
   and ur.revoked_at is null
  where b.status = 'scheduled'
    and b.scheduled_for <= now()
    and (
      b.audience = 'all'
      or (b.audience = 'owners' and ur.role = 'owner')
      or (b.audience = 'employees' and ur.role = 'employee')
      or (b.audience = 'tenants' and ur.role = 'tenant')
      or (
        b.audience = 'property'
        and (
          exists (
            select 1 from public.occupancies_v2 o
            where o.property_id = b.property_id
              and o.user_id = ur.user_id
              and o.status = 'active'
              and o.starts_on <= current_date
              and (o.ends_on is null or o.ends_on >= current_date)
          )
          or exists (
            select 1 from public.property_staff_access_v3 s
            where s.property_id = b.property_id
              and s.employee_user_id = ur.user_id
              and s.revoked_at is null
              and (s.valid_until is null or s.valid_until > now())
          )
          or exists (
            select 1 from public.owners ow
            join public.properties_v2 p on p.owner_id = ow.id
            where p.id = b.property_id
              and ow.user_id = ur.user_id
              and ow.archived_at is null
          )
        )
      )
    )
    and not exists (
      select 1 from public.notifications_v2 n
      where n.recipient_user_id = ur.user_id
        and n.event_type = 'broadcast'
        and n.title = b.title
        and n.body = b.body
        and n.created_at >= b.created_at
    );

  update public.broadcasts_v2
  set status = 'sent',
      sent_at = now()
  where status = 'scheduled'
    and scheduled_for <= now();
end;
$$;