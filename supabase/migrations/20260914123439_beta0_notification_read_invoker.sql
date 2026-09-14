drop policy if exists notifications_mark_read_update on public.notifications_v2;

create policy notifications_mark_read_update
on public.notifications_v2
for update to authenticated
using (
  recipient_user_id = (select auth.uid())
  and status in ('pending','sent','read')
)
with check (
  recipient_user_id = (select auth.uid())
  and status = 'read'
);

revoke update on table public.notifications_v2 from authenticated;
grant update(status, read_at) on table public.notifications_v2 to authenticated;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security invoker
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
