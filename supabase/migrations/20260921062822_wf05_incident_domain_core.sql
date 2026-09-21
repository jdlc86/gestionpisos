-- WF-05 · expediente de incidencia enlazable al motor transversal.
-- Este bloque no crea tareas: publica eventos en el outbox WF-02.

alter table public.incidents_v2
  add column incident_kind text not null default 'incident',
  add column opened_occupancy_id uuid
    references public.occupancies_v2(id) on delete restrict,
  add column open_request_key text;

alter table public.incidents_v2
  add constraint incidents_v2_incident_kind_check
  check (incident_kind in ('incident','maintenance'));

alter table public.incidents_v2
  add constraint incidents_v2_open_request_key_check
  check (
    open_request_key is null
    or (length(btrim(open_request_key)) between 1 and 200)
  );

alter table public.incidents_v2
  drop constraint incidents_v2_status_check;
alter table public.incidents_v2
  add constraint incidents_v2_status_check
  check (status in (
    'reported','triaged','assigned','in_progress','waiting_info',
    'resolved','closed','rejected','reopened'
  ));

alter table public.incident_updates_v2
  add column update_kind text not null default 'legacy',
  add column request_key text;

alter table public.incident_updates_v2
  add constraint incident_updates_v2_update_kind_check
  check (update_kind in (
    'legacy','request_info','information_response','resolution','rejection'
  ));

alter table public.incident_updates_v2
  add constraint incident_updates_v2_request_key_check
  check (
    request_key is null
    or (length(btrim(request_key)) between 1 and 200)
  );

alter table public.workflow_executions_v2
  add column incident_id uuid
    references public.incidents_v2(id) on delete restrict;

create unique index incidents_v2_actor_request_uq
  on public.incidents_v2(created_by,open_request_key)
  where open_request_key is not null;

create unique index incident_updates_v2_actor_request_uq
  on public.incident_updates_v2(incident_id,author_user_id,request_key)
  where request_key is not null;

create index workflow_executions_v2_incident_idx
  on public.workflow_executions_v2(incident_id,created_at desc)
  where incident_id is not null;

comment on column public.incidents_v2.incident_kind is
  'WF-05 classification. Legacy rows default to incident; maintenance remains a category, not a parallel engine.';
comment on column public.incidents_v2.opened_occupancy_id is
  'Active occupancy proven by a tenant at opening time; null for authorized staff reports.';
comment on column public.workflow_executions_v2.incident_id is
  'Exact WF-05 domain dossier linked to management or downstream inspection execution.';

-- Server-authoritative access helpers. They never trust app_metadata claims.
create function private.incident_internal_access_v1(
  p_organization_id uuid,
  p_property_id uuid,
  p_actor uuid,
  p_require_write boolean default false
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select p_actor is not null
    and exists(
      select 1
      from public.profiles pr
      where pr.user_id=p_actor
        and pr.status='active'
        and pr.archived_at is null
    )
    and (
      exists(
        select 1 from public.user_roles ur
        where ur.user_id=p_actor
          and ur.role='root'
          and ur.revoked_at is null
      )
      or exists(
        select 1 from public.user_roles ur
        where ur.user_id=p_actor
          and ur.organization_id=p_organization_id
          and ur.role='admin'
          and ur.revoked_at is null
      )
      or exists(
        select 1
        from public.user_roles ur
        join public.property_staff_access_v3 a
          on a.employee_user_id=ur.user_id
         and a.organization_id=ur.organization_id
         and a.property_id=p_property_id
        where ur.user_id=p_actor
          and ur.organization_id=p_organization_id
          and ur.role='employee'
          and ur.revoked_at is null
          and a.assignment_type in ('responsible','access')
          and a.revoked_at is null
          and a.valid_from<=now()
          and (a.valid_until is null or a.valid_until>now())
          and (not p_require_write or a.can_write=true)
      )
    );
$$;
revoke all on function private.incident_internal_access_v1(
  uuid,uuid,uuid,boolean
) from public,anon,authenticated,service_role;

create function private.incident_tenant_access_v1(
  p_incident_id uuid,
  p_actor uuid
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select p_actor is not null and exists(
    select 1
    from public.incidents_v2 i
    join public.occupancies_v2 o
      on o.organization_id=i.organization_id
     and o.property_id=i.property_id
     and (i.room_id is null or o.room_id=i.room_id)
     and (
       (i.opened_occupancy_id is not null and o.id=i.opened_occupancy_id)
       or (i.opened_occupancy_id is null and i.created_by=p_actor)
     )
    join public.tenants_v2 t
      on t.id=o.tenant_id
     and t.organization_id=o.organization_id
     and t.user_id=p_actor
     and t.status='active'
     and t.archived_at is null
    join public.user_roles ur
      on ur.user_id=p_actor
     and ur.organization_id=i.organization_id
     and ur.role='tenant'
     and ur.revoked_at is null
    where i.id=p_incident_id
      and o.user_id=p_actor
      and o.status='active'
      and o.starts_on is not null
      and o.starts_on<=current_date
      and (o.ends_on is null or o.ends_on>=current_date)
  );
$$;
revoke all on function private.incident_tenant_access_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

create function private.incident_owner_access_v1(
  p_incident_id uuid,
  p_actor uuid
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select p_actor is not null and exists(
    select 1
    from public.incidents_v2 i
    join public.properties_v2 p
      on p.id=i.property_id
     and p.organization_id=i.organization_id
    join public.owners o
      on o.id=p.owner_id
     and o.organization_id=i.organization_id
     and o.user_id=p_actor
     and o.status='active'
     and o.archived_at is null
    join public.user_roles ur
      on ur.user_id=p_actor
     and ur.organization_id=i.organization_id
     and ur.role='owner'
     and ur.revoked_at is null
    where i.id=p_incident_id
  );
$$;
revoke all on function private.incident_owner_access_v1(uuid,uuid)
  from public,anon,authenticated,service_role;

create function public.incident_can_read_v1(p_incident_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_incident public.incidents_v2;
begin
  if v_actor is null or p_incident_id is null then
    return false;
  end if;

  select * into v_incident
  from public.incidents_v2
  where id=p_incident_id;
  if v_incident.id is null then
    return false;
  end if;

  return private.incident_internal_access_v1(
      v_incident.organization_id,v_incident.property_id,v_actor,false
    )
    or private.incident_tenant_access_v1(v_incident.id,v_actor)
    or private.incident_owner_access_v1(v_incident.id,v_actor);
end;
$$;
revoke all on function public.incident_can_read_v1(uuid)
  from public,anon,service_role;
grant execute on function public.incident_can_read_v1(uuid)
  to authenticated;

create function public.incident_can_manage_v1(p_incident_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_incident public.incidents_v2;
begin
  if v_actor is null or p_incident_id is null then
    return false;
  end if;
  select * into v_incident
  from public.incidents_v2
  where id=p_incident_id;
  if v_incident.id is null then
    return false;
  end if;
  return private.incident_internal_access_v1(
    v_incident.organization_id,v_incident.property_id,v_actor,true
  );
end;
$$;
revoke all on function public.incident_can_manage_v1(uuid)
  from public,anon,service_role;
grant execute on function public.incident_can_manage_v1(uuid)
  to authenticated;

create function public.incident_can_read_detail_v1(
  p_incident_id uuid,
  p_visibility text
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_incident public.incidents_v2;
begin
  if v_actor is null or p_incident_id is null
    or p_visibility not in ('tenant','internal','owner') then
    return false;
  end if;
  select * into v_incident
  from public.incidents_v2
  where id=p_incident_id;
  if v_incident.id is null then
    return false;
  end if;

  if private.incident_internal_access_v1(
    v_incident.organization_id,v_incident.property_id,v_actor,false
  ) then
    return true;
  end if;
  if p_visibility='tenant' then
    return private.incident_tenant_access_v1(v_incident.id,v_actor);
  end if;
  if p_visibility='owner' then
    return private.incident_owner_access_v1(v_incident.id,v_actor);
  end if;
  return false;
end;
$$;
revoke all on function public.incident_can_read_detail_v1(uuid,text)
  from public,anon,service_role;
grant execute on function public.incident_can_read_detail_v1(uuid,text)
  to authenticated;

drop policy if exists incidents_root_admin_read on public.incidents_v2;
drop policy if exists incident_updates_root_admin_read on public.incident_updates_v2;
drop policy if exists incident_evidence_root_admin_read on public.incident_evidence_v2;

create policy incidents_v2_authorized_read
on public.incidents_v2 for select to authenticated
using (public.incident_can_read_v1(id));

create policy incident_updates_v2_authorized_read
on public.incident_updates_v2 for select to authenticated
using (public.incident_can_read_detail_v1(incident_id,visibility));

create policy incident_evidence_v2_authorized_read
on public.incident_evidence_v2 for select to authenticated
using (public.incident_can_read_detail_v1(incident_id,visibility));

revoke all on public.incidents_v2 from anon;
revoke all on public.incident_updates_v2 from anon;
revoke all on public.incident_evidence_v2 from anon;
revoke insert,update,delete,truncate,references,trigger
  on public.incidents_v2 from authenticated;
revoke insert,update,delete,truncate,references,trigger
  on public.incident_updates_v2 from authenticated;
revoke insert,update,delete,truncate,references,trigger
  on public.incident_evidence_v2 from authenticated;
grant select on public.incidents_v2 to authenticated;
grant select on public.incident_updates_v2 to authenticated;
grant select on public.incident_evidence_v2 to authenticated;

-- Extend the one shared outbox. Existing occupancy producers delegate to the
-- previous implementation unchanged.
alter table public.workflow_event_outbox_v2
  drop constraint workflow_event_outbox_v2_event_type_check;
alter table public.workflow_event_outbox_v2
  add constraint workflow_event_outbox_v2_event_type_check
  check (event_type in (
    'occupancy.created','occupancy.offboarded',
    'incident.created','incident.resolved'
  ));

alter table public.workflow_event_outbox_v2
  drop constraint workflow_event_outbox_v2_source_kind_check;
alter table public.workflow_event_outbox_v2
  add constraint workflow_event_outbox_v2_source_kind_check
  check (source_kind in ('occupancy','incident'));

alter function private.workflow_enqueue_event_v1(
  uuid,text,text,uuid,text,uuid,uuid,uuid,jsonb,uuid,timestamptz
) rename to workflow_enqueue_event_pre_wf05_v1;
revoke all on function private.workflow_enqueue_event_pre_wf05_v1(
  uuid,text,text,uuid,text,uuid,uuid,uuid,jsonb,uuid,timestamptz
) from public,anon,authenticated,service_role;

create function private.workflow_enqueue_event_v1(
  p_organization_id uuid,
  p_event_type text,
  p_source_kind text,
  p_source_id uuid,
  p_event_key text,
  p_property_id uuid,
  p_room_id uuid,
  p_occupancy_id uuid,
  p_payload jsonb default '{}'::jsonb,
  p_actor_user_id uuid default null,
  p_occurred_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_incident public.incidents_v2;
  v_event_id uuid;
  v_expected_key text;
  v_expected_status text;
begin
  if p_event_type not in ('incident.created','incident.resolved') then
    return private.workflow_enqueue_event_pre_wf05_v1(
      p_organization_id,p_event_type,p_source_kind,p_source_id,p_event_key,
      p_property_id,p_room_id,p_occupancy_id,p_payload,p_actor_user_id,p_occurred_at
    );
  end if;

  v_expected_key:=case p_event_type
    when 'incident.created' then 'created' else 'resolved' end;
  v_expected_status:=case p_event_type
    when 'incident.created' then 'reported' else 'resolved' end;

  if p_source_kind<>'incident'
    or p_source_id is null
    or p_event_key is distinct from v_expected_key
    or p_payload is null
    or jsonb_typeof(p_payload)<>'object' then
    raise exception 'workflow_incident_event_source_invalid' using errcode='22023';
  end if;

  select * into v_incident
  from public.incidents_v2
  where id=p_source_id;
  if v_incident.id is null
    or v_incident.organization_id is distinct from p_organization_id
    or v_incident.property_id is distinct from p_property_id
    or v_incident.room_id is distinct from p_room_id
    or v_incident.opened_occupancy_id is distinct from p_occupancy_id
    or v_incident.status is distinct from v_expected_status then
    raise exception 'workflow_incident_event_routing_invalid' using errcode='22023';
  end if;

  insert into public.workflow_event_outbox_v2(
    organization_id,event_type,source_kind,source_id,event_key,
    property_id,room_id,occupancy_id,payload,actor_user_id,occurred_at
  ) values (
    p_organization_id,p_event_type,p_source_kind,p_source_id,p_event_key,
    p_property_id,p_room_id,p_occupancy_id,p_payload,p_actor_user_id,
    coalesce(p_occurred_at,now())
  )
  on conflict(organization_id,event_type,source_kind,source_id,event_key)
  do nothing
  returning id into v_event_id;

  if v_event_id is null then
    select id into v_event_id
    from public.workflow_event_outbox_v2
    where organization_id=p_organization_id
      and event_type=p_event_type
      and source_kind=p_source_kind
      and source_id=p_source_id
      and event_key=p_event_key;
  end if;
  return v_event_id;
end;
$$;
revoke all on function private.workflow_enqueue_event_v1(
  uuid,text,text,uuid,text,uuid,uuid,uuid,jsonb,uuid,timestamptz
) from public,anon,authenticated,service_role;

create function public.open_workflow_incident_v1(
  p_property_id uuid,
  p_room_id uuid,
  p_incident_kind text,
  p_category text,
  p_description text,
  p_priority text,
  p_request_key text
)
returns table(
  incident_id uuid,
  incident_status text,
  event_id uuid,
  created_new boolean
)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_kind text:=nullif(btrim(p_incident_kind),'');
  v_category text:=nullif(btrim(p_category),'');
  v_description text:=nullif(btrim(p_description),'');
  v_property public.properties_v2;
  v_room public.rooms_v2;
  v_occupancy public.occupancies_v2;
  v_existing public.incidents_v2;
  v_incident public.incidents_v2;
  v_event_id uuid;
  v_internal boolean:=false;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'incident_request_key_invalid' using errcode='22023';
  end if;
  if v_kind not in ('incident','maintenance') or v_kind is null then
    raise exception 'incident_kind_invalid' using errcode='22023';
  end if;
  if v_category is null or length(v_category)>120 then
    raise exception 'incident_category_invalid' using errcode='22023';
  end if;
  if v_description is null or length(v_description)>5000 then
    raise exception 'incident_description_invalid' using errcode='22023';
  end if;
  if p_priority not in ('low','normal','high','urgent') or p_priority is null then
    raise exception 'incident_priority_invalid' using errcode='22023';
  end if;

  -- Serializa reintentos concurrentes antes de consultar la clave única.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_actor::text||':incident-open:'||v_key,0)
  );

  select * into v_property
  from public.properties_v2
  where id=p_property_id;
  if v_property.id is null
    or v_property.status='archived'
    or v_property.archived_at is not null then
    raise exception 'incident_destination_invalid' using errcode='22023';
  end if;

  if p_room_id is not null then
    select * into v_room
    from public.rooms_v2
    where id=p_room_id;
    if v_room.id is null
      or v_room.property_id<>v_property.id
      or v_room.status='archived'
      or v_room.archived_at is not null then
      raise exception 'incident_destination_invalid' using errcode='22023';
    end if;
  end if;

  v_internal:=private.incident_internal_access_v1(
    v_property.organization_id,v_property.id,v_actor,true
  );
  if not v_internal then
    select o.* into v_occupancy
    from public.occupancies_v2 o
    join public.tenants_v2 t
      on t.id=o.tenant_id
     and t.organization_id=o.organization_id
     and t.user_id=v_actor
     and t.status='active'
     and t.archived_at is null
    join public.user_roles ur
      on ur.user_id=v_actor
     and ur.organization_id=o.organization_id
     and ur.role='tenant'
     and ur.revoked_at is null
    where o.organization_id=v_property.organization_id
      and o.property_id=v_property.id
      and (p_room_id is null or o.room_id=p_room_id)
      and o.user_id=v_actor
      and o.status='active'
      and o.starts_on is not null
      and o.starts_on<=current_date
      and (o.ends_on is null or o.ends_on>=current_date)
    order by o.starts_on desc,o.id
    limit 1;
    if v_occupancy.id is null then
      raise exception 'incident_open_forbidden' using errcode='42501';
    end if;
  end if;

  select * into v_existing
  from public.incidents_v2
  where created_by=v_actor and open_request_key=v_key
  for update;
  if v_existing.id is not null then
    if v_existing.organization_id<>v_property.organization_id
      or v_existing.property_id<>v_property.id
      or v_existing.room_id is distinct from p_room_id
      or v_existing.incident_kind<>v_kind
      or v_existing.category<>v_category
      or v_existing.description<>v_description
      or v_existing.priority<>p_priority
      or v_existing.opened_occupancy_id is distinct from v_occupancy.id then
      raise exception 'incident_request_key_conflict' using errcode='55000';
    end if;
    select id into v_event_id
    from public.workflow_event_outbox_v2
    where organization_id=v_existing.organization_id
      and event_type='incident.created'
      and source_kind='incident'
      and source_id=v_existing.id
      and event_key='created';
    if v_event_id is null then
      raise exception 'incident_event_missing' using errcode='55000';
    end if;
    return query select v_existing.id,v_existing.status,v_event_id,false;
    return;
  end if;

  insert into public.incidents_v2(
    organization_id,property_id,room_id,created_by,category,description,
    priority,status,incident_kind,opened_occupancy_id,open_request_key
  ) values (
    v_property.organization_id,v_property.id,p_room_id,v_actor,v_category,
    v_description,p_priority,'reported',v_kind,v_occupancy.id,v_key
  ) returning * into v_incident;

  v_event_id:=private.workflow_enqueue_event_v1(
    v_incident.organization_id,'incident.created','incident',v_incident.id,
    'created',v_incident.property_id,v_incident.room_id,
    v_incident.opened_occupancy_id,
    jsonb_build_object(
      'incidentKind',v_incident.incident_kind,
      'category',v_incident.category,
      'priority',v_incident.priority
    ),v_actor,v_incident.created_at
  );

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_incident.organization_id,v_actor,'incident_opened','incident',
    v_incident.id::text,'success',
    jsonb_build_object(
      'property_id',v_incident.property_id,
      'room_id',v_incident.room_id,
      'incident_kind',v_incident.incident_kind,
      'priority',v_incident.priority,
      'request_key',v_key,
      'event_id',v_event_id
    )
  );

  return query select v_incident.id,v_incident.status,v_event_id,true;
end;
$$;
revoke all on function public.open_workflow_incident_v1(
  uuid,uuid,text,text,text,text,text
) from public,anon;
grant execute on function public.open_workflow_incident_v1(
  uuid,uuid,text,text,text,text,text
) to authenticated,service_role;

create function public.submit_incident_information_v1(
  p_incident_id uuid,
  p_request_key text,
  p_body text
)
returns table(
  incident_id uuid,
  update_id uuid,
  incident_status text,
  applied_new boolean
)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(p_request_key),'');
  v_body text:=nullif(btrim(p_body),'');
  v_incident public.incidents_v2;
  v_update public.incident_updates_v2;
begin
  if v_actor is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if v_key is null or length(v_key)>200 then
    raise exception 'incident_information_request_key_invalid' using errcode='22023';
  end if;
  if v_body is null or length(v_body)>5000 then
    raise exception 'incident_information_body_invalid' using errcode='22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_actor::text||':incident-information:'||p_incident_id::text||':'||v_key,0
    )
  );

  select * into v_incident
  from public.incidents_v2
  where id=p_incident_id
  for update;
  if v_incident.id is null then
    raise exception 'incident_not_found' using errcode='P0002';
  end if;
  if v_incident.created_by<>v_actor
    or not (
      private.incident_tenant_access_v1(v_incident.id,v_actor)
      or private.incident_internal_access_v1(
        v_incident.organization_id,v_incident.property_id,v_actor,false
      )
    ) then
    raise exception 'incident_information_forbidden' using errcode='42501';
  end if;

  select iu.* into v_update
  from public.incident_updates_v2 iu
  where iu.incident_id=v_incident.id
    and iu.author_user_id=v_actor
    and iu.request_key=v_key;
  if v_update.id is not null then
    if v_update.update_kind<>'information_response'
      or v_update.body<>v_body then
      raise exception 'incident_information_request_key_conflict' using errcode='55000';
    end if;
    return query select v_incident.id,v_update.id,v_incident.status,false;
    return;
  end if;

  if v_incident.status<>'waiting_info' then
    raise exception 'incident_not_waiting_information' using errcode='55000';
  end if;

  insert into public.incident_updates_v2(
    incident_id,author_user_id,visibility,body,update_kind,request_key
  ) values (
    v_incident.id,v_actor,
    case when v_incident.opened_occupancy_id is not null
      then 'tenant' else 'internal' end,
    v_body,'information_response',v_key
  ) returning * into v_update;

  insert into public.audit_log_v2(
    organization_id,actor_user_id,action,entity_type,entity_id,result,details
  ) values (
    v_incident.organization_id,v_actor,'incident_information_submitted',
    'incident',v_incident.id::text,'success',
    jsonb_build_object(
      'update_id',v_update.id,
      'request_key',v_key,
      'status',v_incident.status
    )
  );

  return query select v_incident.id,v_update.id,v_incident.status,true;
end;
$$;
revoke all on function public.submit_incident_information_v1(uuid,text,text)
  from public,anon;
grant execute on function public.submit_incident_information_v1(uuid,text,text)
  to authenticated,service_role;

comment on function public.open_workflow_incident_v1(
  uuid,uuid,text,text,text,text,text
) is
  'Opens one WF-05 incident idempotently and publishes incident.created to the shared WF-02 outbox; it never creates a task directly.';
comment on function public.submit_incident_information_v1(uuid,text,text) is
  'Stores one idempotent response while an incident waits for information; continuing remains an assignee workflow action.';
