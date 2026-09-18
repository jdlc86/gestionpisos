revoke execute on function public.save_workflow_definition_draft_v1(jsonb, uuid, bigint) from public;
revoke execute on function public.save_workflow_definition_draft_v1(jsonb, uuid, bigint) from anon;
grant execute on function public.save_workflow_definition_draft_v1(jsonb, uuid, bigint) to authenticated;

revoke execute on function public.workflow_can_read_definitions_v1(uuid) from public;
revoke execute on function public.workflow_can_read_definitions_v1(uuid) from anon;
grant execute on function public.workflow_can_read_definitions_v1(uuid) to authenticated;
