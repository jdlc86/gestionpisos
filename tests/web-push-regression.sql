-- GestionPisos · regresión Web Push.
-- PostgreSQL desechable. Todo se revierte al finalizar.

begin;

insert into auth.users(id)
values ('33333333-3333-4333-8333-333333333333')
on conflict(id) do nothing;

-- Los RPC de dispositivo son solo para authenticated.
do $web_push_grants$
begin
  if has_function_privilege('anon','public.register_web_push_subscription_v1(text,text,text,text)','execute') then
    raise exception 'anon can register web push subscriptions';
  end if;
  if not has_function_privilege('authenticated','public.register_web_push_subscription_v1(text,text,text,text)','execute') then
    raise exception 'authenticated cannot register web push subscriptions';
  end if;
  if has_function_privilege('authenticated','public.web_push_server_config_v1()','execute') then
    raise exception 'authenticated can read web push server secrets';
  end if;
  if has_function_privilege('anon','public.web_push_server_config_v1()','execute') then
    raise exception 'anon can read web push server secrets';
  end if;
  if has_function_privilege('authenticated','public.web_push_store_vapid_v1(text,text)','execute') then
    raise exception 'authenticated can store VAPID secrets';
  end if;
end;
$web_push_grants$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','22222222-2222-4222-8222-222222222222',
    'role','authenticated',
    'aal','aal2'
  )::text,
  true
);

select public.register_web_push_subscription_v1(
  'https://push.example.invalid/subscription/one',
  'BExamplePublicDeviceKey1234567890',
  'ExampleAuthSecret123',
  'Regression Browser'
);

reset role;

do $registered_for_actor$
begin
  if (
    select count(*)
    from public.web_push_subscriptions_v1
    where user_id='22222222-2222-4222-8222-222222222222'::uuid
      and endpoint='https://push.example.invalid/subscription/one'
      and disabled_at is null
  )<>1 then
    raise exception 'push subscription was not bound to authenticated actor';
  end if;
end;
$registered_for_actor$;

-- Conocer solo el endpoint no permite secuestrar la suscripción de otro usuario.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','33333333-3333-4333-8333-333333333333',
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

do $endpoint_hijack_blocked$
begin
  perform public.register_web_push_subscription_v1(
    'https://push.example.invalid/subscription/one',
    'BReplacementPublicDeviceKey123456',
    'ReplacementAuthSecret123',
    'Regression Browser 2'
  );
  raise exception 'push endpoint hijack unexpectedly succeeded';
exception
  when sqlstate '42501' then
    if sqlerrm<>'web_push_subscription_conflict' then
      raise;
    end if;
end;
$endpoint_hijack_blocked$;

-- El cambio legítimo de cuenta en el mismo dispositivo conserva endpoint y claves,
-- por lo que puede reasignarse al usuario de la sesión actual.
select public.register_web_push_subscription_v1(
  'https://push.example.invalid/subscription/one',
  'BExamplePublicDeviceKey1234567890',
  'ExampleAuthSecret123',
  'Regression Browser 2'
);

reset role;

do $endpoint_rebound$
begin
  if (
    select count(*)
    from public.web_push_subscriptions_v1
    where user_id='33333333-3333-4333-8333-333333333333'::uuid
      and endpoint='https://push.example.invalid/subscription/one'
      and p256dh='BExamplePublicDeviceKey1234567890'
      and auth_secret='ExampleAuthSecret123'
      and disabled_at is null
  )<>1 then
    raise exception 'legitimate same-device push endpoint was not rebound to current user';
  end if;
end;
$endpoint_rebound$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','33333333-3333-4333-8333-333333333333',
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);

select public.unregister_web_push_subscription_v1(
  'https://push.example.invalid/subscription/one'
);

reset role;

do $subscription_disabled$
begin
  if not exists(
    select 1
    from public.web_push_subscriptions_v1
    where user_id='33333333-3333-4333-8333-333333333333'::uuid
      and endpoint='https://push.example.invalid/subscription/one'
      and disabled_at is not null
  ) then
    raise exception 'push subscription was not disabled';
  end if;
end;
$subscription_disabled$;

-- Volvemos a activarla para comprobar claim idempotente.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub','33333333-3333-4333-8333-333333333333',
    'role','authenticated',
    'aal','aal1'
  )::text,
  true
);
select public.register_web_push_subscription_v1(
  'https://push.example.invalid/subscription/one',
  'BExamplePublicDeviceKey1234567890',
  'ExampleAuthSecret123',
  'Regression Browser 2'
);
reset role;

select set_config(
  'gestionpisos.webpush.subscription',
  (
    select id::text
    from public.web_push_subscriptions_v1
    where endpoint='https://push.example.invalid/subscription/one'
  ),
  true
);

select set_config(
  'gestionpisos.webpush.notification',
  gen_random_uuid()::text,
  true
);

insert into public.notifications_v2(
  id,organization_id,recipient_user_id,event_type,title,body,
  status,channel_in_app,channel_email,source_kind,source_id,event_key
) values (
  current_setting('gestionpisos.webpush.notification')::uuid,
  '11111111-1111-4111-8111-111111111111'::uuid,
  '33333333-3333-4333-8333-333333333333'::uuid,
  'workflow_task_created','Nueva tarea · Push','Regresión push',
  'pending',true,false,'workflow_execution',
  '77777777-7777-4777-8777-777777777777'::uuid,'created'
);

-- El trigger de red es best-effort: incluso sin pg_net/Vault local, la notificación canónica permanece.
do $canonical_notification_survives$
begin
  if not exists(
    select 1 from public.notifications_v2
    where id=current_setting('gestionpisos.webpush.notification')::uuid
  ) then
    raise exception 'web push dispatch rolled back canonical notification';
  end if;
end;
$canonical_notification_survives$;

set local role service_role;

do $claim_delivery$
declare
  v_notification uuid:=current_setting('gestionpisos.webpush.notification')::uuid;
  v_subscription uuid:=current_setting('gestionpisos.webpush.subscription')::uuid;
begin
  if public.web_push_claim_delivery_v1(v_notification,v_subscription) is distinct from true then
    raise exception 'first push delivery claim failed';
  end if;
  if public.web_push_claim_delivery_v1(v_notification,v_subscription) is distinct from false then
    raise exception 'duplicate push delivery claim was not rejected';
  end if;

  perform public.web_push_finish_delivery_v1(
    v_notification,v_subscription,true,null,false
  );
end;
$claim_delivery$;

reset role;

do $delivery_finished$
begin
  if not exists(
    select 1
    from public.web_push_deliveries_v1
    where notification_id=current_setting('gestionpisos.webpush.notification')::uuid
      and subscription_id=current_setting('gestionpisos.webpush.subscription')::uuid
      and status='sent'
      and finished_at is not null
  ) then
    raise exception 'push delivery completion was not persisted';
  end if;

  if not exists(
    select 1
    from public.web_push_subscriptions_v1
    where id=current_setting('gestionpisos.webpush.subscription')::uuid
      and last_success_at is not null
      and failure_count=0
      and last_error_code is null
  ) then
    raise exception 'push subscription success state was not updated';
  end if;
end;
$delivery_finished$;

rollback;
