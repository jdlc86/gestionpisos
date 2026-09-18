
drop policy if exists photo_verification_storage_read on storage.objects;
drop policy if exists photo_verification_storage_insert on storage.objects;
drop policy if exists photo_verification_storage_update on storage.objects;

create policy photo_verification_storage_read
on storage.objects
for select to authenticated
using (
  bucket_id = 'photo-verification'
  and (
    owner_id = (select auth.uid()::text)
    or ((select auth.jwt())->'app_metadata'->>'role')='root'
    or (
      ((select auth.jwt())->'app_metadata'->>'role')='admin'
      and (storage.foldername(name))[1] = ((select auth.jwt())->'app_metadata'->>'organization_id')
    )
  )
);

create policy photo_verification_storage_insert
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'photo-verification'
  and owner_id = (select auth.uid()::text)
  and (
    ((select auth.jwt())->'app_metadata'->>'role')='root'
    or (storage.foldername(name))[1] = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);

create policy photo_verification_storage_update
on storage.objects
for update to authenticated
using (
  bucket_id = 'photo-verification'
  and owner_id = (select auth.uid()::text)
)
with check (
  bucket_id = 'photo-verification'
  and owner_id = (select auth.uid()::text)
  and (
    ((select auth.jwt())->'app_metadata'->>'role')='root'
    or (storage.foldername(name))[1] = ((select auth.jwt())->'app_metadata'->>'organization_id')
  )
);
