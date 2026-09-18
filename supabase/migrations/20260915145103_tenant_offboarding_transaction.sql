create or replace function public.offboard_tenant_occupancy_v2(p_occupancy_id uuid, p_ends_on date)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_status public.record_status;
begin
  if p_ends_on is null or p_ends_on < current_date then
    raise exception 'offboarding_end_invalid' using errcode='22023';
  end if;

  select tenant_id, status into v_tenant_id, v_status
  from public.occupancies_v2
  where id=p_occupancy_id
  for update;

  if v_tenant_id is null then
    raise exception 'occupancy_not_found' using errcode='P0002';
  end if;
  if v_status not in ('active','blocked') then
    raise exception 'offboarding_invalid_state' using errcode='22023';
  end if;

  update public.occupancies_v2
     set status='archived',
         ends_on=p_ends_on,
         starts_on=case when v_status='blocked' then null else starts_on end
   where id=p_occupancy_id;

  update public.tenants_v2
     set status='archived',
         archived_at=coalesce(archived_at,now()),
         deletion_requested_at=coalesce(deletion_requested_at,now()),
         deletion_requested_by=coalesce(deletion_requested_by,auth.uid()),
         updated_at=now()
   where id=v_tenant_id;
end;
$$;
grant execute on function public.offboard_tenant_occupancy_v2(uuid,date) to authenticated;
