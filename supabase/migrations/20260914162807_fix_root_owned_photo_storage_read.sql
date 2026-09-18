drop policy if exists photo_verification_storage_read on storage.objects;

create policy photo_verification_storage_read
on storage.objects
for select to authenticated
using (
  bucket_id = 'photo-verification'
  and (
    (
      ((select auth.jwt())->'app_metadata'->>'role') = 'root'
      and (
        owner_id = (select auth.uid()::text)
        or (select auth.jwt())->>'aal' = 'aal2'
      )
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
