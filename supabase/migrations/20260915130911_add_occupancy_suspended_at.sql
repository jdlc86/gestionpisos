alter table public.occupancies_v2 add column if not exists suspended_at timestamptz;
comment on column public.occupancies_v2.suspended_at is 'Timestamp of the current suspension transition. Null when the occupancy is not suspended.';
