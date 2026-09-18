-- Remove two verified orphan tenant identities created by failed manual tests.
-- Every DELETE is guarded by the exact id and by absence of occupancies/documents.
delete from public.tenants_v2 t
where t.id in (
  'bfc09c6c-4712-470f-9249-3da865cf6b04',
  '53d2364d-6ca2-4b24-abf2-7b3d6882b4e1'
)
and not exists (select 1 from public.occupancies_v2 o where o.tenant_id=t.id)
and not exists (select 1 from public.tenant_documents_v2 d where d.tenant_id=t.id);
