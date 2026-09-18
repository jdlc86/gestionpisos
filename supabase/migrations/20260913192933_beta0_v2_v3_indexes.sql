
create index if not exists properties_v2_org_idx on public.properties_v2(organization_id);
create index if not exists properties_v2_owner_idx on public.properties_v2(owner_id);
create index if not exists rooms_v2_property_idx on public.rooms_v2(property_id);

create index if not exists occupancies_v2_org_idx on public.occupancies_v2(organization_id);
create index if not exists occupancies_v2_property_idx on public.occupancies_v2(property_id);
create index if not exists occupancies_v2_room_idx on public.occupancies_v2(room_id);
create index if not exists occupancies_v2_user_idx on public.occupancies_v2(user_id);

create index if not exists property_staff_access_v3_property_idx on public.property_staff_access_v3(property_id);
create index if not exists property_staff_access_v3_granted_by_idx on public.property_staff_access_v3(granted_by);

create index if not exists property_qr_tokens_property_idx on public.property_qr_tokens(property_id);
create index if not exists property_qr_tokens_created_by_idx on public.property_qr_tokens(created_by);

create index if not exists access_requests_org_idx on public.access_requests(organization_id);
create index if not exists access_requests_property_idx on public.access_requests(property_id);
create index if not exists access_requests_requester_idx on public.access_requests(requester_user_id);
create index if not exists access_requests_decided_by_idx on public.access_requests(decided_by);
