create or replace function private.guard_owner_archive_dependencies()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status is distinct from new.status and new.status = 'archived' then
    if exists (
      select 1
      from public.properties_v2 p
      where p.owner_id = old.id
        and p.status <> 'archived'
    ) then
      raise exception 'owner_has_active_properties';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_owner_archive_dependencies() from public, anon, authenticated;

drop trigger if exists trg_guard_owner_archive_dependencies on public.owners;
create trigger trg_guard_owner_archive_dependencies
before update on public.owners
for each row execute function private.guard_owner_archive_dependencies();
