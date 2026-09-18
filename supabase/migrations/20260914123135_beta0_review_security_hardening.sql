
-- 1) Photo verification runs: only safe initial state and authorized property/source.
drop policy if exists photo_runs_actor_insert on public.photo_verification_runs_v2;

create policy photo_runs_actor_insert
on public.photo_verification_runs_v2
for insert to authenticated
with check (
  actor_user_id = (select auth.uid())
  and status = 'capturing'
  and submitted_at is null
  and reviewed_at is null
  and reviewed_by is null
  and rejection_reason is null
  and exists (
    select 1
    from public.properties_v2 p
    where p.id = property_id
      and p.organization_id = organization_id
      and (
        ((select auth.jwt())->'app_metadata'->>'role') = 'root'
        or (
          ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
          and p.organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
        )
        or exists (
          select 1
          from public.occupancies_v2 o
          where o.property_id = p.id
            and o.user_id = (select auth.uid())
            and o.status = 'active'
            and o.starts_on <= current_date
            and (o.ends_on is null or o.ends_on >= current_date)
        )
        or exists (
          select 1
          from public.property_staff_access_v3 s
          where s.property_id = p.id
            and s.employee_user_id = (select auth.uid())
            and s.revoked_at is null
            and (s.valid_until is null or s.valid_until > now())
        )
      )
  )
  and (
    (source_type = 'manual' and source_id is null)
    or (
      source_type = 'cleaning_task'
      and source_id is not null
      and exists (
        select 1 from public.cleaning_tasks_v2 t
        where t.id = source_id
          and t.property_id = property_id
          and t.organization_id = organization_id
          and t.assigned_user_id = (select auth.uid())
      )
    )
    or (
      source_type = 'random_request'
      and source_id is not null
      and exists (
        select 1 from public.random_photo_requests_v2 rr
        where rr.id = source_id
          and rr.property_id = property_id
          and rr.organization_id = organization_id
          and rr.assigned_user_id = (select auth.uid())
      )
    )
  )
);

-- 2) Pattern write scope: organization and property must match.
drop policy if exists photo_patterns_root_admin_insert on public.photo_patterns_v2;
drop policy if exists photo_patterns_root_admin_update on public.photo_patterns_v2;

create policy photo_patterns_root_admin_insert
on public.photo_patterns_v2
for insert to authenticated
with check (
  exists (
    select 1 from public.properties_v2 p
    where p.id = property_id
      and p.organization_id = organization_id
      and (
        ((select auth.jwt())->'app_metadata'->>'role') = 'root'
        or (
          ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
          and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
        )
      )
  )
);

create policy photo_patterns_root_admin_update
on public.photo_patterns_v2
for update to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role') = 'root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
    and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
)
with check (
  exists (
    select 1 from public.properties_v2 p
    where p.id = property_id
      and p.organization_id = organization_id
      and (
        ((select auth.jwt())->'app_metadata'->>'role') = 'root'
        or (
          ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
          and organization_id::text = ((select auth.jwt())->'app_metadata'->>'organization_id')
        )
      )
  )
);

-- Pattern content is immutable after publication; only retirement metadata may change.
create or replace function private.enforce_photo_pattern_immutability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.organization_id is distinct from old.organization_id
     or new.property_id is distinct from old.property_id
     or new.name is distinct from old.name
     or new.target_type is distinct from old.target_type
     or new.target_key is distinct from old.target_key
     or new.reference_storage_path is distinct from old.reference_storage_path
     or new.silhouette_storage_path is distinct from old.silhouette_storage_path
     or new.contour_data is distinct from old.contour_data
     or new.version is distinct from old.version
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'published photo pattern content is immutable; create a new version';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_photo_pattern_immutability on public.photo_patterns_v2;
create trigger trg_photo_pattern_immutability
before update on public.photo_patterns_v2
for each row execute function private.enforce_photo_pattern_immutability();

-- 3) Photo items must match actor run and pattern scope.
drop policy if exists photo_items_actor_insert on public.photo_verification_items_v2;

create policy photo_items_actor_insert
on public.photo_verification_items_v2
for insert to authenticated
with check (
  exists (
    select 1
    from public.photo_verification_runs_v2 r
    join public.photo_patterns_v2 p on p.id = pattern_id
    where r.id = run_id
      and r.actor_user_id = (select auth.uid())
      and r.status = 'capturing'
      and p.property_id = r.property_id
      and p.organization_id = r.organization_id
      and p.active = true
  )
  and ai_score is null
  and ai_result is null
  and manual_result is null
  and reviewed_by is null
  and reviewed_at is null
);

-- 4) Privileged Storage reads require AAL2.
drop policy if exists photo_verification_storage_read on storage.objects;

create policy photo_verification_storage_read
on storage.objects
for select to authenticated
using (
  bucket_id = 'photo-verification'
  and (
    (
      ((select auth.jwt())->'app_metadata'->>'role') = 'root'
      and (select auth.jwt())->>'aal' = 'aal2'
    )
    or (
      (storage.foldername(name))[1] = ((select auth.jwt())->'app_metadata'->>'organization_id')
      and (
        owner_id = (select auth.uid()::text)
        or (
          ((select auth.jwt())->'app_metadata'->>'role') = 'admin'
          and (select auth.jwt())->>'aal' = 'aal2'
        )
      )
    )
  )
);

-- 5) Claims: no physical client delete.
drop policy if exists claims_admin_write on public.claims_v2;

create policy claims_admin_insert
on public.claims_v2
for insert to authenticated
with check (
  ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy claims_admin_update
on public.claims_v2
for update to authenticated
using (
  ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
)
with check (
  ((select auth.jwt())->'app_metadata'->>'role')='root'
  or (
    ((select auth.jwt())->'app_metadata'->>'role')='admin'
    and organization_id::text=((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

revoke delete on table public.claims_v2 from anon, authenticated;

-- 6) Mark notification read through a narrow SECURITY DEFINER RPC.
create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  update public.notifications_v2
  set status = 'read',
      read_at = coalesce(read_at, now())
  where id = p_notification_id
    and recipient_user_id = auth.uid()
    and status in ('pending','sent','read');

  if not found then
    raise exception 'notification not found or not allowed';
  end if;
end;
$$;

revoke all on function public.mark_notification_read(uuid) from public, anon;
grant execute on function public.mark_notification_read(uuid) to authenticated;
revoke update on table public.notifications_v2 from authenticated;

-- 7) Configuration writes are auditable.
create or replace function private.audit_photo_verification_config()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
begin
  insert into public.audit_log_v2(
    organization_id,
    actor_user_id,
    action,
    entity_type,
    entity_id,
    result,
    details
  )
  values (
    nullif(v_row->>'organization_id','')::uuid,
    auth.uid(),
    lower(tg_op) || '_photo_verification_config',
    tg_table_name,
    v_row->>'id',
    'success',
    jsonb_build_object('operation', tg_op)
  );
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_audit_verification_policies on public.verification_policies_v2;
create trigger trg_audit_verification_policies
after insert or update on public.verification_policies_v2
for each row execute function private.audit_photo_verification_config();

drop trigger if exists trg_audit_photo_patterns on public.photo_patterns_v2;
create trigger trg_audit_photo_patterns
after insert or update on public.photo_patterns_v2
for each row execute function private.audit_photo_verification_config();

drop trigger if exists trg_audit_random_photo_requests on public.random_photo_requests_v2;
create trigger trg_audit_random_photo_requests
after insert or update on public.random_photo_requests_v2
for each row execute function private.audit_photo_verification_config();
