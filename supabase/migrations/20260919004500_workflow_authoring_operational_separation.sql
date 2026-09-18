-- GestionPisos · separación autoría/operación de Flujos
-- Borradores iniciales siguen en workflow_definitions_v2(status='draft').
-- Las futuras versiones de una definición publicada se editan aparte para que
-- la versión operativa y sus aplicaciones permanezcan inmutables.

create table if not exists public.workflow_definition_revision_drafts_v2 (
  definition_id uuid primary key
    references public.workflow_definitions_v2(id) on delete restrict,
  organization_id uuid not null
    references public.organizations(id) on delete restrict,
  base_version_id uuid not null
    references public.workflow_definition_versions_v2(id) on delete restrict,
  base_version integer not null check (base_version > 0),
  draft_spec jsonb not null check (jsonb_typeof(draft_spec)='object'),
  revision bigint not null default 1 check (revision > 0),
  authoring_complete boolean not null default false,
  created_by uuid not null,
  updated_by uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists workflow_definition_revision_drafts_v2_org_idx
  on public.workflow_definition_revision_drafts_v2(organization_id,updated_at desc);

alter table public.workflow_definition_revision_drafts_v2 enable row level security;

revoke all on public.workflow_definition_revision_drafts_v2 from anon;
revoke insert,update,delete,truncate,references,trigger
  on public.workflow_definition_revision_drafts_v2 from authenticated;
grant select on public.workflow_definition_revision_drafts_v2 to authenticated;

drop policy if exists workflow_definition_revision_drafts_v2_read
  on public.workflow_definition_revision_drafts_v2;
create policy workflow_definition_revision_drafts_v2_read
on public.workflow_definition_revision_drafts_v2
for select
to authenticated
using (public.workflow_can_manage_v1(organization_id));

create or replace function private.workflow_sanitize_authoring_spec_v2(
  p_spec jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $sanitize$
declare
  v_name text;
  v_flow_type text;
  v_description text;
  v_scope_type text;
  v_trigger_type text;
  v_recurrence text;
  v_scheduled_at text;
  v_custom_every text;
  v_custom_unit text;
  v_assignment_type text;
  v_close_type text;
  v_steps jsonb;
  v_notifications jsonb;
  v_authoring_version integer:=1;
begin
  if p_spec is null or jsonb_typeof(p_spec)<>'object' then
    raise exception 'workflow_spec_object_required' using errcode='22023';
  end if;

  v_name:=btrim(coalesce(p_spec->>'flowName',''));
  v_flow_type:=nullif(p_spec->>'flowType','');
  v_description:=nullif(btrim(coalesce(p_spec->>'flowDescription','')),'');
  v_scope_type:=nullif(p_spec->>'scopeType','');
  v_trigger_type:=nullif(p_spec->>'triggerType','');
  v_recurrence:=nullif(p_spec->>'recurrence','');
  v_scheduled_at:=nullif(btrim(coalesce(p_spec->>'scheduledAt','')),'');
  v_custom_every:=nullif(btrim(coalesce(p_spec->>'customEvery','')),'');
  v_custom_unit:=nullif(p_spec->>'customUnit','');
  v_assignment_type:=nullif(p_spec->>'assignmentType','');
  v_close_type:=nullif(p_spec->>'closeType','');
  v_steps:=coalesce(p_spec->'steps','{}'::jsonb);
  v_notifications:=coalesce(p_spec->'notifications','{}'::jsonb);

  if coalesce(p_spec->>'authoringVersion','') ~ '^[0-9]+$' then
    v_authoring_version:=greatest(1,(p_spec->>'authoringVersion')::integer);
  end if;

  if v_authoring_version<2 then
    v_flow_type:=null;
    v_scope_type:=null;
    v_trigger_type:=null;
    v_recurrence:=null;
    v_scheduled_at:=null;
    v_custom_every:=null;
    v_custom_unit:=null;
    v_assignment_type:=null;
    v_close_type:=null;
    v_steps:='{}'::jsonb;
    v_notifications:='{}'::jsonb;
  end if;

  if char_length(v_name)<3 or char_length(v_name)>80 then
    raise exception 'workflow_name_invalid' using errcode='22023';
  end if;
  if v_flow_type is not null
    and v_flow_type not in ('cleaning','inspection','maintenance','checkin','checkout','custom') then
    raise exception 'workflow_type_invalid' using errcode='22023';
  end if;
  if v_description is not null and char_length(v_description)>400 then
    raise exception 'workflow_description_too_long' using errcode='22023';
  end if;
  if v_scope_type is not null
    and v_scope_type not in ('organization','property','room','occupancy') then
    raise exception 'workflow_scope_invalid' using errcode='22023';
  end if;
  if v_trigger_type is not null
    and v_trigger_type not in ('manual','recurring','scheduled_once','event') then
    raise exception 'workflow_trigger_invalid' using errcode='22023';
  end if;
  if v_trigger_type='recurring'
    and v_recurrence is not null
    and v_recurrence not in ('weekly','biweekly','monthly','custom') then
    raise exception 'workflow_recurrence_invalid' using errcode='22023';
  end if;
  if v_scheduled_at is not null
    and v_scheduled_at !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$' then
    raise exception 'workflow_scheduled_at_invalid' using errcode='22023';
  end if;
  if v_custom_every is not null then
    if v_custom_every !~ '^[0-9]+$'
      or v_custom_every::integer<1
      or v_custom_every::integer>365 then
      raise exception 'workflow_custom_recurrence_invalid' using errcode='22023';
    end if;
  end if;
  if v_custom_unit is not null and v_custom_unit not in ('day','week','month') then
    raise exception 'workflow_custom_recurrence_invalid' using errcode='22023';
  end if;

  if v_trigger_type is distinct from 'recurring' then
    v_recurrence:=null;
    v_custom_every:=null;
    v_custom_unit:=null;
  elsif v_recurrence is distinct from 'custom' then
    v_custom_every:=null;
    v_custom_unit:=null;
  end if;

  if v_trigger_type is distinct from 'scheduled_once' then
    v_scheduled_at:=null;
  end if;

  if v_assignment_type is not null
    and v_assignment_type not in ('property_responsible','active_occupants_rotation','fixed_person','role','manual') then
    raise exception 'workflow_assignment_invalid' using errcode='22023';
  end if;
  if v_close_type is not null
    and v_close_type not in ('auto','human_review','domain_adapter') then
    raise exception 'workflow_close_invalid' using errcode='22023';
  end if;

  if jsonb_typeof(v_steps)<>'object'
    or jsonb_typeof(v_notifications)<>'object' then
    raise exception 'workflow_nested_spec_invalid' using errcode='22023';
  end if;

  if (v_steps ? 'accept' and jsonb_typeof(v_steps->'accept')<>'boolean')
    or (v_steps ? 'photo' and jsonb_typeof(v_steps->'photo')<>'boolean')
    or (v_steps ? 'checklist' and jsonb_typeof(v_steps->'checklist')<>'boolean')
    or (v_steps ? 'document' and jsonb_typeof(v_steps->'document')<>'boolean')
    or (v_notifications ? 'onCreate' and jsonb_typeof(v_notifications->'onCreate')<>'boolean')
    or (v_notifications ? 'onClose' and jsonb_typeof(v_notifications->'onClose')<>'boolean') then
    raise exception 'workflow_nested_spec_invalid' using errcode='22023';
  end if;

  return jsonb_build_object(
    'authoringVersion',v_authoring_version,
    'flowName',v_name,
    'flowType',coalesce(v_flow_type,''),
    'flowDescription',coalesce(v_description,''),
    'scopeType',coalesce(v_scope_type,''),
    'triggerType',coalesce(v_trigger_type,''),
    'recurrence',coalesce(v_recurrence,''),
    'scheduledAt',coalesce(v_scheduled_at,''),
    'customEvery',coalesce(v_custom_every,''),
    'customUnit',coalesce(v_custom_unit,''),
    'assignmentType',coalesce(v_assignment_type,''),
    'steps',jsonb_build_object(
      'accept',coalesce((v_steps->>'accept')::boolean,false),
      'photo',coalesce((v_steps->>'photo')::boolean,false),
      'checklist',coalesce((v_steps->>'checklist')::boolean,false),
      'document',coalesce((v_steps->>'document')::boolean,false)
    ),
    'closeType',coalesce(v_close_type,''),
    'notifications',jsonb_build_object(
      'onCreate',coalesce((v_notifications->>'onCreate')::boolean,false),
      'onClose',coalesce((v_notifications->>'onClose')::boolean,false)
    )
  );
end;
$sanitize$;

revoke all on function private.workflow_sanitize_authoring_spec_v2(jsonb)
  from public,anon,authenticated;

create or replace function public.start_workflow_definition_revision_v1(
  p_definition_id uuid
)
returns table(
  definition_id uuid,
  base_version integer,
  revision bigint,
  updated_at timestamptz,
  created_new boolean
)
language plpgsql
security definer
set search_path=public,pg_temp
as $start_revision$
declare
  v_actor uuid:=auth.uid();
  v_definition public.workflow_definitions_v2;
  v_version public.workflow_definition_versions_v2;
  v_existing public.workflow_definition_revision_drafts_v2;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select * into v_definition
  from public.workflow_definitions_v2
  where id=p_definition_id
  for update;

  if v_definition.id is null then
    raise exception 'workflow_definition_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_definition.organization_id) then
    raise exception 'workflow_author_role_required' using errcode='42501';
  end if;

  if v_definition.status<>'published' then
    raise exception 'workflow_revision_requires_published_definition' using errcode='55000';
  end if;

  select * into v_existing
  from public.workflow_definition_revision_drafts_v2
  where definition_id=p_definition_id;

  if v_existing.definition_id is not null then
    return query
    select v_existing.definition_id,v_existing.base_version,
           v_existing.revision,v_existing.updated_at,false;
    return;
  end if;

  select * into v_version
  from public.workflow_definition_versions_v2
  where definition_id=p_definition_id
    and organization_id=v_definition.organization_id
  order by version desc
  limit 1;

  if v_version.id is null then
    raise exception 'workflow_published_version_missing' using errcode='55000';
  end if;

  insert into public.workflow_definition_revision_drafts_v2(
    definition_id,organization_id,base_version_id,base_version,
    draft_spec,revision,authoring_complete,created_by,updated_by
  ) values (
    p_definition_id,v_definition.organization_id,v_version.id,v_version.version,
    v_version.spec-'definitionRevision',1,
    public.workflow_authoring_complete_v1(v_version.spec-'definitionRevision'),
    v_actor,v_actor
  )
  returning * into v_existing;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_definition.organization_id,v_actor,'workflow_revision_draft_started',
    'workflow_definition',p_definition_id::text,'success',
    jsonb_build_object(
      'base_version_id',v_version.id,
      'base_version',v_version.version,
      'draft_revision',v_existing.revision
    )
  );

  return query
  select v_existing.definition_id,v_existing.base_version,
         v_existing.revision,v_existing.updated_at,true;
end;
$start_revision$;

revoke all on function public.start_workflow_definition_revision_v1(uuid) from public,anon;
grant execute on function public.start_workflow_definition_revision_v1(uuid) to authenticated;

create or replace function public.save_workflow_definition_revision_draft_v1(
  p_definition_id uuid,
  p_spec jsonb,
  p_expected_revision bigint default null
)
returns table(
  definition_id uuid,
  base_version integer,
  revision bigint,
  authoring_complete boolean,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path=public,private,pg_temp
as $save_revision$
declare
  v_actor uuid:=auth.uid();
  v_definition public.workflow_definitions_v2;
  v_draft public.workflow_definition_revision_drafts_v2;
  v_spec jsonb;
  v_complete boolean;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select * into v_definition
  from public.workflow_definitions_v2
  where id=p_definition_id;

  if v_definition.id is null then
    raise exception 'workflow_definition_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_definition.organization_id) then
    raise exception 'workflow_author_role_required' using errcode='42501';
  end if;

  if v_definition.status<>'published' then
    raise exception 'workflow_revision_requires_published_definition' using errcode='55000';
  end if;

  select * into v_draft
  from public.workflow_definition_revision_drafts_v2
  where definition_id=p_definition_id
  for update;

  if v_draft.definition_id is null then
    raise exception 'workflow_revision_draft_not_found' using errcode='P0002';
  end if;

  if p_expected_revision is not null
    and p_expected_revision<>v_draft.revision then
    raise exception 'workflow_draft_conflict' using errcode='40001';
  end if;

  v_spec:=private.workflow_sanitize_authoring_spec_v2(p_spec);
  v_complete:=public.workflow_authoring_complete_v1(v_spec);

  if v_draft.draft_spec=v_spec
    and v_draft.authoring_complete=v_complete then
    return query
    select v_draft.definition_id,v_draft.base_version,v_draft.revision,
           v_draft.authoring_complete,v_draft.updated_at;
    return;
  end if;

  update public.workflow_definition_revision_drafts_v2 d
  set draft_spec=v_spec,
      authoring_complete=v_complete,
      revision=d.revision+1,
      updated_by=v_actor,
      updated_at=now()
  where d.definition_id=p_definition_id
  returning * into v_draft;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_definition.organization_id,v_actor,'workflow_revision_draft_updated',
    'workflow_definition',p_definition_id::text,'success',
    jsonb_build_object(
      'base_version',v_draft.base_version,
      'draft_revision',v_draft.revision,
      'authoring_complete',v_draft.authoring_complete
    )
  );

  return query
  select v_draft.definition_id,v_draft.base_version,v_draft.revision,
         v_draft.authoring_complete,v_draft.updated_at;
end;
$save_revision$;

revoke all on function public.save_workflow_definition_revision_draft_v1(uuid,jsonb,bigint)
  from public,anon;
grant execute on function public.save_workflow_definition_revision_draft_v1(uuid,jsonb,bigint)
  to authenticated;

create or replace function public.publish_workflow_definition_revision_v1(
  p_definition_id uuid,
  p_expected_revision bigint default null
)
returns table(
  definition_id uuid,
  version_id uuid,
  version integer,
  published_at timestamptz
)
language plpgsql
security definer
set search_path=public,pg_temp
as $publish_revision$
declare
  v_actor uuid:=auth.uid();
  v_definition public.workflow_definitions_v2;
  v_draft public.workflow_definition_revision_drafts_v2;
  v_latest_version integer;
  v_new_version integer;
  v_version_id uuid;
  v_published_at timestamptz;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
    raise exception 'aal2_required' using errcode='42501';
  end if;

  select * into v_definition
  from public.workflow_definitions_v2
  where id=p_definition_id
  for update;

  if v_definition.id is null then
    raise exception 'workflow_definition_not_found' using errcode='P0002';
  end if;

  if not public.workflow_can_manage_v1(v_definition.organization_id) then
    raise exception 'workflow_publish_not_authorized' using errcode='42501';
  end if;

  if v_definition.status<>'published' then
    raise exception 'workflow_revision_requires_published_definition' using errcode='55000';
  end if;

  select * into v_draft
  from public.workflow_definition_revision_drafts_v2
  where definition_id=p_definition_id
  for update;

  if v_draft.definition_id is null then
    raise exception 'workflow_revision_draft_not_found' using errcode='P0002';
  end if;

  if p_expected_revision is not null
    and p_expected_revision<>v_draft.revision then
    raise exception 'workflow_draft_conflict' using errcode='40001';
  end if;

  if not v_draft.authoring_complete then
    raise exception 'workflow_authoring_incomplete' using errcode='22023';
  end if;

  select max(v.version)
  into v_latest_version
  from public.workflow_definition_versions_v2 v
  where v.definition_id=p_definition_id;

  if v_latest_version is distinct from v_draft.base_version then
    raise exception 'workflow_revision_base_version_conflict' using errcode='40001';
  end if;

  v_new_version:=v_latest_version+1;

  insert into public.workflow_definition_versions_v2(
    definition_id,organization_id,version,spec,published_by
  ) values (
    p_definition_id,
    v_definition.organization_id,
    v_new_version,
    v_draft.draft_spec || jsonb_build_object(
      'definitionRevision',v_draft.revision,
      'baseVersion',v_draft.base_version
    ),
    v_actor
  )
  returning id,workflow_definition_versions_v2.published_at
  into v_version_id,v_published_at;

  update public.workflow_definitions_v2 wd
  set name=v_draft.draft_spec->>'flowName',
      flow_type=nullif(v_draft.draft_spec->>'flowType',''),
      description=nullif(v_draft.draft_spec->>'flowDescription',''),
      scope_type=nullif(v_draft.draft_spec->>'scopeType',''),
      trigger_type=nullif(v_draft.draft_spec->>'triggerType',''),
      assignment_type=nullif(v_draft.draft_spec->>'assignmentType',''),
      close_type=nullif(v_draft.draft_spec->>'closeType',''),
      draft_spec=v_draft.draft_spec,
      authoring_complete=true,
      revision=wd.revision+1,
      updated_by=v_actor,
      updated_at=now()
  where wd.id=p_definition_id;

  delete from public.workflow_definition_revision_drafts_v2
  where definition_id=p_definition_id;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_definition.organization_id,v_actor,'workflow_definition_revision_published',
    'workflow_definition',p_definition_id::text,'success',
    jsonb_build_object(
      'version_id',v_version_id,
      'version',v_new_version,
      'base_version',v_draft.base_version,
      'draft_revision',v_draft.revision
    )
  );

  return query
  select p_definition_id,v_version_id,v_new_version,v_published_at;
end;
$publish_revision$;

revoke all on function public.publish_workflow_definition_revision_v1(uuid,bigint)
  from public,anon;
grant execute on function public.publish_workflow_definition_revision_v1(uuid,bigint)
  to authenticated;

comment on table public.workflow_definition_revision_drafts_v2 is
  'Borrador de futura versión de una definición publicada. La versión operativa permanece inmutable hasta publicar.';
comment on function public.start_workflow_definition_revision_v1(uuid) is
  'Crea idempotentemente un borrador de nueva versión copiando la última versión publicada.';
comment on function public.publish_workflow_definition_revision_v1(uuid,bigint) is
  'Publica el borrador de revisión como siguiente versión inmutable sin modificar aplicaciones ligadas a versiones anteriores.';
