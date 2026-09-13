-- B-01: owner writes are authorized in PostgreSQL and audited.
-- B-02: active room occupancies cannot overlap.

alter table public.owners enable row level security;

drop policy if exists owners_insert_root_admin on public.owners;
create policy owners_insert_root_admin
on public.owners
for insert
to authenticated
with check (
  ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'root'
  or (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
    and organization_id::text =
      ((select auth.jwt()) -> 'app_metadata' ->> 'organization_id')
  )
);

drop policy if exists owners_update_root_admin on public.owners;
create policy owners_update_root_admin
on public.owners
for update
to authenticated
using (
  ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'root'
  or (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
    and organization_id::text =
      ((select auth.jwt()) -> 'app_metadata' ->> 'organization_id')
  )
)
with check (
  ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'root'
  or (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin'
    and organization_id::text =
      ((select auth.jwt()) -> 'app_metadata' ->> 'organization_id')
  )
);

grant select, insert, update on table public.owners to authenticated;
revoke insert, update, delete on table public.owners from anon;
revoke delete on table public.owners from authenticated;

alter table public.owners
  add constraint owners_archive_state_check
  check (
    (status = 'archived' and archived_at is not null)
    or (status <> 'archived' and archived_at is null)
  )
  not valid;

alter table public.owners validate constraint owners_archive_state_check;

create or replace function private.audit_owner_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  audit_action text;
begin
  audit_action := case
    when tg_op = 'INSERT' then 'owner_created'
    when old.status is distinct from new.status
      and new.status = 'archived' then 'owner_archived'
    when old.status is distinct from new.status
      and old.status = 'archived' then 'owner_reactivated'
    else 'owner_updated'
  end;

  insert into public.audit_log_v2 (
    organization_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    details
  )
  values (
    new.organization_id,
    auth.uid(),
    audit_action,
    'owner',
    new.id::text,
    jsonb_build_object(
      'operation', tg_op,
      'previous_status', case when tg_op = 'UPDATE' then old.status::text end,
      'new_status', new.status::text,
      'organization_changed', case
        when tg_op = 'UPDATE' then old.organization_id is distinct from new.organization_id
        else false
      end,
      'name_changed', case
        when tg_op = 'UPDATE' then old.full_name is distinct from new.full_name
        else false
      end,
      'email_changed', case
        when tg_op = 'UPDATE' then old.email is distinct from new.email
        else false
      end,
      'phone_changed', case
        when tg_op = 'UPDATE' then old.phone is distinct from new.phone
        else false
      end
    )
  );

  return new;
end;
$$;

revoke all on function private.audit_owner_change() from public, anon, authenticated;

drop trigger if exists trg_audit_owner_change on public.owners;
create trigger trg_audit_owner_change
after insert or update on public.owners
for each row execute function private.audit_owner_change();

alter table public.occupancies_v2
  add constraint occupancies_v2_dates_check
  check (ends_on is null or ends_on >= starts_on)
  not valid;

alter table public.occupancies_v2
  validate constraint occupancies_v2_dates_check;

create extension if not exists btree_gist with schema extensions;

alter table public.occupancies_v2
  add constraint occupancies_v2_no_active_room_overlap
  exclude using gist (
    room_id with =,
    daterange(starts_on, coalesce(ends_on, 'infinity'::date), '[]') with &&
  )
  where (status = 'active');
