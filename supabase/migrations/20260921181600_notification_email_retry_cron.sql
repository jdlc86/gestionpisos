-- GestionPisos · email asíncrono · cron de reintentos
-- Separado del núcleo para que la regresión PostgreSQL desechable no dependa
-- de pg_cron. Producción Supabase aplica este job por la vía normal.

create extension if not exists pg_cron;

do $notification_email_retry_cron$
declare
  v_job_id bigint;
begin
  select jobid
  into v_job_id
  from cron.job
  where jobname='gestionpisos-notification-email-retry'
  limit 1;

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'gestionpisos-notification-email-retry',
    '*/5 * * * *',
    'select private.retry_due_notification_emails_v1(50);'
  );
end;
$notification_email_retry_cron$;
