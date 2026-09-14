drop policy if exists photo_runs_actor_insert on public.photo_verification_runs_v2;

create policy photo_runs_actor_insert
on public.photo_verification_runs_v2
for insert to authenticated
with check (
  photo_verification_runs_v2.actor_user_id = (select auth.uid())
  and photo_verification_runs_v2.status = 'capturing'
  and photo_verification_runs_v2.submitted_at is null
  and photo_verification_runs_v2.reviewed_at is null
  and photo_verification_runs_v2.reviewed_by is null
  and photo_verification_runs_v2.rejection_reason is null
  and exists (
    select 1
    from public.properties_v2 p
    where p.id = photo_verification_runs_v2.property_id
      and p.organization_id = photo_verification_runs_v2.organization_id
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
    photo_verification_runs_v2.room_id is null
    or exists (
      select 1
      from public.rooms_v2 rm
      where rm.id = photo_verification_runs_v2.room_id
        and rm.property_id = photo_verification_runs_v2.property_id
    )
  )
  and (
    (
      photo_verification_runs_v2.source_type = 'manual'
      and photo_verification_runs_v2.source_id is null
    )
    or (
      photo_verification_runs_v2.source_type = 'cleaning_task'
      and photo_verification_runs_v2.source_id is not null
      and exists (
        select 1
        from public.cleaning_tasks_v2 t
        where t.id = photo_verification_runs_v2.source_id
          and t.property_id = photo_verification_runs_v2.property_id
          and t.organization_id = photo_verification_runs_v2.organization_id
          and t.assigned_user_id = (select auth.uid())
      )
    )
    or (
      photo_verification_runs_v2.source_type = 'random_request'
      and photo_verification_runs_v2.source_id is not null
      and exists (
        select 1
        from public.random_photo_requests_v2 rr
        where rr.id = photo_verification_runs_v2.source_id
          and rr.property_id = photo_verification_runs_v2.property_id
          and rr.organization_id = photo_verification_runs_v2.organization_id
          and rr.assigned_user_id = (select auth.uid())
          and rr.status in ('pending','opened')
      )
    )
  )
);
