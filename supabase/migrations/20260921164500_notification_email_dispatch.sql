-- GestionPisos · notificaciones email asíncronas
-- Infraestructura transversal: notifications_v2.channel_email=true dispara
-- una Edge Function vía pg_net. La notificación canónica nunca se revierte
-- si el proveedor de email falla.

create schema if not exists private;
create schema if not exists extensions;

do $notification_email_pg_net$
begin
  if exists(select 1 from pg_available_extensions where name='pg_net') then
    execute 'create extension if not exists pg_net';
  end if;
end;
$notification_email_pg_net$;

create table if not exists public.notification_email_deliveries_v1(
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null
    references public.notifications_v2(id) on delete cascade,
  status text not null default 'sending'
    check(status in ('sending','sent','failed')),
  attempted_at timestamptz not null default now(),
  finished_at timestamptz,
  provider_message_id text,
  error_code text,
  constraint notification_email_deliveries_notification_uq
    unique(notification_id)
);

create index if not exists notification_email_deliveries_status_idx
  on public.notification_email_deliveries_v1(status,attempted_at desc);

alter table public.notification_email_deliveries_v1 enable row level security;
revoke all on public.notification_email_deliveries_v1
  from public,anon,authenticated;
grant select,insert,update,delete on public.notification_email_deliveries_v1
  to service_role;

do $notification_email_dispatch_secret$
declare
  v_exists boolean:=false;
begin
  if to_regprocedure('vault.create_secret(text,text,text,uuid)') is null then
    return;
  end if;

  execute
    'select exists(select 1 from vault.decrypted_secrets where name=$1)'
    into v_exists
    using 'gestionpisos_notification_email_dispatch_secret_v1';

  if not v_exists then
    execute 'select vault.create_secret($1,$2,$3,null)'
      using
        gen_random_uuid()::text||gen_random_uuid()::text,
        'gestionpisos_notification_email_dispatch_secret_v1',
        'Internal DB -> Edge Function notification email dispatch secret';
  end if;
end;
$notification_email_dispatch_secret$;

create or replace function public.notification_email_server_config_v1()
returns table(dispatch_secret text)
language plpgsql
security definer
set search_path=''
as $notification_email_config$
declare
  v_dispatch text;
begin
  if to_regclass('vault.decrypted_secrets') is null then
    return query select null::text;
    return;
  end if;

  execute
    'select decrypted_secret
       from vault.decrypted_secrets
      where name=$1
      limit 1'
  into v_dispatch
  using 'gestionpisos_notification_email_dispatch_secret_v1';

  return query select v_dispatch;
end;
$notification_email_config$;

revoke all on function public.notification_email_server_config_v1()
  from public,anon,authenticated;
grant execute on function public.notification_email_server_config_v1()
  to service_role;

create or replace function public.notification_email_claim_delivery_v1(
  p_notification_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=''
as $notification_email_claim$
declare
  v_count integer;
begin
  insert into public.notification_email_deliveries_v1(
    notification_id,status,attempted_at
  )
  select n.id,'sending',now()
  from public.notifications_v2 n
  where n.id=p_notification_id
    and n.channel_email=true
    and n.recipient_user_id is not null
  on conflict(notification_id) do nothing;

  get diagnostics v_count=row_count;
  return v_count=1;
end;
$notification_email_claim$;

revoke all on function public.notification_email_claim_delivery_v1(uuid)
  from public,anon,authenticated;
grant execute on function public.notification_email_claim_delivery_v1(uuid)
  to service_role;

create or replace function public.notification_email_finish_delivery_v1(
  p_notification_id uuid,
  p_success boolean,
  p_error_code text default null,
  p_provider_message_id text default null
)
returns void
language plpgsql
security definer
set search_path=''
as $notification_email_finish$
begin
  update public.notification_email_deliveries_v1
  set status=case when p_success then 'sent' else 'failed' end,
      finished_at=now(),
      provider_message_id=case
        when p_success then left(nullif(btrim(coalesce(p_provider_message_id,'')),''),240)
        else null
      end,
      error_code=case
        when p_success then null
        else left(nullif(btrim(coalesce(p_error_code,'')),''),160)
      end
  where notification_id=p_notification_id;
end;
$notification_email_finish$;

revoke all on function public.notification_email_finish_delivery_v1(
  uuid,boolean,text,text
) from public,anon,authenticated;
grant execute on function public.notification_email_finish_delivery_v1(
  uuid,boolean,text,text
) to service_role;

create or replace function private.notification_email_dispatch_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $notification_email_dispatch$
declare
  v_secret text;
  v_url text:='https://qsxtmmkftsohkqqmytbb.supabase.co/functions/v1/notification-email';
  v_request_id bigint;
begin
  if new.channel_email is distinct from true
    or new.recipient_user_id is null then
    return new;
  end if;

  if not exists(select 1 from pg_extension where extname='pg_net')
    or to_regclass('vault.decrypted_secrets') is null then
    return new;
  end if;

  execute
    'select decrypted_secret from vault.decrypted_secrets where name=$1 limit 1'
    into v_secret
    using 'gestionpisos_notification_email_dispatch_secret_v1';

  if nullif(v_secret,'') is null then
    return new;
  end if;

  execute
    'select net.http_post($1,$2,$3,$4,$5)'
    into v_request_id
    using
      v_url,
      jsonb_build_object('notification_id',new.id),
      '{}'::jsonb,
      jsonb_build_object(
        'Content-Type','application/json',
        'X-Allaiso-Email-Secret',v_secret
      ),
      5000;

  return new;
exception when others then
  -- Email delivery is secondary; never roll back the canonical notification.
  return new;
end;
$notification_email_dispatch$;

revoke all on function private.notification_email_dispatch_v1()
  from public,anon,authenticated;

drop trigger if exists notification_email_dispatch_v1
  on public.notifications_v2;

create trigger notification_email_dispatch_v1
after insert on public.notifications_v2
for each row
execute function private.notification_email_dispatch_v1();

comment on table public.notification_email_deliveries_v1 is
  'Idempotent email delivery receipt per canonical notification.';
comment on function private.notification_email_dispatch_v1() is
  'Asynchronously dispatches notifications_v2.channel_email via pg_net to notification-email Edge Function using a Vault-backed secret.';
