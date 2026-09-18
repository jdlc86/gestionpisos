alter table public.occupancies_v2 alter column starts_on drop not null;
update public.occupancies_v2 set starts_on=null, ends_on=null, suspended_at=coalesce(suspended_at, now()) where status='blocked';
alter table public.occupancies_v2 drop constraint if exists occupancies_v2_dates_check;
alter table public.occupancies_v2 add constraint occupancies_v2_dates_check check (
  (status = 'blocked' and starts_on is null and ends_on is null and suspended_at is not null)
  or
  (status <> 'blocked' and starts_on is not null and (ends_on is null or ends_on >= starts_on))
);
alter table public.occupancies_v2 drop constraint if exists occupancies_v2_no_active_room_overlap;
alter table public.occupancies_v2 add constraint occupancies_v2_no_active_room_overlap exclude using gist (
 room_id with =,
 daterange(starts_on, coalesce(ends_on, 'infinity'::date), '[]') with &&
) where (status = 'active' and starts_on is not null);
