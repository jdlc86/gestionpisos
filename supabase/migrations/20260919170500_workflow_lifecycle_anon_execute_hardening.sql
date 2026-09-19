-- GestionPisos · Flujos · cierre explícito de EXECUTE anon en RPC lifecycle
-- Supabase concede EXECUTE a anon/authenticated por default privileges en public.
-- La migración 20260919143208 revocó PUBLIC, pero no el grant explícito de anon.
-- Estas funciones ya validan auth.uid(), AAL2 y workflow_can_manage_v1; este
-- hardening elimina además la superficie RPC anónima.

revoke all on function public.publish_workflow_ready_v1(
  jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid
) from public,anon;

revoke all on function public.update_unexecuted_workflow_v1(
  uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid
) from public,anon;

revoke all on function public.publish_workflow_revision_ready_v1(
  uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid
) from public,anon;

revoke all on function public.delete_unexecuted_workflow_v1(uuid)
  from public,anon;

revoke all on function public.archive_workflow_definition_v1(uuid)
  from public,anon;

grant execute on function public.publish_workflow_ready_v1(
  jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid
) to authenticated;

grant execute on function public.update_unexecuted_workflow_v1(
  uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid
) to authenticated;

grant execute on function public.publish_workflow_revision_ready_v1(
  uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid
) to authenticated;

grant execute on function public.delete_unexecuted_workflow_v1(uuid)
  to authenticated;

grant execute on function public.archive_workflow_definition_v1(uuid)
  to authenticated;

comment on function public.publish_workflow_ready_v1(
  jsonb,uuid,uuid,uuid,uuid[],boolean,text,text,uuid
) is
  'Finaliza un flujo nuevo. RPC authenticated/AAL2; anon EXECUTE revocado explícitamente.';

comment on function public.update_unexecuted_workflow_v1(
  uuid,jsonb,uuid,uuid,uuid,uuid[],bigint,boolean,text,uuid
) is
  'Edita en sitio un flujo publicado sin historial. RPC authenticated/AAL2; anon EXECUTE revocado explícitamente.';

comment on function public.publish_workflow_revision_ready_v1(
  uuid,bigint,uuid,uuid,uuid,uuid[],boolean,text,uuid
) is
  'Publica una revisión de un flujo con historial. RPC authenticated/AAL2; anon EXECUTE revocado explícitamente.';

comment on function public.delete_unexecuted_workflow_v1(uuid) is
  'Elimina solo un flujo sin historial. RPC authenticated/AAL2; anon EXECUTE revocado explícitamente.';

comment on function public.archive_workflow_definition_v1(uuid) is
  'Archiva un flujo con historial. RPC authenticated/AAL2; anon EXECUTE revocado explícitamente.';
