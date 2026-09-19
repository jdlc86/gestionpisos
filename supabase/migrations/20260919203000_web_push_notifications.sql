-- GestionPisos · Web Push notifications
-- Adds device subscriptions, VAPID material in Supabase Vault, delivery idempotency
-- and an asynchronous notification -> Edge Function bridge. No client polling.

create schema if not exists private;
create schema if not exists extensions;

do $web_push_pg_net$
begin
  if exists(select 1 from pg_available_extensions where name='pg_net') then
    execute 'create extension if not exists pg_net with schema extensions';
  end if;
end;
$web_push_pg_net$;

create table if not exists public.web_push_subscriptions_v1(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth_secret text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  disabled_at timestamptz,
  last_success_at timestamptz,
  failure_count integer not null default 0,
  last_error_code text,
  constraint web_push_subscriptions_endpoint_uq unique(endpoint),
  constraint web_push_subscriptions_endpoint_check check (
    char_length(endpoint) between 16 and 4096
    and endpoint ~ '^https://'
  ),
  constraint web_push_subscriptions_key_check check (
    char_length(p256dh) between 16 and 1024
    and char_length(auth_secret) between 8 and 512
  ),
  constraint web_push_subscriptions_failure_count_check check (failure_count >= 0)
);

create index if not exists web_push_subscriptions_user_active_idx
  on public.web_push_subscriptions_v1(user_id,updated_at desc)
  where disabled_at is null;

alter table public.web_push_subscriptions_v1 enable row level security;
revoke all on table public.web_push_subscriptions_v1 from public,anon,authenticated;
grant select,insert,update,delete on table public.web_push_subscriptions_v1 to service_role;

create table if not exists public.web_push_deliveries_v1(
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications_v2(id) on delete cascade,
  subscription_id uuid not null references public.web_push_subscriptions_v1(id) on delete cascade,
  status text not null default 'sending',
  attempted_at timestamptz not null default now(),
  finished_at timestamptz,
  error_code text,
  constraint web_push_deliveries_state_check check (status in ('sending','sent','failed')),
  constraint web_push_deliveries_notification_subscription_uq unique(notification_id,subscription_id)
);

create index if not exists web_push_deliveries_notification_idx
  on public.web_push_deliveries_v1(notification_id,attempted_at desc);

alter table public.web_push_deliveries_v1 enable row level security;
revoke all on table public.web_push_deliveries_v1 from public,anon,authenticated;
grant select,insert,update,delete on table public.web_push_deliveries_v1 to service_role;

do $web_push_dispatch_secret$
declare
  v_exists boolean:=false;
begin
  if to_regprocedure('vault.create_secret(text,text,text,uuid)') is null then
    return;
  end if;

  execute
    'select exists(select 1 from vault.decrypted_secrets where name=$1)'
    into v_exists
    using 'gestionpisos_web_push_dispatch_secret_v1';

  if not v_exists then
    execute 'select vault.create_secret($1,$2,$3,null)'
      using
        gen_random_uuid()::text||gen_random_uuid()::text,
        'gestionpisos_web_push_dispatch_secret_v1',
        'Internal DB -> Edge Function Web Push dispatch secret';
  end if;
end;
$web_push_dispatch_secret$;

create or replace function public.register_web_push_subscription_v1(
  p_endpoint text,
  p_p256dh text,
  p_auth_secret text,
  p_user_agent text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $register_web_push$
declare
  v_actor uuid:=auth.uid();
  v_id uuid;
begin
  if v_actor is null then
    raise exception 'authentication_required' using errcode='28000';
  end if;

  p_endpoint:=btrim(coalesce(p_endpoint,''));
  p_p256dh:=btrim(coalesce(p_p256dh,''));
  p_auth_secret:=btrim(coalesce(p_auth_secret,''));
  p_user_agent:=nullif(left(btrim(coalesce(p_user_agent,'')),512),'');

  if char_length(p_endpoint) not between 16 and 4096
    or p_endpoint !~ '^https://'
    or char_length(p_p256dh) not between 16 and 1024
    or char_length(p_auth_secret) not between 8 and 512 then
    raise exception 'web_push_subscription_invalid' using errcode='22023';
  end if;

  insert into public.web_push_subscriptions_v1(
    user_id,endpoint,p256dh,auth_secret,user_agent,
    disabled_at,last_success_at,failure_count,last_error_code,created_at,updated_at
  ) values (
    v_actor,p_endpoint,p_p256dh,p_auth_secret,p_user_agent,
    null,null,0,null,now(),now()
  )
  on conflict(endpoint) do update
  set user_id=excluded.user_id,
      p256dh=excluded.p256dh,
      auth_secret=excluded.auth_secret,
      user_agent=excluded.user_agent,
      disabled_at=null,
      failure_count=0,
      last_error_code=null,
      updated_at=now()
  where public.web_push_subscriptions_v1.user_id=excluded.user_id
     or (
       public.web_push_subscriptions_v1.p256dh=excluded.p256dh
       and public.web_push_subscriptions_v1.auth_secret=excluded.auth_secret
     )
  returning id into v_id;

  if v_id is null then
    raise exception 'web_push_subscription_conflict' using errcode='42501';
  end if;

  return v_id;
end;
$register_web_push$;

revoke all on function public.register_web_push_subscription_v1(text,text,text,text)
  from public,anon;
grant execute on function public.register_web_push_subscription_v1(text,text,text,text)
  to authenticated;

create or replace function public.unregister_web_push_subscription_v1(
  p_endpoint text
)
returns boolean
language plpgsql
security definer
set search_path=''
as $unregister_web_push$
declare
  v_actor uuid:=auth.uid();
  v_count integer;
begin
  if v_actor is null then
    raise exception 'authentication_required' using errcode='28000';
  end if;

  update public.web_push_subscriptions_v1
  set disabled_at=coalesce(disabled_at,now()),
      updated_at=now()
  where user_id=v_actor
    and endpoint=btrim(coalesce(p_endpoint,''))
    and disabled_at is null;

  get diagnostics v_count=row_count;
  return v_count>0;
end;
$unregister_web_push$;

revoke all on function public.unregister_web_push_subscription_v1(text)
  from public,anon;
grant execute on function public.unregister_web_push_subscription_v1(text)
  to authenticated;

create or replace function public.web_push_server_config_v1()
returns table(
  dispatch_secret text,
  vapid_public_key text,
  vapid_private_key text
)
language plpgsql
security definer
set search_path=''
as $web_push_server_config$
declare
  v_dispatch text;
  v_public text;
  v_private text;
begin
  if to_regclass('vault.decrypted_secrets') is null then
    return query select null::text,null::text,null::text;
    return;
  end if;

  execute
    'select
       max(decrypted_secret) filter (where name=$1),
       max(decrypted_secret) filter (where name=$2),
       max(decrypted_secret) filter (where name=$3)
     from vault.decrypted_secrets'
  into v_dispatch,v_public,v_private
  using
    'gestionpisos_web_push_dispatch_secret_v1',
    'gestionpisos_web_push_vapid_public_v1',
    'gestionpisos_web_push_vapid_private_v1';

  return query select v_dispatch,v_public,v_private;
end;
$web_push_server_config$;

revoke all on function public.web_push_server_config_v1()
  from public,anon,authenticated;
grant execute on function public.web_push_server_config_v1()
  to service_role;

create or replace function public.web_push_store_vapid_v1(
  p_public_key text,
  p_private_key text
)
returns void
language plpgsql
security definer
set search_path=''
as $web_push_store_vapid$
declare
  v_exists boolean;
begin
  if char_length(btrim(coalesce(p_public_key,''))) not between 32 and 512
    or char_length(btrim(coalesce(p_private_key,''))) not between 16 and 512 then
    raise exception 'web_push_vapid_invalid' using errcode='22023';
  end if;

  if to_regprocedure('vault.create_secret(text,text,text,uuid)') is null then
    raise exception 'web_push_vault_unavailable' using errcode='55000';
  end if;

  perform pg_advisory_xact_lock(hashtext('gestionpisos_web_push_vapid_v1'));

  execute
    'select exists(select 1 from vault.decrypted_secrets where name=$1)'
    into v_exists
    using 'gestionpisos_web_push_vapid_public_v1';
  if not v_exists then
    execute 'select vault.create_secret($1,$2,$3,null)'
      using btrim(p_public_key),
        'gestionpisos_web_push_vapid_public_v1',
        'Web Push VAPID public key';
  end if;

  execute
    'select exists(select 1 from vault.decrypted_secrets where name=$1)'
    into v_exists
    using 'gestionpisos_web_push_vapid_private_v1';
  if not v_exists then
    execute 'select vault.create_secret($1,$2,$3,null)'
      using btrim(p_private_key),
        'gestionpisos_web_push_vapid_private_v1',
        'Web Push VAPID private key';
  end if;
end;
$web_push_store_vapid$;

revoke all on function public.web_push_store_vapid_v1(text,text)
  from public,anon,authenticated;
grant execute on function public.web_push_store_vapid_v1(text,text)
  to service_role;

create or replace function public.web_push_list_subscriptions_v1(
  p_user_id uuid
)
returns table(
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth_secret text
)
language sql
security definer
set search_path=''
as $web_push_list_subscriptions$
  select s.id,s.endpoint,s.p256dh,s.auth_secret
  from public.web_push_subscriptions_v1 s
  where s.user_id=p_user_id
    and s.disabled_at is null
  order by s.updated_at desc;
$web_push_list_subscriptions$;

revoke all on function public.web_push_list_subscriptions_v1(uuid)
  from public,anon,authenticated;
grant execute on function public.web_push_list_subscriptions_v1(uuid)
  to service_role;

create or replace function public.web_push_claim_delivery_v1(
  p_notification_id uuid,
  p_subscription_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=''
as $web_push_claim_delivery$
declare
  v_count integer;
begin
  insert into public.web_push_deliveries_v1(
    notification_id,subscription_id,status,attempted_at
  )
  select p_notification_id,p_subscription_id,'sending',now()
  from public.notifications_v2 n
  join public.web_push_subscriptions_v1 s
    on s.id=p_subscription_id
   and s.user_id=n.recipient_user_id
   and s.disabled_at is null
  where n.id=p_notification_id
  on conflict(notification_id,subscription_id) do nothing;

  get diagnostics v_count=row_count;
  return v_count=1;
end;
$web_push_claim_delivery$;

revoke all on function public.web_push_claim_delivery_v1(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.web_push_claim_delivery_v1(uuid,uuid)
  to service_role;

create or replace function public.web_push_finish_delivery_v1(
  p_notification_id uuid,
  p_subscription_id uuid,
  p_success boolean,
  p_error_code text default null,
  p_disable_subscription boolean default false
)
returns void
language plpgsql
security definer
set search_path=''
as $web_push_finish_delivery$
begin
  update public.web_push_deliveries_v1
  set status=case when p_success then 'sent' else 'failed' end,
      finished_at=now(),
      error_code=case when p_success then null else left(nullif(btrim(coalesce(p_error_code,'')),''),120) end
  where notification_id=p_notification_id
    and subscription_id=p_subscription_id;

  if p_success then
    update public.web_push_subscriptions_v1
    set last_success_at=now(),
        failure_count=0,
        last_error_code=null,
        updated_at=now()
    where id=p_subscription_id;
  else
    update public.web_push_subscriptions_v1
    set failure_count=failure_count+1,
        last_error_code=left(nullif(btrim(coalesce(p_error_code,'')),''),120),
        disabled_at=case when p_disable_subscription then coalesce(disabled_at,now()) else disabled_at end,
        updated_at=now()
    where id=p_subscription_id;
  end if;
end;
$web_push_finish_delivery$;

revoke all on function public.web_push_finish_delivery_v1(uuid,uuid,boolean,text,boolean)
  from public,anon,authenticated;
grant execute on function public.web_push_finish_delivery_v1(uuid,uuid,boolean,text,boolean)
  to service_role;

create or replace function private.notification_web_push_dispatch_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $notification_web_push_dispatch$
declare
  v_secret text;
  v_url text:='https://qsxtmmkftsohkqqmytbb.supabase.co/functions/v1/web-push';
  v_request_id bigint;
begin
  if new.channel_in_app is distinct from true
    or new.event_type not in (
      'workflow_task_created',
      'workflow_completed',
      'workflow_rejected',
      'workflow_schedule_blocked'
    ) then
    return new;
  end if;

  if not exists(select 1 from pg_extension where extname='pg_net')
    or to_regclass('vault.decrypted_secrets') is null then
    return new;
  end if;

  execute
    'select decrypted_secret from vault.decrypted_secrets where name=$1 limit 1'
    into v_secret
    using 'gestionpisos_web_push_dispatch_secret_v1';

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
        'X-Allaiso-Push-Secret',v_secret
      ),
      5000;

  return new;
exception when others then
  -- Push delivery is secondary. Never roll back the canonical notification.
  return new;
end;
$notification_web_push_dispatch$;

revoke all on function private.notification_web_push_dispatch_v1()
  from public,anon,authenticated;

drop trigger if exists notification_web_push_dispatch_v1
  on public.notifications_v2;

create trigger notification_web_push_dispatch_v1
after insert on public.notifications_v2
for each row
execute function private.notification_web_push_dispatch_v1();

comment on table public.web_push_subscriptions_v1 is
  'Web Push device subscriptions. Client access only through authenticated RPCs.';
comment on table public.web_push_deliveries_v1 is
  'Idempotent Web Push delivery attempts per notification and device subscription.';
comment on function private.notification_web_push_dispatch_v1() is
  'Asynchronously dispatches eligible canonical notifications to the web-push Edge Function using pg_net and a Vault-backed internal secret.';
