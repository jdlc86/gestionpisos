-- Private, multi-document tenant dossier.
create table public.tenant_documents_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  tenant_id uuid not null references public.tenants_v2(id) on delete restrict,
  document_type text not null check (document_type in ('identification','contract','authorization','other')),
  display_name text not null check (length(btrim(display_name)) >= 2),
  storage_path text not null unique,
  original_filename text not null,
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  uploaded_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index tenant_documents_v2_tenant_idx on public.tenant_documents_v2(tenant_id,created_at desc);
alter table public.tenant_documents_v2 enable row level security;

create policy tenant_documents_v2_root_all on public.tenant_documents_v2 for all to authenticated
using ((auth.jwt()->'app_metadata'->>'role')='root')
with check ((auth.jwt()->'app_metadata'->>'role')='root');

create policy tenant_documents_v2_admin_org_all on public.tenant_documents_v2 for all to authenticated
using ((auth.jwt()->'app_metadata'->>'role')='admin' and organization_id=(auth.jwt()->'app_metadata'->>'organization_id')::uuid)
with check ((auth.jwt()->'app_metadata'->>'role')='admin' and organization_id=(auth.jwt()->'app_metadata'->>'organization_id')::uuid);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('tenant-documents-v2','tenant-documents-v2',false,10485760,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- Object path contract: organization_id/tenant_id/random-filename.
create policy tenant_documents_storage_root on storage.objects for all to authenticated
using (bucket_id='tenant-documents-v2' and (auth.jwt()->'app_metadata'->>'role')='root')
with check (bucket_id='tenant-documents-v2' and (auth.jwt()->'app_metadata'->>'role')='root');

create policy tenant_documents_storage_admin_org on storage.objects for all to authenticated
using (bucket_id='tenant-documents-v2' and (auth.jwt()->'app_metadata'->>'role')='admin' and (storage.foldername(name))[1]=(auth.jwt()->'app_metadata'->>'organization_id'))
with check (bucket_id='tenant-documents-v2' and (auth.jwt()->'app_metadata'->>'role')='admin' and (storage.foldername(name))[1]=(auth.jwt()->'app_metadata'->>'organization_id'));

comment on table public.tenant_documents_v2 is 'Private named attachments belonging to a tenant dossier.';
