create or replace function public.sync_tenant_status_from_occupancy_v2()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.tenant_id is not null and new.status in ('active','blocked') then
    update public.tenants_v2
       set status = new.status,
           updated_at = now()
     where id = new.tenant_id
       and status is distinct from new.status;
  end if;
  return new;
end;
$$;
drop trigger if exists occupancies_v2_sync_tenant_status on public.occupancies_v2;
create trigger occupancies_v2_sync_tenant_status
after insert or update of status on public.occupancies_v2
for each row execute function public.sync_tenant_status_from_occupancy_v2();

update public.tenants_v2 t
set status=o.status, updated_at=now()
from public.occupancies_v2 o
where o.tenant_id=t.id
  and o.status in ('active','blocked')
  and t.status is distinct from o.status;
