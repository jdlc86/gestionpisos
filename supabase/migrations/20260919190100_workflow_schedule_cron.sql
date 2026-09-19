-- GestionPisos · scheduler de Flujos de Trabajo
-- Separado del núcleo para que las regresiones PostgreSQL no dependan de pg_cron.

create extension if not exists pg_cron;

do $workflow_schedule_cron$
declare
  v_job_id bigint;
begin
  select jobid
  into v_job_id
  from cron.job
  where jobname='gestionpisos-workflow-schedules'
  limit 1;

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'gestionpisos-workflow-schedules',
    '* * * * *',
    'select private.process_due_workflow_schedules_v1(now());'
  );
end;
$workflow_schedule_cron$;
