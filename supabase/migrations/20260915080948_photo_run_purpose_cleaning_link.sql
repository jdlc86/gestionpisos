-- Explicitly type the purpose of photo verification runs.
-- Existing rows retain generic/manual semantics and are never reinterpreted as cleaning.

alter table public.photo_verification_runs_v2
  add column if not exists purpose text not null default 'general',
  add column if not exists cleaning_task_id uuid references public.cleaning_tasks_v2(id);

alter table public.photo_verification_runs_v2
  drop constraint if exists photo_verification_runs_v2_purpose_check;
alter table public.photo_verification_runs_v2
  add constraint photo_verification_runs_v2_purpose_check
  check (purpose in ('general','cleaning','maintenance','state'));

alter table public.photo_verification_runs_v2
  drop constraint if exists photo_verification_runs_v2_cleaning_link_check;
alter table public.photo_verification_runs_v2
  add constraint photo_verification_runs_v2_cleaning_link_check
  check (
    (purpose='cleaning' and cleaning_task_id is not null)
    or
    (purpose<>'cleaning' and cleaning_task_id is null)
  );

create unique index if not exists photo_verification_runs_cleaning_task_uidx
  on public.photo_verification_runs_v2(cleaning_task_id)
  where cleaning_task_id is not null;

create or replace function private.enforce_photo_run_cleaning_scope_v2()
returns trigger
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_task public.cleaning_tasks_v2;
begin
  if new.purpose <> 'cleaning' then
    return new;
  end if;

  select * into v_task from public.cleaning_tasks_v2 where id=new.cleaning_task_id;
  if not found then raise exception 'cleaning_task_not_found' using errcode='23503'; end if;

  if v_task.organization_id <> new.organization_id or v_task.property_id <> new.property_id then
    raise exception 'cleaning_photo_scope_mismatch' using errcode='23514';
  end if;
  if v_task.assigned_user_id is not null and v_task.assigned_user_id <> new.actor_user_id then
    raise exception 'cleaning_actor_mismatch' using errcode='23514';
  end if;
  return new;
end;
$$;

drop trigger if exists photo_run_cleaning_scope_v2 on public.photo_verification_runs_v2;
create trigger photo_run_cleaning_scope_v2
before insert or update of purpose,cleaning_task_id,organization_id,property_id,actor_user_id
on public.photo_verification_runs_v2
for each row execute function private.enforce_photo_run_cleaning_scope_v2();

revoke all on function private.enforce_photo_run_cleaning_scope_v2() from public,anon,authenticated;

comment on column public.photo_verification_runs_v2.purpose is
  'Explicit business purpose. general preserves historical/manual runs; cleaning enables cleaning audit semantics; maintenance/state never inherit cleaning approve/reject.';
comment on column public.photo_verification_runs_v2.cleaning_task_id is
  'Required only when purpose=cleaning. Explicitly links the photo session to one cleaning task.';
