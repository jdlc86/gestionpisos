-- WF-04: la Baja real se publica en el outbox común; una reactivación de una
-- ocupación suspendida no es una Salida y no debe generar este evento.

alter table public.workflow_event_outbox_v2
  drop constraint workflow_event_outbox_v2_event_type_check;
alter table public.workflow_event_outbox_v2
  add constraint workflow_event_outbox_v2_event_type_check
  check (event_type in ('occupancy.created','occupancy.offboarded'));

-- Preservar el validador y la normalización WF-02 para todos los demás casos.
alter function private.workflow_sanitize_authoring_spec_v3(jsonb)
  rename to workflow_sanitize_authoring_spec_wf02_v3;
revoke all on function private.workflow_sanitize_authoring_spec_wf02_v3(jsonb)
  from public,anon,authenticated,service_role;

create function private.workflow_sanitize_authoring_spec_v3(p_spec jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_spec jsonb;
begin
  if p_spec->>'triggerType'='event'
    and p_spec->>'eventType'='occupancy.offboarded' then
    v_spec:=private.workflow_sanitize_authoring_spec_wf02_v3(
      p_spec || jsonb_build_object('eventType','occupancy.created')
    );
    return v_spec || jsonb_build_object('eventType','occupancy.offboarded');
  end if;
  return private.workflow_sanitize_authoring_spec_wf02_v3(p_spec);
end;
$$;
revoke all on function private.workflow_sanitize_authoring_spec_v3(jsonb)
  from public,anon,authenticated,service_role;

alter function public.workflow_authoring_complete_v1(jsonb)
  rename to workflow_authoring_complete_wf03_v1;
revoke all on function public.workflow_authoring_complete_wf03_v1(jsonb)
  from public,anon,authenticated,service_role;

create function public.workflow_authoring_complete_v1(p_spec jsonb)
returns boolean
language sql
immutable
security definer
set search_path=''
as $$
  select public.workflow_authoring_complete_wf03_v1(
    case when p_spec->>'triggerType'='event'
      and p_spec->>'eventType'='occupancy.offboarded'
      then p_spec || jsonb_build_object('eventType','occupancy.created')
      else p_spec end
  );
$$;
revoke all on function public.workflow_authoring_complete_v1(jsonb)
  from public,anon,service_role;
grant execute on function public.workflow_authoring_complete_v1(jsonb)
  to authenticated;

alter function private.workflow_enqueue_event_v1(
  uuid,text,text,uuid,text,uuid,uuid,uuid,jsonb,uuid,timestamptz
) rename to workflow_enqueue_event_wf02_v1;
revoke all on function private.workflow_enqueue_event_wf02_v1(
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
declare v_occ public.occupancies_v2; v_event_id uuid;
begin
  if p_event_type<>'occupancy.offboarded' then
    return private.workflow_enqueue_event_wf02_v1(
      p_organization_id,p_event_type,p_source_kind,p_source_id,p_event_key,
      p_property_id,p_room_id,p_occupancy_id,p_payload,p_actor_user_id,p_occurred_at
    );
  end if;

  if p_source_kind<>'occupancy'
    or p_source_id is null
    or p_occupancy_id is distinct from p_source_id
    or p_event_key<>'offboarded'
    or p_payload is null
    or jsonb_typeof(p_payload)<>'object' then
    raise exception 'workflow_event_source_invalid' using errcode='22023';
  end if;

  select * into v_occ from public.occupancies_v2 where id=p_source_id;
  if v_occ.id is null
    or v_occ.organization_id is distinct from p_organization_id
    or v_occ.property_id is distinct from p_property_id
    or v_occ.room_id is distinct from p_room_id
    or v_occ.status<>'archived' then
    raise exception 'workflow_event_routing_invalid' using errcode='22023';
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

-- La RPC de Baja es la única productora de offboarded. El camino atómico de
-- reactivación #274 archiva una ocupación bloqueada por otro motivo.
alter function public.offboard_tenant_occupancy_v2(uuid,date)
  set schema private;
revoke all on function private.offboard_tenant_occupancy_v2(uuid,date)
  from public,anon,authenticated,service_role;

create function public.offboard_tenant_occupancy_v2(
  p_occupancy_id uuid,
  p_ends_on date
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare v_before public.occupancies_v2; v_after public.occupancies_v2;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;

  select * into v_before
  from public.occupancies_v2 where id=p_occupancy_id;

  perform private.offboard_tenant_occupancy_v2(p_occupancy_id,p_ends_on);

  select * into v_after
  from public.occupancies_v2 where id=p_occupancy_id;
  if v_after.id is null or v_after.status<>'archived' then
    raise exception 'workflow_offboarding_state_invalid' using errcode='55000';
  end if;

  perform private.workflow_enqueue_event_v1(
    v_after.organization_id,'occupancy.offboarded','occupancy',v_after.id,
    'offboarded',v_after.property_id,v_after.room_id,v_after.id,
    jsonb_build_object(
      'previousStatus',v_before.status::text,
      'status',v_after.status::text,
      'endsOn',v_after.ends_on
    ),auth.uid(),now()
  );
end;
$$;
revoke all on function public.offboard_tenant_occupancy_v2(uuid,date)
  from public,anon;
grant execute on function public.offboard_tenant_occupancy_v2(uuid,date)
  to authenticated,service_role;

comment on function public.offboard_tenant_occupancy_v2(uuid,date) is
  'Conserva la Baja y revocación existentes y publica occupancy.offboarded en el outbox WF-02 sin crear tareas en la transacción de negocio.';
