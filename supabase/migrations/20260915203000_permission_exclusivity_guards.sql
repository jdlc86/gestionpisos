-- Enforce the existing permissions model; do not introduce parallel role/access tables.
-- A responsibility remains current until explicitly revoked. valid_until is business metadata;
-- expiry processing must revoke the row before another responsible can be assigned.
create unique index if not exists property_staff_access_v3_one_current_responsible_per_property
on public.property_staff_access_v3(property_id)
where assignment_type='responsible' and revoked_at is null;

-- Exactly one current holder of each critical admin capability in an organization.
create unique index if not exists admin_capability_holders_one_current_holder
on public.admin_capability_holders(organization_id, capability)
where revoked_at is null;

-- Prevent duplicate simultaneous transfer requests from the same admin.
create unique index if not exists admin_capability_requests_one_pending_per_requester
on public.admin_capability_requests(organization_id, capability, requester_user_id)
where status='pending';
