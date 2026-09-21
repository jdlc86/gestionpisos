-- GestionPisos · email asíncrono · reintento seguro
--
-- La entrega original es idempotente por notification_id pero un fallo
-- transitorio quedaba bloqueado para siempre por la restricción UNIQUE.
-- Permitimos reintentos acotados y recuperación de claims "sending" huérfanos.
-- La Edge Function usa además Idempotency-Key del proveedor para evitar
-- duplicar el side-effect externo si el primer envío llegó a Resend pero la
-- confirmación local falló.

alter table public.notification_email_deliveries_v1
  add column if not exists attempt_count integer not null default 0;

alter table public.notification_email_deliveries_v1
  drop constraint if exists notification_email_deliveries_attempt_count_check;
alter table public.notification_email_deliveries_v1
  add constraint notification_email_deliveries_attempt_count_check
  check(attempt_count between 0 and 5);

create or replace function public.notification_email_claim_delivery_v1(
  p_notification_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=''
as $notification_email_claim$
declare
  v_claimed uuid;
begin
  insert into public.notification_email_deliveries_v1 as d(
    notification_id,status,attempted_at,finished_at,
    provider_message_id,error_code,attempt_count
  )
  select n.id,'sending',now(),null,null,null,1
  from public.notifications_v2 n
  where n.id=p_notification_id
    and n.channel_email=true
    and n.recipient_user_id is not null
  on conflict(notification_id) do update
  set status='sending',
      attempted_at=now(),
      finished_at=null,
      provider_message_id=null,
      error_code=null,
      attempt_count=d.attempt_count+1
  where d.attempt_count<5
    and (
      (
        d.status='failed'
        and d.attempted_at<=now()-interval '2 minutes'
      )
      or (
        d.status='sending'
        and d.attempted_at<=now()-interval '15 minutes'
      )
    )
  returning notification_id into v_claimed;

  return v_claimed is not null;
end;
$notification_email_claim$;

revoke all on function public.notification_email_claim_delivery_v1(uuid)
  from public,anon,authenticated;
grant execute on function public.notification_email_claim_delivery_v1(uuid)
  to service_role;

create or replace function private.notification_email_enqueue_http_v1(
  p_notification_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=''
as $notification_email_enqueue$
declare
  v_secret text;
  v_url text:='https://qsxtmmkftsohkqqmytbb.supabase.co/functions/v1/notification-email';
  v_request_id bigint;
begin
  if p_notification_id is null
    or not exists(
      select 1
      from public.notifications_v2 n
      where n.id=p_notification_id
        and n.channel_email=true
        and n.recipient_user_id is not null
    ) then
    return false;
  end if;

  if not exists(select 1 from pg_extension where extname='pg_net')
    or to_regclass('vault.decrypted_secrets') is null then
    return false;
  end if;

  execute
    'select decrypted_secret from vault.decrypted_secrets where name=$1 limit 1'
    into v_secret
    using 'gestionpisos_notification_email_dispatch_secret_v1';

  if nullif(v_secret,'') is null then
    return false;
  end if;

  execute
    'select net.http_post($1,$2,$3,$4,$5)'
    into v_request_id
    using
      v_url,
      jsonb_build_object('notification_id',p_notification_id),
      '{}'::jsonb,
      jsonb_build_object(
        'Content-Type','application/json',
        'X-Allaiso-Email-Secret',v_secret
      ),
      5000;

  return v_request_id is not null;
exception when others then
  return false;
end;
$notification_email_enqueue$;

revoke all on function private.notification_email_enqueue_http_v1(uuid)
  from public,anon,authenticated,service_role;

create or replace function private.notification_email_dispatch_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $notification_email_dispatch$
begin
  perform private.notification_email_enqueue_http_v1(new.id);
  return new;
end;
$notification_email_dispatch$;

revoke all on function private.notification_email_dispatch_v1()
  from public,anon,authenticated,service_role;

create or replace function private.retry_due_notification_emails_v1(
  p_limit integer default 50
)
returns integer
language plpgsql
security definer
set search_path=''
as $notification_email_retry$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),500);
  v_notification record;
  v_enqueued integer:=0;
begin
  for v_notification in
    select n.id
    from public.notifications_v2 n
    cross join private.notification_email_dispatch_state_v1 s
    left join public.notification_email_deliveries_v1 d
      on d.notification_id=n.id
    where s.singleton=true
      and n.channel_email=true
      and n.recipient_user_id is not null
      and (
        (
          d.notification_id is null
          and n.created_at>=s.activated_at
        )
        or (
          d.status='failed'
          and d.attempt_count<5
          and d.attempted_at<=now()-interval '2 minutes'
        )
        or (
          d.status='sending'
          and d.attempt_count<5
          and d.attempted_at<=now()-interval '15 minutes'
        )
      )
    order by n.created_at,n.id
    limit v_limit
  loop
    if private.notification_email_enqueue_http_v1(v_notification.id) then
      v_enqueued:=v_enqueued+1;
    end if;
  end loop;

  return v_enqueued;
end;
$notification_email_retry$;

revoke all on function private.retry_due_notification_emails_v1(integer)
  from public,anon,authenticated,service_role;

comment on column public.notification_email_deliveries_v1.attempt_count is
  'Número de claims de entrega aceptados. Máximo 5 por notificación.';
comment on function private.retry_due_notification_emails_v1(integer) is
  'Reencola emails sin recibo, fallidos o sending huérfanos; la Edge/provider idempotency evita duplicados.';
