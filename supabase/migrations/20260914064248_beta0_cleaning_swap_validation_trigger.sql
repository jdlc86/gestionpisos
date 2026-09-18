
create schema if not exists private;

create or replace function private.validate_cleaning_swap_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task public.cleaning_tasks_v2%rowtype;
begin
  if new.requester_user_id is distinct from auth.uid() then
    raise exception 'requester must be current user';
  end if;

  if new.requester_user_id = new.target_user_id then
    raise exception 'target must be another user';
  end if;

  if new.status <> 'pending' or new.decided_at is not null or new.decided_by is not null then
    raise exception 'new swap request must be pending';
  end if;

  select *
  into v_task
  from public.cleaning_tasks_v2
  where id = new.cleaning_task_id;

  if not found then
    raise exception 'cleaning task not found';
  end if;

  if v_task.assigned_user_id is distinct from new.requester_user_id then
    raise exception 'requester is not current task assignee';
  end if;

  if v_task.status not in ('pending','accepted') then
    raise exception 'task cannot be swapped in current state';
  end if;

  if not exists (
    select 1
    from public.occupancies_v2 o
    where o.property_id = v_task.property_id
      and o.user_id = new.requester_user_id
      and o.status = 'active'
      and o.starts_on <= current_date
      and (o.ends_on is null or o.ends_on >= current_date)
  ) then
    raise exception 'requester is not active occupant of property';
  end if;

  if not exists (
    select 1
    from public.occupancies_v2 o
    where o.property_id = v_task.property_id
      and o.user_id = new.target_user_id
      and o.status = 'active'
      and o.starts_on <= current_date
      and (o.ends_on is null or o.ends_on >= current_date)
  ) then
    raise exception 'target is not active occupant of property';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_cleaning_swap_insert() from public, anon, authenticated;

drop trigger if exists trg_cleaning_swap_validate_insert on public.cleaning_swap_requests_v2;
create trigger trg_cleaning_swap_validate_insert
before insert on public.cleaning_swap_requests_v2
for each row execute function private.validate_cleaning_swap_insert();
