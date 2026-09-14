alter table public.properties_v2
  add constraint properties_v2_archive_state_check
  check (
    (status = 'archived' and archived_at is not null)
    or (status <> 'archived' and archived_at is null)
  ) not valid;

alter table public.properties_v2
  validate constraint properties_v2_archive_state_check;

alter table public.rooms_v2
  add constraint rooms_v2_archive_state_check
  check (
    (status = 'archived' and archived_at is not null)
    or (status <> 'archived' and archived_at is null)
  ) not valid;

alter table public.rooms_v2
  validate constraint rooms_v2_archive_state_check;

create or replace function private.audit_property_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  audit_action text;
begin
  audit_action := case
    when tg_op = 'INSERT' then 'property_created'
    when old.status is distinct from new.status and new.status = 'archived' then 'property_archived'
    when old.status is distinct from new.status and old.status = 'archived' then 'property_reactivated'
    else 'property_updated'
  end;

  insert into public.audit_log_v2 (
    organization_id, actor_user_id, action, entity_type, entity_id, result, details
  )
  values (
    new.organization_id,
    auth.uid(),
    audit_action,
    'property',
    new.id::text,
    'success',
    jsonb_build_object(
      'operation', tg_op,
      'previous_status', case when tg_op = 'UPDATE' then old.status::text end,
      'new_status', new.status::text,
      'owner_changed', case when tg_op = 'UPDATE' then old.owner_id is distinct from new.owner_id else false end,
      'name_changed', case when tg_op = 'UPDATE' then old.name is distinct from new.name else false end,
      'address_changed', case when tg_op = 'UPDATE' then old.address_line is distinct from new.address_line else false end
    )
  );

  return new;
end;
$$;

revoke all on function private.audit_property_change() from public, anon, authenticated;

drop trigger if exists trg_audit_property_change on public.properties_v2;
create trigger trg_audit_property_change
after insert or update on public.properties_v2
for each row execute function private.audit_property_change();

create or replace function private.audit_room_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  audit_action text;
  org_id uuid;
begin
  select p.organization_id
  into org_id
  from public.properties_v2 p
  where p.id = new.property_id;

  audit_action := case
    when tg_op = 'INSERT' then 'room_created'
    when old.status is distinct from new.status and new.status = 'archived' then 'room_archived'
    when old.status is distinct from new.status and old.status = 'archived' then 'room_reactivated'
    else 'room_updated'
  end;

  insert into public.audit_log_v2 (
    organization_id, actor_user_id, action, entity_type, entity_id, result, details
  )
  values (
    org_id,
    auth.uid(),
    audit_action,
    'room',
    new.id::text,
    'success',
    jsonb_build_object(
      'operation', tg_op,
      'previous_status', case when tg_op = 'UPDATE' then old.status::text end,
      'new_status', new.status::text,
      'property_changed', case when tg_op = 'UPDATE' then old.property_id is distinct from new.property_id else false end,
      'label_changed', case when tg_op = 'UPDATE' then old.label is distinct from new.label else false end,
      'description_changed', case when tg_op = 'UPDATE' then old.description is distinct from new.description else false end
    )
  );

  return new;
end;
$$;

revoke all on function private.audit_room_change() from public, anon, authenticated;

drop trigger if exists trg_audit_room_change on public.rooms_v2;
create trigger trg_audit_room_change
after insert or update on public.rooms_v2
for each row execute function private.audit_room_change();
