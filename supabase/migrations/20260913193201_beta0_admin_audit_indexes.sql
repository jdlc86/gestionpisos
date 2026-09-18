
create index if not exists admin_capability_holders_granted_by_idx on public.admin_capability_holders(granted_by);
create index if not exists admin_capability_requests_decided_by_idx on public.admin_capability_requests(decided_by);
create index if not exists audit_log_v2_org_idx on public.audit_log_v2(organization_id);
create index if not exists audit_log_v2_actor_idx on public.audit_log_v2(actor_user_id);
