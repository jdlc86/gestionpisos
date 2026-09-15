-- Stable, optional tenant identity for tenant-attributable cleaning tasks.
-- Tasks that belong only to a property/room keep tenant_id NULL.
alter table public.cleaning_tasks_v2
  add column if not exists tenant_id uuid null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'cleaning_tasks_v2_tenant_id_fkey'
      and conrelid = 'public.cleaning_tasks_v2'::regclass
  ) then
    alter table public.cleaning_tasks_v2
      add constraint cleaning_tasks_v2_tenant_id_fkey
      foreign key (tenant_id) references public.tenants_v2(id)
      on update restrict on delete restrict;
  end if;
end $$;

create index if not exists cleaning_tasks_v2_tenant_id_idx
  on public.cleaning_tasks_v2 (tenant_id)
  where tenant_id is not null;

comment on column public.cleaning_tasks_v2.tenant_id is
  'Optional stable tenant identity associated with this task. Null means the task is not attributable to one tenant.';
