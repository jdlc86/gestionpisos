create unique index if not exists property_staff_access_v3_one_current_responsible_per_property
on public.property_staff_access_v3(property_id)
where assignment_type='responsible' and revoked_at is null;

create unique index if not exists admin_capability_holders_one_current_holder
on public.admin_capability_holders(organization_id, capability)
where revoked_at is null;

create unique index if not exists admin_capability_requests_one_pending_per_requester
on public.admin_capability_requests(organization_id, capability, requester_user_id)
where status='pending';
