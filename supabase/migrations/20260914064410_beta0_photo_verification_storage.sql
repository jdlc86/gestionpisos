
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values (
  'photo-verification',
  'photo-verification',
  false,
  10485760,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy photo_verification_storage_read
on storage.objects
for select to authenticated
using (
  bucket_id = 'photo-verification'
  and (
    owner_id = (select auth.uid()::text)
    or ((select auth.jwt())->'app_metadata'->>'role')='root'
    or ((select auth.jwt())->'app_metadata'->>'role')='admin'
  )
);

create policy photo_verification_storage_insert
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'photo-verification'
  and owner_id = (select auth.uid()::text)
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
);
