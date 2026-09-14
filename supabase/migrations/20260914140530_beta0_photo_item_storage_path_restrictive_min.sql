create policy photo_items_storage_path_restrictive
on public.photo_verification_items_v2
as restrictive
for insert to authenticated
with check (
  storage_path = (
    (select organization_id::text from public.photo_verification_runs_v2 where id = run_id)
    || '/' || run_id::text || '/' || id::text || '.jpg'
  )
);
