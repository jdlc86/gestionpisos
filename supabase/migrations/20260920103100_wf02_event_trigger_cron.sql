-- GestionPisos · WF-02 · consumidor periódico del outbox de eventos
-- Separado del núcleo para que las regresiones PostgreSQL no dependan de pg_cron.

create extension if not exists pg_cron;

do $workflow_event_cron$
declare
  v_job_id bigint;
begin
  select jobid
  into v_job_id
  from cron.job
  where jobname='gestionpisos-workflow-events'
  limit 1;

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'gestionpisos-workflow-events',
    '* * * * *',
    'select private.process_pending_workflow_events_v1(50);'
  );
end;
$workflow_event_cron$;
