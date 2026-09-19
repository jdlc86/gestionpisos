-- GestionPisos · Flujos de Trabajo · descarte seguro de borradores
-- Permite eliminar únicamente borradores no publicados y borradores de nueva versión.
-- Las versiones publicadas, aplicaciones, ejecuciones y su historial nunca se eliminan aquí.

create or replace function public.discard_workflow_definition_draft_v1(
  p_definition_id uuid,
  p_expected_revision bigint default null
)
returns table(
  definition_id uuid,
  discarded_at timestamptz
)
language plpgsql
security definer
set search_path=public,pg_temp
as $workflow_discard_initial$
declare
  v_actor uuid:=auth.uid();
  v_definition public.workflow_definitions_v2;
  v_discarded_at timestamptz:=now();
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select * into v_definition
  from public.workflow_definitions_v2 wd
  where wd.id=p_definition_id
  for update;

  if v_definition.id is null then
    raise exception 'workflow_definition_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_definition.organization_id) then
    raise exception 'workflow_draft_discard_forbidden' using errcode='42501';
  end if;

  if v_definition.status<>'draft' then
    raise exception 'workflow_draft_discard_requires_unpublished' using errcode='55000';
  end if;

  if p_expected_revision is not null
    and p_expected_revision<>v_definition.revision then
    raise exception 'workflow_draft_conflict' using errcode='40001';
  end if;

  if exists(
      select 1 from public.workflow_definition_versions_v2 v
      where v.definition_id=v_definition.id
    )
    or exists(
      select 1 from public.workflow_definition_revision_drafts_v2 rd
      where rd.definition_id=v_definition.id
    )
    or exists(
      select 1 from public.workflow_applications_v2 a
      where a.definition_id=v_definition.id
    ) then
    raise exception 'workflow_draft_has_dependencies' using errcode='55000';
  end if;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_definition.organization_id,
    v_actor,
    'workflow_definition_draft_discarded',
    'workflow_definition',
    v_definition.id::text,
    'success',
    jsonb_build_object(
      'revision',v_definition.revision,
      'name',v_definition.name,
      'kind','initial'
    )
  );

  delete from public.workflow_definitions_v2
  where id=v_definition.id;

  return query select v_definition.id,v_discarded_at;
end;
$workflow_discard_initial$;

revoke all on function public.discard_workflow_definition_draft_v1(uuid,bigint)
  from public,anon;
grant execute on function public.discard_workflow_definition_draft_v1(uuid,bigint)
  to authenticated;

create or replace function public.discard_workflow_definition_revision_draft_v1(
  p_definition_id uuid,
  p_expected_revision bigint default null
)
returns table(
  definition_id uuid,
  base_version integer,
  discarded_at timestamptz
)
language plpgsql
security definer
set search_path=public,pg_temp
as $workflow_discard_revision$
declare
  v_actor uuid:=auth.uid();
  v_draft public.workflow_definition_revision_drafts_v2;
  v_definition public.workflow_definitions_v2;
  v_discarded_at timestamptz:=now();
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select * into v_draft
  from public.workflow_definition_revision_drafts_v2 rd
  where rd.definition_id=p_definition_id
    and rd.published_at is null
  for update;

  if v_draft.definition_id is null then
    raise exception 'workflow_revision_draft_not_found' using errcode='P0002';
  end if;

  select * into v_definition
  from public.workflow_definitions_v2 wd
  where wd.id=v_draft.definition_id
  for update;

  if v_definition.id is null then
    raise exception 'workflow_definition_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_draft.organization_id) then
    raise exception 'workflow_draft_discard_forbidden' using errcode='42501';
  end if;

  if v_definition.status<>'published' then
    raise exception 'workflow_revision_requires_published_definition' using errcode='55000';
  end if;

  if p_expected_revision is not null
    and p_expected_revision<>v_draft.revision then
    raise exception 'workflow_draft_conflict' using errcode='40001';
  end if;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_draft.organization_id,
    v_actor,
    'workflow_definition_revision_draft_discarded',
    'workflow_definition',
    v_draft.definition_id::text,
    'success',
    jsonb_build_object(
      'base_version',v_draft.base_version,
      'revision',v_draft.revision,
      'kind','revision'
    )
  );

  delete from public.workflow_definition_revision_drafts_v2 rd
  where rd.definition_id=v_draft.definition_id
    and rd.published_at is null;

  return query
  select v_draft.definition_id,v_draft.base_version,v_discarded_at;
end;
$workflow_discard_revision$;

revoke all on function public.discard_workflow_definition_revision_draft_v1(uuid,bigint)
  from public,anon;
grant execute on function public.discard_workflow_definition_revision_draft_v1(uuid,bigint)
  to authenticated;

comment on function public.discard_workflow_definition_draft_v1(uuid,bigint) is
  'Elimina únicamente una definición todavía no publicada, con control de revisión optimista y sin dependencias publicadas.';
comment on function public.discard_workflow_definition_revision_draft_v1(uuid,bigint) is
  'Descarta únicamente el borrador de una nueva versión y conserva intacta la definición publicada, sus versiones y aplicaciones.';
