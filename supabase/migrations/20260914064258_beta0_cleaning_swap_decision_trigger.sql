create or replace function private.apply_cleaning_swap_decision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task public.cleaning_tasks_v2%rowtype;
begin
  if old.status <> 'pending' then
    raise exception 'only pending requests can be decided';
  end if;

  if new.cleaning_task_id is distinct from old.cleaning_task_id
     or new.requester_user_id is distinct from old.requester_user_id
     or new.target_user_id is distinct from old.target_user_id
     or new.requested_at is distinct from old.requested_at then
    raise exception 'swap request identity is immutable';
  end if;

  if new.status not in ('accepted','rejected','cancelled') then
    raise exception 'invalid swap decision';
  end if;

  if new.status in ('accepted','rejected') and auth.uid() is distinct from old.target_user_id then
    raise exception 'only target can accept or reject';
  end if;

  if new.status = 'cancelled' and auth.uid() is distinct from old.requester_user_id then
    raise exception 'only requester can cancel';
  end if;

  new.decided_at := coalesce(new.decided_at, now());
  new.decided_by := auth.uid();

  if new.status = 'accepted' then
    select *
    into v_task
    from public.cleaning_tasks_v2
    where id = old.cleaning_task_id
    for update;

    if not found then
      raise exception 'cleaning task not found';
    end if;

    if v_task.assigned_user_id is distinct from old.requester_user_id then
      raise exception 'task assignee changed';
    end if;

    if v_task.status not in ('pending','accepted') then
      raise exception 'task cannot be swapped in current state';
    end if;

    if not exists (
      select 1
      from public.occupancies_v2 o
      where o.property_id = v_task.property_id
        and o.user_id = old.target_user_id
        and o.status = 'active'
        and o.starts_on <= current_date
        and (o.ends_on is null or o.ends_on >= current_date)
    ) then
      raise exception 'target no longer occupies property';
    end if;

    update public.cleaning_tasks_v2
    set assigned_user_id = old.target_user_id,
        status = 'accepted',
        updated_at = now()
    where id = v_task.id;

    insert into public.cleaning_debts_v2(
      organization_id,
      property_id,
      debtor_user_id,
      creditor_user_id,
      source_task_id,
      swap_request_id,
      amount,
      status
    )
    values (
      v_task.organization_id,
      v_task.property_id,
      old.requester_user_id,
      old.target_user_id,
      v_task.id,
      old.id,
      1,
      'open'
    );
  end if;

  return new;
end;
$$;

revoke all on function private.apply_cleaning_swap_decision() from public, anon, authenticated;

drop trigger if exists trg_cleaning_swap_apply_decision on public.cleaning_swap_requests_v2;
create trigger trg_cleaning_swap_apply_decision
before update on public.cleaning_swap_requests_v2
for each row execute function private.apply_cleaning_swap_decision();
