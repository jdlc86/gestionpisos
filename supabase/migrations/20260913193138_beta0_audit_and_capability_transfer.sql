
create table public.audit_log_v2 (
  id bigint generated always as identity primary key,
  organization_id uuid references public.organizations(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  result text not null default 'success',
  details jsonb,
  created_at timestamptz not null default now()
);
alter table public.audit_log_v2 enable row level security;

create policy audit_log_v2_admin_read on public.audit_log_v2
for select to authenticated
using (
  (select auth.jwt()->'app_metadata'->>'role') = 'root'
  or (
    (select auth.jwt()->'app_metadata'->>'role') = 'admin'
    and organization_id::text = (select auth.jwt()->'app_metadata'->>'organization_id')
  )
);

create schema if not exists private;

create or replace function private.transfer_admin_capability(request_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth, private
as $$
declare
  req public.admin_capability_requests%rowtype;
  current_holder uuid;
  caller uuid := auth.uid();
  caller_role text := auth.jwt()->'app_metadata'->>'role';
  caller_org uuid := nullif(auth.jwt()->'app_metadata'->>'organization_id','')::uuid;
begin
  if caller is null then
    raise exception 'authentication required';
  end if;

  select * into req
  from public.admin_capability_requests
  where id = request_id
  for update;

  if not found then
    raise exception 'request not found';
  end if;

  if req.status <> 'pending' then
    raise exception 'request is not pending';
  end if;

  select holder_user_id into current_holder
  from public.admin_capability_holders
  where organization_id = req.organization_id
    and capability = req.capability
    and revoked_at is null
  for update;

  if caller_role <> 'root' then
    if caller_role <> 'admin' or caller_org is distinct from req.organization_id then
      raise exception 'not authorized';
    end if;
    if current_holder is distinct from caller then
      raise exception 'only current holder can approve transfer';
    end if;
  end if;

  update public.admin_capability_holders
  set holder_user_id = req.requester_user_id,
      granted_by = caller,
      granted_at = now(),
      revoked_at = null
  where organization_id = req.organization_id
    and capability = req.capability;

  if not found then
    insert into public.admin_capability_holders(
      organization_id, capability, holder_user_id, granted_by
    ) values (
      req.organization_id, req.capability, req.requester_user_id, caller
    );
  end if;

  update public.admin_capability_requests
  set status = 'approved',
      decided_at = now(),
      decided_by = caller
  where id = req.id;

  insert into public.audit_log_v2(
    organization_id, actor_user_id, action, entity_type, entity_id, details
  ) values (
    req.organization_id,
    caller,
    'admin_capability_transfer',
    'admin_capability',
    req.capability,
    jsonb_build_object('from_user_id', current_holder, 'to_user_id', req.requester_user_id, 'request_id', req.id)
  );
end;
$$;

revoke all on function private.transfer_admin_capability(uuid) from public;
grant execute on function private.transfer_admin_capability(uuid) to authenticated;
grant usage on schema private to authenticated;
