drop policy if exists notifications_self_update on public.notifications_v2;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  update public.notifications_v2
  set status = 'read',
      read_at = coalesce(read_at, now())
  where id = p_notification_id
    and recipient_user_id = (select auth.uid())
    and status in ('pending','sent','read');

  if not found then
    raise exception 'notification not found or not allowed';
  end if;
end;
$$;

revoke all on function public.mark_notification_read(uuid) from public;
grant execute on function public.mark_notification_read(uuid) to authenticated;