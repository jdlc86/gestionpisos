-- Automatic expiry of unattended cleaning audits.
-- Runs frequently so a configurable deadline is respected without requiring user action.

create extension if not exists pg_cron;

-- Remove a previous definition if this migration is replayed in a disposable environment.
select cron.unschedule(jobid)
from cron.job
where jobname='gestionpisos-cleaning-audit-expiry';

select cron.schedule(
  'gestionpisos-cleaning-audit-expiry',
  '*/5 * * * *',
  'select private.close_expired_cleaning_audits_v2(now());'
);

comment on function private.close_expired_cleaning_audits_v2(timestamptz) is
  'Idempotently expires pending photo decisions after their audit deadline and marks one report ready. Scheduled every 5 minutes by pg_cron.';
