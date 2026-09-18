alter table public.occupancies_v2 drop constraint if exists occupancies_v2_dates_check;
alter table public.occupancies_v2 add constraint occupancies_v2_dates_check check (
 (status='blocked' and starts_on is null and ends_on is null and suspended_at is not null)
 or
 (status='archived' and starts_on is null and ends_on is null and suspended_at is not null)
 or
 (status <> 'blocked' and starts_on is not null and (ends_on is null or ends_on >= starts_on))
);
