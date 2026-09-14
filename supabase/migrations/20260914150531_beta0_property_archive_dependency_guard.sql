create or replace function private.guard_property_archive_dependencies()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status is distinct from new.status and new.status = 'archived' then
    if exists (
      select 1
      from public.rooms_v2 r
      where r.property_id = old.id
        and r.status <> 'archived'
    ) then
      raise exception 'property_has_active_rooms';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_property_archive_dependencies() from public, anon, authenticated;

drop trigger if exists trg_guard_property_archive_dependencies on public.properties_v2;
create trigger trg_guard_property_archive_dependencies
before update on public.properties_v2
for each row execute function private.guard_property_archive_dependencies();
