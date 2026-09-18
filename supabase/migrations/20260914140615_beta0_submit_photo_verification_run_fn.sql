create or replace function public.submit_photo_verification_run(p_run_id uuid, p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_path text;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;

  select i.storage_path into v_path
  from public.photo_verification_runs_v2 r
  join public.photo_verification_items_v2 i on i.run_id = r.id
  where r.id = p_run_id
    and i.id = p_item_id
    and r.actor_user_id = v_user
    and r.status = 'capturing';

  if v_path is null then
    raise exception 'run/item not found or not allowed';
  end if;

  if not exists (
    select 1
    from storage.objects o
    where o.bucket_id = 'photo-verification'
      and o.name = v_path
      and o.owner_id = v_user::text
  ) then
    raise exception 'photo object missing';
  end if;

  update public.photo_verification_runs_v2
  set status = 'submitted', submitted_at = now()
  where id = p_run_id
    and actor_user_id = v_user
    and status = 'capturing';
end;
$$;
