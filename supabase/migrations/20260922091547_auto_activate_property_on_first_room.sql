-- Promote a property from onboarding to active as soon as it has at least
-- one active, non-archived room. The transition is one-way: removing or
-- archiving rooms never sends an already active property back to onboarding.

create or replace function private.promote_property_on_active_room_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'active' and new.archived_at is null then
    update public.properties_v2 p
    set status = 'active',
        updated_at = now()
    where p.id = new.property_id
      and p.status = 'onboarding'
      and p.archived_at is null;
  end if;

  return new;
end;
$$;

revoke all on function private.promote_property_on_active_room_v1() from public, anon, authenticated;

drop trigger if exists trg_promote_property_on_active_room_v1 on public.rooms_v2;
create trigger trg_promote_property_on_active_room_v1
after insert or update of property_id, status, archived_at on public.rooms_v2
for each row
execute function private.promote_property_on_active_room_v1();

-- Reconcile properties that already satisfy the new lifecycle rule.
update public.properties_v2 p
set status = 'active',
    updated_at = now()
where p.status = 'onboarding'
  and p.archived_at is null
  and exists (
    select 1
    from public.rooms_v2 r
    where r.property_id = p.id
      and r.status = 'active'
      and r.archived_at is null
  );
